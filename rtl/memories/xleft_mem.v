// =============================================================================
// xleft_mem.v -- SUPERSEDED: DW->PW routing is now internal to group2_top.
// This file is kept for reference but is NOT instantiated anywhere.
// xleft_mem.v -- X_Left intermediate memory: DW conv output -> PW conv input
// -----------------------------------------------------------------------------
//: Left branch DW output buffer within Group 2 shuffle blocks.
//
// Organization:
// 29 instances x 784 words x G2_FM_W (12) bits
// 784 = 16 acc_groups x 49 pixels (7*7 = 49, maximum spatial size)
// Address: acc_group * 49 + pixel (0..783)
//
// The DW conv writes its 29-channel output here. The PW conv reads from here
// as its per-step input (one row of 12 channels per step after PAR_CHAN change).
// The read/write orchestration (which acc_group, write vs read cycle) is
// controlled externally by group2_ctrl and accelerator_top.
//
// Read is registered (1-cycle latency, standard BRAM behavior).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module xleft_mem #(
    parameter integer N_CH    = `G3_PW_PAR_CHAN,   // 29 channel instances
    parameter integer DATA_W  = `G2_FM_W,          // 12 bits per word
    parameter integer N_WORDS = 784,               // 16 acc_groups * 49 pixels
    parameter integer AW      = 10                 // ceil(log2(784)) = 10
) (
    input  wire clk,

    // ---- Write port (from dw_conv3x3_core via accelerator_top) ----
    input  wire [AW-1:0]          wr_addr,
    input  wire [N_CH*DATA_W-1:0] wr_data,   // 29 channels packed
    input  wire                   wr_we,

    // ---- Read port (to conv1x1_core as pw_data_in) ----
    input  wire [AW-1:0]          rd_addr,
    output reg  [N_CH*DATA_W-1:0] rd_data    // 29 channels packed (registered)
);

    genvar c;
    generate
        for (c = 0; c < N_CH; c = c + 1) begin : gen_bram

            (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:N_WORDS-1];

            integer i;
            initial begin
                for (i = 0; i < N_WORDS; i = i + 1)
                    mem[i] = {DATA_W{1'b0}};
            end

            always @(posedge clk) begin
                if (wr_we)
                    mem[wr_addr] <= wr_data[c*DATA_W +: DATA_W];
            end

            always @(posedge clk) begin
                rd_data[c*DATA_W +: DATA_W] <= mem[rd_addr];
            end

        end
    endgenerate

endmodule

`default_nettype wire
// =============================================================================
// END xleft_mem.v
// =============================================================================
