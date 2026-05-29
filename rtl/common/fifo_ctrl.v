// =============================================================================
// fifo_ctrl.v -- FIFO Controller: 4-state FSM for 3x3 conv and maxpool FIFOs
// -----------------------------------------------------------------------------
// "3x3 Convolution FIFOs Controller" / Figure 5.14
//
// "The main purpose of this controller is to manage the storage data in the
// FIFO to solve the padding problem." -- Sec 5.3.4.1
//
// "The Controller is implemented as a finite state machine with four states"
// 1) IDLE -- reset FIFOs, wait for start
// 2) LOAD_ROW -- load one padded row: 0, W data pixels, 0 (W=IMG_W)
// 3) LOAD_WIN -- load 3 elements of the next row: 0, data, data
// 4) PROCESS -- finish loading current computation row; FIFOs advance
//
// Transitions (Fig 5.14, row_counter increments on each state change):
// IDLE -> LOAD_ROW on start
// LOAD_ROW -> LOAD_WIN after PADDED_W columns loaded
// LOAD_WIN -> PROCESS after 3 elements loaded
// PROCESS -> LOAD_ROW if more output rows remain (stride-2 skip row)
// PROCESS -> IDLE if last output row processed; asserts done
//
// Outputs driven by this module (Sec 5.3.4.1):
// shift_and_load : 1 in LOAD_ROW, LOAD_WIN, PROCESS; 0 in IDLE
// padding_sel : 1 at padding positions, 0 for data positions
// rd_addr : photo-memory read address (= rd_ptr, combinational)
// fsm_state : current state (for group1_ctrl, Module 1.12)
// done : 1-cycle pulse when last output row finishes
//
// NOTE on memory timing: rd_addr is combinationally driven from rd_ptr.
// For LUT ROM it is zero-latency. For BRAM (photo_mem) the group1_top
// must register or offset rd_addr by one cycle to meet BRAM latency.
//
// Parameters:
// IMG_W : unpadded image width (224 for Group1 conv; 112 for maxpool)
// IMG_H : unpadded image height
// PAD : zero-padding on each side (1 for both Group1 blocks)
// STRIDE : row skip stride (2 for Group1 stride-2 conv and maxpool)
// AW : rd_addr width (PHOTO_MEM_AW=16 for Group1 conv)
//
// Padded dimensions:
// PADDED_W = IMG_W + 2*PAD (226 for Group1 conv)
// OUT_H = (IMG_H + 2*PAD - 3) / STRIDE + 1 (112 for Group1 conv)
//
// Column accounting per output row:
// LOAD_ROW : PADDED_W shifts (col 0=left-pad, 1..IMG_W=data, PADDED_W-1=right-pad)
// LOAD_WIN : 3 shifts (col_cnt 0=left-pad, 1=data, 2=data)
// PROCESS : PADDED_W-3 shifts (col_cnt 0..PADDED_W-4=data, PADDED_W-3-1=right-pad)
// i.e. proc_cnt 0..PROC_LAST where PROC_LAST = PADDED_W-4 = 222
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module fifo_ctrl #(
    parameter integer IMG_W  = `IMG_W,         // 224 (unpadded)
    parameter integer IMG_H  = `IMG_H,         // 224
    parameter integer PAD    = 1,              // zero padding per side
    parameter integer STRIDE = 2,             // row-skip stride
    parameter integer AW     = `PHOTO_MEM_AW  // rd_addr width (16)
) (
    input  wire        clk,
    input  wire        rst,          // async active-high ()
    input  wire        start,        // begin frame (from group1_ctrl)

    // --- FIFO controls (identical to all channel instances) ---
    output reg         shift_and_load,  // Sec 5.3.3 / Fig 5.13
    output reg         padding_sel,     // 1=zero, 0=data_in

    // --- Photo-memory read address ---
    output wire [AW-1:0] rd_addr,       // combinational: rd_addr = rd_ptr

    // --- Status (consumed by group1_ctrl, Module 1.12) ---
    output reg  [1:0]  fsm_state,   // 0=IDLE,1=LOAD_ROW,2=LOAD_WIN,3=PROCESS
    output reg         done          // 1-cycle pulse: all OUT_H rows done
);

    // -------------------------------------------------------------------------
    // Derived constants
    // -------------------------------------------------------------------------
    localparam integer PADDED_W  = IMG_W + 2 * PAD;                   // 226
    localparam integer OUT_H     = (IMG_H + 2*PAD - 3) / STRIDE + 1;  // 112

    // Max column counter in LOAD_ROW (0 .. PADDED_W-1)
    localparam integer LDROW_LAST = PADDED_W - 1;   // 225
    // Max col_cnt in LOAD_WIN (0 .. 2)
    localparam integer LDWIN_LAST = 2;
    // Max proc_cnt in PROCESS (0 .. PADDED_W-4)
    localparam integer PROC_LAST  = PADDED_W - 4;   // 222

    // -------------------------------------------------------------------------
    // State encoding
    // -------------------------------------------------------------------------
    localparam [1:0] S_IDLE    = 2'd0;
    localparam [1:0] S_LDROW   = 2'd1;
    localparam [1:0] S_LDWIN   = 2'd2;
    localparam [1:0] S_PROCESS = 2'd3;

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    reg [1:0]  state;
    reg [8:0]  col_cnt;   // LOAD_ROW / LOAD_WIN column counter (0..225)
    reg [8:0]  proc_cnt;  // PROCESS column counter (0..222)
    reg [6:0]  row_cnt;   // output row counter (0..111)
    reg [AW-1:0] rd_ptr;  // linear photo-memory read pointer (0..50175)

    // rd_addr is combinational from rd_ptr (see timing note in header)
    assign rd_addr = rd_ptr;

    // fsm_state mirrors state
    always @(*) fsm_state = state;

    // -------------------------------------------------------------------------
    // Sequential FSM + counter + pointer logic
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin : fsm_main
        if (rst) begin
            state          <= S_IDLE;
            col_cnt        <= 9'd0;
            proc_cnt       <= 9'd0;
            row_cnt        <= 7'd0;
            rd_ptr         <= {AW{1'b0}};
            shift_and_load <= 1'b0;
            padding_sel    <= 1'b0;
            done           <= 1'b0;
        end else begin
            done <= 1'b0;   // default: no done pulse

            case (state)

                // ============================================================
                // IDLE
                // "in that state we reset the FIFOs content and all signals
                // are set to default values waiting for start signal."
                // -- Sec 5.3.4.1
                // FIFOs are zeroed by the external rst; we just hold still.
                // ============================================================
                S_IDLE: begin
                    shift_and_load <= 1'b0;
                    padding_sel    <= 1'b0;
                    col_cnt        <= 9'd0;
                    proc_cnt       <= 9'd0;
                    row_cnt        <= 7'd0;
                    rd_ptr         <= {AW{1'b0}};
                    if (start)
                        state <= S_LDROW;
                end

                // ============================================================
                // LOAD_ROW
                // "we load a row of data which is zero then W data then zero"
                // -- Sec 5.3.4.1
                // col_cnt 0 : left padding zero
                // col_cnt 1..IMG_W : data pixels from photo memory
                // col_cnt PADDED_W-1 : right padding zero
                // ============================================================
                S_LDROW: begin
                    shift_and_load <= 1'b1;

                    // Determine padding vs data
                    if (col_cnt == 9'd0 ||
                        col_cnt == LDROW_LAST[8:0]) begin
                        // Padding position: load zero into FIFO
                        padding_sel <= 1'b1;
                    end else begin
                        // Data position: FIFO gets photo-memory output
                        padding_sel <= 1'b0;
                    end

                    // Advance rd_ptr after EACH data read
                    // Data positions: col_cnt 1 .. IMG_W
                    // We increment at the NEXT cycle (to let the current
                    // address settle on rd_addr this cycle).
                    if (col_cnt >= 9'd1 && col_cnt < IMG_W[8:0]) begin
                        // mid-data: advance pointer
                        rd_ptr <= rd_ptr + 1'b1;
                    end else if (col_cnt == IMG_W[8:0]) begin
                        // last data col: advance pointer; next cycle = right pad
                        rd_ptr <= rd_ptr + 1'b1;
                    end

                    // Counter and transition
                    if (col_cnt == LDROW_LAST[8:0]) begin
                        col_cnt <= 9'd0;
                        state   <= S_LDWIN;
                    end else begin
                        col_cnt <= col_cnt + 9'd1;
                    end
                end

                // ============================================================
                // LOAD_WIN
                // "It loads a zero for padding then loads 2 data from memory
                // and then we go to the process state." -- Sec 5.3.4.1
                // col_cnt 0 : left padding zero of the new row
                // col_cnt 1 : first data pixel of new row
                // col_cnt 2 : second data pixel of new row -> -> PROCESS
                // ============================================================
                S_LDWIN: begin
                    shift_and_load <= 1'b1;

                    if (col_cnt == 9'd0) begin
                        padding_sel <= 1'b1;    // left padding zero
                    end else begin
                        padding_sel <= 1'b0;    // data pixel
                        // Advance ptr after each of the 2 data loads
                        rd_ptr <= rd_ptr + 1'b1;
                    end

                    if (col_cnt == LDWIN_LAST[8:0]) begin
                        col_cnt  <= 9'd0;
                        proc_cnt <= 9'd0;
                        state    <= S_PROCESS;
                    end else begin
                        col_cnt <= col_cnt + 9'd1;
                    end
                end

                // ============================================================
                // PROCESS
                // "keep loading data to get the new window and so on until we
                // process all possible windows in that row." -- Sec 5.3.4.1
                //
                // Loads PADDED_W - 3 = 223 elements:
                // proc_cnt 0 .. PROC_LAST-1 (= 0..221): data (222 pixels)
                // proc_cnt PROC_LAST (= 222) : right padding zero
                //
                // Stride-2 row handling (Sec 5.3.4.1):
                // "If the convolution was stride 2 so we need to skip a row,
                // we go to the load row state to load a row without
                // processing it."
                // -> PROCESS -> LOAD_ROW if row_cnt < OUT_H-1
                // -> PROCESS -> IDLE if row_cnt == OUT_H-1 (last row)
                // ============================================================
                S_PROCESS: begin
                    shift_and_load <= 1'b1;

                    if (proc_cnt == PROC_LAST[8:0]) begin
                        // Right padding zero (last element of this padded row)
                        padding_sel <= 1'b1;
                    end else begin
                        // Data pixel
                        padding_sel <= 1'b0;
                        rd_ptr      <= rd_ptr + 1'b1;
                    end

                    if (proc_cnt == PROC_LAST[8:0]) begin
                        // Completed all PADDED_W elements for this output row
                        proc_cnt <= 9'd0;
                        if (row_cnt == (OUT_H - 1)) begin
                            // Last output row done -> IDLE
                            state <= S_IDLE;
                            done  <= 1'b1;
                        end else begin
                            // Load skip row (stride 2 in Y) -> LOAD_ROW
                            row_cnt <= row_cnt + 7'd1;
                            col_cnt <= 9'd0;
                            state   <= S_LDROW;
                        end
                    end else begin
                        proc_cnt <= proc_cnt + 9'd1;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule

`default_nettype wire
// =============================================================================
// END fifo_ctrl.v
// =============================================================================
