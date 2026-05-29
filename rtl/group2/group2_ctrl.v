// =============================================================================
// group2_ctrl.v -- Group 2 top-level Shuffle Unit sequencer (Module 2.10)
// -----------------------------------------------------------------------------
// "Group 2 Controller" / Figures 5.51, 5.52, 5.53, 5.54
//
// Path A modification (ZU19EG): sequential DW-then-PW phasing.
// Original design fires both DW and PW start simultaneously (Sec 5.4.7.4).
// Modified: DW phase completes first (all pixels written to internal DW buffer),
// then PW phase starts (reads from DW buffer). Ensures DW output is available
// before PW begins. ~4.75% throughput overhead for correctness.
//
// START ENCODING (modified from original):
// start[0] = 1 -- DW start (fires when DW phase begins for any config)
// start[1] = 1 -- PW start (fires when PW phase begins, after done_dw)
// gc_width + gc_stride: config identification (unchanged; stable during block)
//
// SEQUENCING (modified):
// New block: start[0]=1 -> DW runs -> done_dw -> start[1]=1 -> PW runs
// -> done_1x1 -> advance loop -> next block start[0]=1
//
// ARCHITECTURE (unchanged from original):
// Group 2 consists of 16 Shuffle unit blocks split into 3 stages (Fig 5.15):
// Stage 2: 1 stride-2 block + 3 stride-1 blocks (loops 0..3)
// Stage 3: 1 stride-2 block + 7 stride-1 blocks (loops 4..11)
// Stage 4: 1 stride-2 block + 3 stride-1 blocks (loops 12..15)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module group2_ctrl (
    input  wire clk,
    input  wire rst,
    input  wire start_group,  // from Accelerator ctrl (begin Group 2)
    input  wire done_dw,      // from dw_conv3x3_ctrl (done3_3_G)
    input  wire done_1x1,     // from conv1x1_ctrl (done1_1_G)

    output reg  [1:0] start,      // 2-bit start: [0]=DW start, [1]=PW start
    output wire [5:0] width,      // current feature map width
    output wire       stride,     // current stride (0=stride-1, 1=stride-2)
    output wire [1:0] fsm_state,  // 0=IDLE 1=S2 2=S3 3=S4
    output wire [4:0] loops,      // loop counter 0..16
    output reg        group2_done // all 16 Shuffle blocks complete
);

    // -------------------------------------------------------------------------
    // State encoding
    // -------------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_S2   = 2'd1;  // Stage 2: loops 0..3
    localparam [1:0] S_S3   = 2'd2;  // Stage 3: loops 4..11
    localparam [1:0] S_S4   = 2'd3;  // Stage 4: loops 12..15

    localparam integer LOOPS_S2_END = 4;   // loops 0..3
    localparam integer LOOPS_S3_END = 12;  // loops 4..11
    localparam integer LOOPS_S4_END = 16;  // loops 12..15

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    reg [1:0] state;
    reg [4:0] loops_r;
    reg       got_dw;   // done_dw latched (for case where done arrives 1 cycle early)
    reg       got_1x1;  // done_1x1 latched
    reg       waiting;
    reg       phase;    // 0=DW phase, 1=PW phase

    assign fsm_state = state;
    assign loops     = loops_r;

    // -------------------------------------------------------------------------
    // Width and stride ( - unchanged)
    // -------------------------------------------------------------------------
    reg [5:0] width_r;
    reg       stride_r;
    assign width  = width_r;
    assign stride = stride_r;

    function is_stride2;
        input [4:0] lp;
        begin
            is_stride2 = (lp == 5'd0 || lp == 5'd4 || lp == 5'd12);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Sequential FSM ( -- modified for sequential DW/PW)
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin : fsm_main
        if (rst) begin
            state       <= S_IDLE;
            loops_r     <= 5'd0;
            got_dw      <= 1'b0;
            got_1x1     <= 1'b0;
            waiting     <= 1'b0;
            phase       <= 1'b0;
            start       <= 2'b00;
            width_r     <= 6'd56;
            stride_r    <= 1'b1;
            group2_done <= 1'b0;
        end else begin
            start       <= 2'b00;   // default: no start pulse
            group2_done <= 1'b0;

            case (state)

                // =============================================================
                // IDLE: wait for start_group
                // =============================================================
                S_IDLE: begin
                    loops_r  <= 5'd0;
                    got_dw   <= 1'b0;
                    got_1x1  <= 1'b0;
                    waiting  <= 1'b0;
                    phase    <= 1'b0;
                    width_r  <= 6'd56;
                    stride_r <= 1'b1;

                    if (start_group) begin
                        state   <= S_S2;
                        start   <= 2'b01;  // DW start for first block (stride-2, W=56)
                        phase   <= 1'b0;
                        waiting <= 1'b1;
                    end
                end

                // =============================================================
                // S2 / S3 / S4: sequential DW-then-PW per Shuffle block.
                //
                // Phase 0 (DW):
                // Wait for done_dw; then fire start[1]=1 (PW start), phase->1.
                //
                // Phase 1 (PW):
                // Wait for done_1x1; then advance loop counter, fire start[0]=1
                // (DW start for next block), phase->0.
                // If last block: go to IDLE and assert group2_done.
                // =============================================================
                S_S2, S_S3, S_S4: begin

                    if (waiting) begin

                        // ---- Phase 0: DW running, wait for done_dw ----
                        if (phase == 1'b0) begin
                            if (done_dw) got_dw <= 1'b1;

                            if (got_dw || done_dw) begin
                                // DW complete: clear latch and start PW
                                got_dw  <= 1'b0;
                                phase   <= 1'b1;
                                start   <= 2'b10;   // PW start (bit 1)
                            end

                        // ---- Phase 1: PW running, wait for done_1x1 ----
                        end else begin
                            if (done_1x1) got_1x1 <= 1'b1;

                            if (got_1x1 || done_1x1) begin
                                // PW complete: advance block
                                got_1x1 <= 1'b0;
                                phase   <= 1'b0;
                                loops_r <= loops_r + 5'd1;

                                if (loops_r + 5'd1 == LOOPS_S4_END[4:0]) begin
                                    // All 16 blocks complete
                                    waiting     <= 1'b0;
                                    state       <= S_IDLE;
                                    group2_done <= 1'b1;

                                end else if (loops_r + 5'd1 == LOOPS_S2_END[4:0]) begin
                                    // Stage 2 -> Stage 3 transition
                                    state    <= S_S3;
                                    width_r  <= 6'd28;
                                    stride_r <= 1'b1;    // stride-2 first block in S3
                                    start    <= 2'b01;   // DW start
                                    waiting  <= 1'b1;

                                end else if (loops_r + 5'd1 == LOOPS_S3_END[4:0]) begin
                                    // Stage 3 -> Stage 4 transition
                                    state    <= S_S4;
                                    width_r  <= 6'd14;
                                    stride_r <= 1'b1;    // stride-2 first block in S4
                                    start    <= 2'b01;   // DW start
                                    waiting  <= 1'b1;

                                end else begin
                                    // More blocks in current stage
                                    if (is_stride2(loops_r + 5'd1)) begin
                                        stride_r <= 1'b1;
                                    end else begin
                                        stride_r <= 1'b0;
                                        if (loops_r + 5'd1 == 5'd1)
                                            width_r <= 6'd28;
                                        else if (loops_r + 5'd1 == 5'd5)
                                            width_r <= 6'd14;
                                        else if (loops_r + 5'd1 == 5'd13)
                                            width_r <= 6'd7;
                                        // else: stride-1 keeps same width
                                    end
                                    start   <= 2'b01;   // DW start for next block
                                    waiting <= 1'b1;
                                end

                            end // got_1x1 || done_1x1
                        end // phase == 1

                    end // waiting

                end // S_S2/S_S3/S_S4

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule

`default_nettype wire
// =============================================================================
// END group2_ctrl.v
// =============================================================================
