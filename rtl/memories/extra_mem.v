// =============================================================================
// extra_mem.v -- Extra Memory: Group 2 -> Group 3 feature map buffer
// -----------------------------------------------------------------------------
//: "Till it reaches 7*7*464 at the Group 2 output which
// is stored in the Extra memory."
//
// Organization:
// 29 instances x 784 words x G2_FM_W (12) bits
// 784 = 16 acc_groups x 49 pixels (7*7 = 49)
// 16 acc_groups x 29 channels = 464 total channels
//
// Address encoding:
// addr = acc_group * 49 + pixel (0..783)
// All 29 instances hold different channels for the same (acc_group, pixel).
//
// Write side (from group2_top / accelerator_top):
// Group 2 PW conv writes 29 channels per cycle; the 58-wide result is split
// into two half-writes (channels 0..28, then channels 29..57).
// wr_addr = acc_group * 49 + pixel
// wr_data[c*G2_FM_W +: G2_FM_W] = result for channel c (c=0..28)
// wr_we = 1 when a valid half-write is presented
//
// Read side (from group3_top):
// rd_addr = extramem_rd_addr from group3_ctrl
// rd_data = 29 channels at that (acc_group, pixel) position
// Read is registered (1-cycle read latency, standard BRAM behavior)
//
// BRAM inference: Vivado will infer 29 x RAMB36 (or split into RAMB18 pairs).
// Each instance: 784 x 12 bits ~9.4 Kb -> maps to 1 x RAMB18 per instance
// = 29 BRAMs total
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module extra_mem #(
    parameter integer N_CH    = `G3_PW_PAR_CHAN,   // 29 channel instances
    parameter integer DATA_W  = `G2_FM_W,          // 12 bits per word
    parameter integer N_WORDS = 1024,              // depth = 1024 (max addr = 49*17-2 = 831)
    parameter integer AW      = 10                 // ceil(log2(1024)) = 10
) (
    input  wire clk,

    // ---- Write port (from Group 2 via accelerator_top) ----
    input  wire [AW-1:0]          wr_addr,
    input  wire [N_CH*DATA_W-1:0] wr_data,   // 29 channels packed
    input  wire                   wr_we,

    // ---- Read port (from group3_top via accelerator_top) ----
    input  wire [AW-1:0]          rd_addr,
    output reg  [N_CH*DATA_W-1:0] rd_data    // 29 channels packed (registered)
);

    // -------------------------------------------------------------------------
    // 29 BRAM instances: each 784 x 12 bits, simple dual-port
    // -------------------------------------------------------------------------
    genvar c;
    generate
        for (c = 0; c < N_CH; c = c + 1) begin : gen_bram

            (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:N_WORDS-1];

            integer i;
            initial begin
                for (i = 0; i < N_WORDS; i = i + 1)
                    mem[i] = {DATA_W{1'b0}};
            end

            // Write
            always @(posedge clk) begin
                if (wr_we)
                    mem[wr_addr] <= wr_data[c*DATA_W +: DATA_W];
            end

            // Read (registered)
            always @(posedge clk) begin
                rd_data[c*DATA_W +: DATA_W] <= mem[rd_addr];
            end

        end
    endgenerate

endmodule

`default_nettype wire
// =============================================================================
// END extra_mem.v
// =============================================================================
