// =============================================================================
// accelerator_ctrl.v -- Top-level Accelerator Controller (Module 4.1)
// -----------------------------------------------------------------------------
// "Accelerator Controller" / Figures 5.69, 5.70, 5.71
//
// "The accelerator controller is the central FSM that orchestrates all three
// groups of the ShuffleNet accelerator and manages the pipelined execution
// of consecutive input images." -- Sec 5.6
//
// FSM (Figure 5.70) -- 5 states encoding which groups are ACTIVE:
// IDLE : No groups running. Wait for photo_ready.
// G1 : Group 1 only. Wait for group1_done.
// G1_2 : Groups 1 & 2. Wait for group2_done.
// G1_2_3 : All 3 groups. Wait for group3_done.
// G1_3 : Groups 1 & 3. Wait for both done (flag-latched).
//
// PIPELINED OPERATION ():
// Each group processes a DIFFERENT image simultaneously:
// G1 processes image N+1 while G2 processes image N, G3 processes N-1.
// start pulses are 1-cycle and correspond to each group accepting a new frame.
//
// FLAG STORAGE (Figure 5.71):
// In state G1_3, done pulses may arrive at different cycles.
// done1_flag and done3_flag latch each pulse and are both checked together.
//
// PORT MAP:
// clk, rst -- system clock / async reset
// photo_ready -- from image source: new image available in photo memory
// group1_done -- 1-cycle pulse from group1_top (frame complete)
// group2_done -- 1-cycle pulse from group2_top (frame complete)
// group3_done -- 1-cycle pulse from group3_top (frame complete)
// group1_start -- 1-cycle pulse to group1_top (begin new frame)
// group2_start -- 1-cycle pulse to group2_top (begin new frame)
// group3_start -- 1-cycle pulse to group3_top (begin new frame)
// busy -- high while Group 1 or Group 2 is active
// (tells image source to wait before writing next image)
// ping_pong_sel -- toggles on each new image accepted by Group 1
// (selects which photo memory bank G1 reads from)
// fsm_state -- current FSM state (for debug)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module accelerator_ctrl (
    input  wire clk,
    input  wire rst,

    // Handshake with image source
    input  wire photo_ready,   // new image is ready in photo memory
    output reg  busy,          // asserted while G1 or G2 active (back-pressure)

    // Group control
    output reg  group1_start,  // 1-cycle pulse to Group 1
    output reg  group2_start,  // 1-cycle pulse to Group 2
    output reg  group3_start,  // 1-cycle pulse to Group 3

    // Group status
    input  wire group1_done,   // 1-cycle pulse from Group 1
    input  wire group2_done,   // 1-cycle pulse from Group 2
    input  wire group3_done,   // 1-cycle pulse from Group 3

    // Photo memory bank select
    output reg  ping_pong_sel,

    // Debug
    output wire [2:0] fsm_state
);

    // -------------------------------------------------------------------------
    // State encoding
    // -------------------------------------------------------------------------
    localparam [2:0] S_IDLE    = 3'd0;
    localparam [2:0] S_G1      = 3'd1;
    localparam [2:0] S_G1_2    = 3'd2;
    localparam [2:0] S_G1_2_3  = 3'd3;
    localparam [2:0] S_G1_3    = 3'd4;

    reg [2:0] state;
    assign fsm_state = state;

    // Flag registers (Figure 5.71): latch done pulses in G1_3
    reg done1_flag;  // group1_done received in G1_3
    reg done3_flag;  // group3_done received in G1_3

    // -------------------------------------------------------------------------
    // Sequential FSM ()
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin : fsm_seq
        if (rst) begin
            state         <= S_IDLE;
            group1_start  <= 1'b0;
            group2_start  <= 1'b0;
            group3_start  <= 1'b0;
            busy          <= 1'b0;
            ping_pong_sel <= 1'b0;
            done1_flag    <= 1'b0;
            done3_flag    <= 1'b0;
        end else begin
            // Default: clear pulse outputs
            group1_start <= 1'b0;
            group2_start <= 1'b0;
            group3_start <= 1'b0;

            case (state)

                // =============================================================
                // IDLE: wait for photo_ready -> start Group 1
                // =============================================================
                S_IDLE: begin
                    busy       <= 1'b0;
                    done1_flag <= 1'b0;
                    done3_flag <= 1'b0;
                    if (photo_ready) begin
                        state        <= S_G1;
                        group1_start <= 1'b1;
                        ping_pong_sel<= ~ping_pong_sel;  // toggle bank
                        busy         <= 1'b1;
                    end
                end

                // =============================================================
                // G1: Group 1 running.
                // When done: start Group 2.
                // If new image ready: also restart Group 1 for it.
                // =============================================================
                S_G1: begin
                    busy <= 1'b1;
                    if (group1_done) begin
                        // Start Group 2 with the frame Group 1 just completed
                        group2_start <= 1'b1;

                        if (photo_ready) begin
                            // New image ready: restart G1, go to G1_2
                            state        <= S_G1_2;
                            group1_start <= 1'b1;
                            ping_pong_sel<= ~ping_pong_sel;
                        end else begin
                            // No new image: G2 alone -- still go to G1_2
                            // (G1_2 state: G1 is NOT running, only G2 is)
                            // We stay here treating G1_2 as "G2 only" for now
                            state <= S_G1_2;
                        end
                    end
                end

                // =============================================================
                // G1_2: Groups 1 and/or 2 running.
                // When Group 2 done: start Group 3.
                // =============================================================
                S_G1_2: begin
                    busy <= 1'b1;
                    if (group2_done) begin
                        // Start Group 3
                        group3_start <= 1'b1;
                        state        <= S_G1_2_3;
                    end
                end

                // =============================================================
                // G1_2_3: All three groups running.
                // When Group 3 done:
                // If photo_ready: start G1 for next image -> G1_3
                // Else: back to IDLE
                // =============================================================
                S_G1_2_3: begin
                    busy <= 1'b1;
                    if (group3_done) begin
                        if (photo_ready) begin
                            state        <= S_G1_3;
                            group1_start <= 1'b1;
                            ping_pong_sel<= ~ping_pong_sel;
                            done1_flag   <= 1'b0;
                            done3_flag   <= 1'b0;
                        end else begin
                            state <= S_IDLE;
                            busy  <= 1'b0;
                        end
                    end
                end

                // =============================================================
                // G1_3: Groups 1 and 3 running.
                // Latch done pulses; when both received:
                // If photo_ready: start G2 (and G1) -> G1_2
                // Else: back to IDLE
                // =============================================================
                S_G1_3: begin
                    busy <= 1'b1;
                    // Latch done flags (pulses may arrive in any order)
                    if (group1_done) done1_flag <= 1'b1;
                    if (group3_done) done3_flag <= 1'b1;

                    // Both done (accounting for same-cycle arrival)
                    if ((done1_flag || group1_done) &&
                        (done3_flag || group3_done)) begin
                        done1_flag <= 1'b0;
                        done3_flag <= 1'b0;
                        if (photo_ready) begin
                            state        <= S_G1_2;
                            group2_start <= 1'b1;
                            group1_start <= 1'b1;
                            ping_pong_sel<= ~ping_pong_sel;
                        end else begin
                            state <= S_IDLE;
                            busy  <= 1'b0;
                        end
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule

`default_nettype wire
// =============================================================================
// END accelerator_ctrl.v
// =============================================================================
