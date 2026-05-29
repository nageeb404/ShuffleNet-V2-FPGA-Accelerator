// =============================================================================
// group2_fifo_ctrl.v -- FIFO Controller: 5-state FSM for Group 2 DW conv FIFO
// -----------------------------------------------------------------------------
// "FIFO Controller" / Figure 5.37, 5.38, 5.39
//
// "The FSM has 5 states ... it's normally in the IDLE state till the start
// signal comes from the 3by3 DWconv controller to start the FIFO operation."
// -- Sec 5.4.7.1
//
// States (Figure 5.39):
// IDLE : wait for start; all signals at default
// LOAD_ROW: "we load a row of data which is zero then W data then zero"
// LOAD_WIN: "we load a zero for padding then loads 2 data ... then go to PROCESS"
// PROCESS : "we give signals to the computation core that there is a valid window"
// LAST_PAD: load bottom zero-padding row to flush last windows
// (stride=1: always needed; stride=2: needed only when H is odd)
//
// PROCESS -> next state:
// not last row, stride=1 -> LOAD_WIN (Sec 5.4.7.1: "Load Window if stride 1")
// not last row, stride=2 -> LOAD_ROW (Sec 5.4.7.1: "Load Row if stride 2")
// last row, NEED_LAST_PAD -> LAST_PAD
// last row, !NEED_LAST_PAD -> IDLE + done pulse
//
// Outputs (Sec 5.4.7.1 / Fig 5.37):
// shift_and_load : 1 in LOAD_ROW / LOAD_WIN / PROCESS / LAST_PAD
// padding_sel : 1 at padding positions, 0 for data positions
// width_sel : 2-bit, from parameter W (same encoding as group2_fifo)
// rd_addr : feature-map memory read pointer (combinational)
// fsm_state : 3-bit state for use by dw_conv3x3_ctrl (Module 2.8)
// done : 1-cycle pulse when frame complete
//
// Column counts per state:
// LOAD_ROW : PADDED_W shifts (col_cnt 0..PADDED_W-1)
// LOAD_WIN : 3 shifts (col_cnt 0..2)
// PROCESS : PADDED_W-3 shifts (proc_cnt 0..PADDED_W-4)
// LAST_PAD : PADDED_W shifts (col_cnt 0..PADDED_W-1), all padding_sel=1
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module group2_fifo_ctrl #(
    parameter integer W      = `G2_W_MAX,  // feature map width: 7,14,28,56
    parameter integer H      = `G2_W_MAX,  // feature map height: 7,14,28,56
    parameter integer STRIDE = 2,          // 1 (stride-1 block) or 2 (stride-2)
    parameter integer PAD    = 1,          // zero-padding per side (always 1)
    parameter integer AW     = 12          // rd_addr bit width (ceil log2 of depth)
) (
    input  wire clk,
    input  wire rst,
    input  wire start,         // begin frame (from dw_conv3x3_ctrl)

    output reg         shift_and_load, // to group2_fifo
    output reg         padding_sel,    // to group2_fifo
    output wire [1:0]  width_sel,      // to group2_fifo (Sec 5.4.6 Fig 5.38)
    output wire [AW-1:0] rd_addr,      // feature-map read address (comb from rd_ptr)
    output wire [2:0]  fsm_state,      // current state (for dw_conv3x3_ctrl)
    output reg         done            // 1-cycle pulse when all rows complete
);

    // -------------------------------------------------------------------------
    // Derived constants
    // -------------------------------------------------------------------------
    localparam integer PADDED_W    = W + 2 * PAD;               // padded row width
    localparam integer OUT_H       = (H + 2*PAD - 3) / STRIDE + 1; // output rows
    localparam integer LDROW_LAST  = PADDED_W - 1;              // last col in LOAD_ROW
    localparam integer LDWIN_LAST  = 2;                         // 3 shifts: 0,1,2
    localparam integer PROC_LAST   = PADDED_W - 4;              // last proc_cnt

    // NEED_LAST_PAD: 1 if the last output row requires loading the bottom padding.
    // stride=1: always needed -- last output row uses bottom_pad as its 3rd row.
    // stride=2: in the actual ShuffleNet V2 architecture, all stride-2 DW conv
    // blocks have even H (56, 28, 14), so NEED_LAST_PAD=0. For odd H
    // (H=7) we still compute it correctly for generality.
    localparam integer NEED_LAST_PAD = (STRIDE == 1) ? 1 : (H & 1);

    // width_sel encoding (Sec 5.4.6 / Fig 5.38):
    // 00=W7, 01=W14, 10=W28, 11=W56
    localparam [1:0] WS = (W == 7)  ? 2'b00 :
                          (W == 14) ? 2'b01 :
                          (W == 28) ? 2'b10 : 2'b11;
    assign width_sel = WS;

    // -------------------------------------------------------------------------
    // State encoding
    // -------------------------------------------------------------------------
    localparam [2:0] S_IDLE    = 3'd0;
    localparam [2:0] S_LDROW   = 3'd1;
    localparam [2:0] S_LDWIN   = 3'd2;
    localparam [2:0] S_PROCESS = 3'd3;
    localparam [2:0] S_LASTPAD = 3'd4;

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    reg [2:0]    state;
    reg [7:0]    col_cnt;   // column counter in LOAD_ROW, LOAD_WIN, LAST_PAD
    reg [7:0]    proc_cnt;  // column counter in PROCESS
    reg [6:0]    row_cnt;   // output row counter (0..OUT_H-1)
    reg [AW-1:0] rd_ptr;    // feature-map read pointer (linear)

    assign rd_addr  = rd_ptr;
    assign fsm_state = state;

    // -------------------------------------------------------------------------
    // Sequential FSM + counter + pointer logic
    // -------------------------------------------------------------------------
    // Ch 6.2.2: rst removed from FSM sensitivity list and body to eliminate the
    // async-reset high-fanout net. FFs initialize to 0 at FPGA configuration,
    // placing the FSM in S_IDLE (= 3'd0) with all counters at zero -- correct
    // initial state. rst port kept for interface compatibility.
    always @(posedge clk) begin : fsm_main
        begin
            done <= 1'b0;   // default: no done pulse

            case (state)

                // =============================================================
                // IDLE
                // "in that state we reset the FIFOs content and all signals are
                // set to default values waiting for start signal" -- Sec 5.4.7.1
                // FIFO registers are cleared by external rst; we hold still here.
                // =============================================================
                S_IDLE: begin
                    shift_and_load <= 1'b0;
                    // Ch 6.2.2: keep padding_sel=1 in IDLE so the continuously-
                    // shifting FIFO stays filled with zeros (replaces FIFO rst).
                    padding_sel    <= 1'b1;
                    col_cnt        <= 8'd0;
                    proc_cnt       <= 8'd0;
                    row_cnt        <= 7'd0;
                    rd_ptr         <= {AW{1'b0}};
                    if (start)
                        state <= S_LDROW;
                end

                // =============================================================
                // LOAD_ROW
                // "we load a row of data which is zero then W data then zero"
                // -- Sec 5.4.7.1
                // col_cnt 0 : left padding zero
                // col_cnt 1..W : data from feature-map memory
                // col_cnt LDROW_LAST : right padding zero -> go to LOAD_WIN
                // =============================================================
                S_LDROW: begin
                    shift_and_load <= 1'b1;

                    if (col_cnt == 8'd0 || col_cnt == LDROW_LAST[7:0]) begin
                        padding_sel <= 1'b1;   // padding positions
                    end else begin
                        padding_sel <= 1'b0;   // data position
                        rd_ptr      <= rd_ptr + 1'b1;
                    end

                    if (col_cnt == LDROW_LAST[7:0]) begin
                        col_cnt <= 8'd0;
                        state   <= S_LDWIN;
                    end else begin
                        col_cnt <= col_cnt + 8'd1;
                    end
                end

                // =============================================================
                // LOAD_WIN
                // "we load a zero for padding then loads 2 data from memory and
                // then we go to the process state" -- Sec 5.4.7.1
                // col_cnt 0 : left padding zero
                // col_cnt 1 : first data pixel
                // col_cnt 2 : second data pixel -> -> PROCESS
                // =============================================================
                S_LDWIN: begin
                    shift_and_load <= 1'b1;

                    if (col_cnt == 8'd0) begin
                        padding_sel <= 1'b1;   // left pad zero
                    end else begin
                        padding_sel <= 1'b0;   // data pixel
                        rd_ptr      <= rd_ptr + 1'b1;
                    end

                    if (col_cnt == LDWIN_LAST[7:0]) begin
                        col_cnt  <= 8'd0;
                        proc_cnt <= 8'd0;
                        state    <= S_PROCESS;
                    end else begin
                        col_cnt <= col_cnt + 8'd1;
                    end
                end

                // =============================================================
                // PROCESS
                // "we give signals to the computation core that there is a valid
                // window of data" -- Sec 5.4.7.1
                // proc_cnt 0..PROC_LAST-1 : data pixels (advance rd_ptr)
                // proc_cnt PROC_LAST : right padding zero
                //
                // After last PROCESS element:
                // last row + NEED_LAST_PAD -> LAST_PAD
                // last row + !NEED_LAST_PAD -> IDLE (done)
                // not last row, stride=1 -> LOAD_WIN
                // not last row, stride=2 -> LOAD_ROW
                // =============================================================
                S_PROCESS: begin
                    shift_and_load <= 1'b1;

                    if (proc_cnt == PROC_LAST[7:0]) begin
                        padding_sel <= 1'b1;   // right padding zero
                    end else begin
                        padding_sel <= 1'b0;
                        rd_ptr      <= rd_ptr + 1'b1;
                    end

                    if (proc_cnt == PROC_LAST[7:0]) begin
                        proc_cnt <= 8'd0;
                        // When NEED_LAST_PAD=1: enter LAST_PAD one output row early
                        // (at OUT_H-2) so LAST_PAD handles the final output row by
                        // loading the bottom zero-padding instead of reading OOB data.
                        // When NEED_LAST_PAD=0: all rows covered by PROCESS; done at OUT_H-1.
                        if (NEED_LAST_PAD) begin
                            if (row_cnt == (OUT_H - 2)) begin
                                col_cnt <= 8'd0;
                                state   <= S_LASTPAD;
                            end else begin
                                row_cnt <= row_cnt + 7'd1;
                                col_cnt <= 8'd0;
                                state   <= (STRIDE == 1) ? S_LDWIN : S_LDROW;
                            end
                        end else begin
                            if (row_cnt == (OUT_H - 1)) begin
                                state <= S_IDLE;
                                done  <= 1'b1;
                            end else begin
                                row_cnt <= row_cnt + 7'd1;
                                col_cnt <= 8'd0;
                                state   <= S_LDROW; // stride-2 only when !NEED_LAST_PAD
                            end
                        end
                    end else begin
                        proc_cnt <= proc_cnt + 8'd1;
                    end
                end

                // =============================================================
                // LAST_PAD
                // Load the bottom zero-padding row to flush the last set of
                // valid windows through the FIFO (Sec 5.4.7.1 "Last Padding").
                // All elements are zeros (padding_sel=1 always).
                // col_cnt 0..PADDED_W-1 -> IDLE + done
                // =============================================================
                S_LASTPAD: begin
                    shift_and_load <= 1'b1;
                    padding_sel    <= 1'b1;

                    if (col_cnt == LDROW_LAST[7:0]) begin
                        col_cnt <= 8'd0;
                        state   <= S_IDLE;
                        done    <= 1'b1;
                    end else begin
                        col_cnt <= col_cnt + 8'd1;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule

`default_nettype wire
// =============================================================================
// END group2_fifo_ctrl.v
// =============================================================================
