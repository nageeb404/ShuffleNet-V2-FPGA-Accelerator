// =============================================================================
// xright_mem.v -- SUPERSEDED: DW->PW routing is now internal to group2_top.
// This file is kept for reference but is NOT instantiated anywhere.
// xright_mem.v -- X_Right intermediate memory: DW conv output -> PW conv input
// -----------------------------------------------------------------------------
//: Right branch DW output buffer within Group 2 shuffle blocks.
//
// Organization:
// 29 instances x 1568 words x G2_FM_W (12) bits
// 1568 = 2 x 784 (double-buffered: one half written while other half is read)
// 784 = 16 acc_groups x 49 pixels (7*7 = 49)
//
// Ping-pong buffering:
// Bank 0 (addresses 0..783): DW output for current or previous block
// Bank 1 (addresses 784..1567): DW output for the other block
// Bank select bit in the upper address bit allows simultaneous read/write
// of different blocks without stalling.
//
// Read is registered (1-cycle latency, standard BRAM behavior).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module xright_mem #(
    parameter integer N_CH    = `G3_PW_PAR_CHAN,   // 29 channel instances
    parameter integer DATA_W  = `G2_FM_W,          // 12 bits per word
    parameter integer N_WORDS = 1568,              // 2 * 784 (double buffer)
    parameter integer AW      = 11                 // ceil(log2(1568)) = 11
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
// END xright_mem.v
// =============================================================================
