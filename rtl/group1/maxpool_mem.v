// =============================================================================
// maxpool_mem.v -- Maxpool output memory (Module 1.11)
// -----------------------------------------------------------------------------
// "We have full parallelism in filters in 3x3 core and max pooling core so
// the max pool is generating 24 outputs at the same time, one for each
// output channel, (number of the output channels from Group1 is 24) so we
// need to store them at the same time so we must partition the memory to
// 24 instance each one has one of the channels." --
// STRUCTURE:
// 24 channel instances (one per output channel), each a 3136x15 SDP BRAM.
// The 24 BRAMs share one write address, one read address, and one WE.
// Write: maxpool core produces all 24 channel values simultaneously each
// output clock -- data_in is a 24*15 = 360-bit flat bus.
// Read : Group2 controller reads one address per clock -- data_out is a
// 360-bit flat bus with 1-cycle registered read latency.
// "Dual Port" in means SDP BRAM: write by Group1 and read by
// Group2 can proceed simultaneously at different addresses.
// PORT MAP:
// addr_wr [AW-1:0] -- shared write address (12 bits for 3136 depth)
// data_in [N_CHAN*DATA_W-1:0] -- 24-channel parallel write data (360 bits)
// data_in[ch*DATA_W +: DATA_W] = value for channel ch (0-indexed)
// we -- write enable (all 24 channels at once)
// addr_rd [AW-1:0] -- shared read address
// data_out[N_CHAN*DATA_W-1:0] -- 24-channel parallel read data (360 bits)
// data_out[ch*DATA_W +: DATA_W] = value for channel ch (1-cycle latency)
// IMPLEMENTATION:
// 24 inferred SDP Block RAMs, each 3136 x 15 bits.
// Separate write/read always blocks per channel (Vivado SDP pattern).
// (* ram_style = "block" *) forces BRAM inference in synthesis.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Ch 6.2.8: storage word width changed from DATA_W (15) to G1_FM_W (10).
// Reduces BRAM data width, saving BRAM resources.
module maxpool_mem #(
 parameter integer N_CHAN = `G1_OUT_C, // 24
 parameter integer DATA_W = `G1_FM_W, // 10 (Ch 6.2.8)
 parameter integer IMG_W = `G1_OUT_W, // 56
 parameter integer IMG_H = `G1_OUT_H, // 56
 parameter integer AW = `MAXPOOL_MEM_AW // 12
) (
 input wire clk,
 input wire rst,
 // Write port (maxpool core -- 24 channels in parallel, once per output pixel)
 input wire [AW-1:0] addr_wr,
 input wire [N_CHAN*DATA_W-1:0] data_in, // data_in[ch*DATA_W +: DATA_W]
 input wire we,
 // Read port (Group2 controller -- 1-cycle latency)
 input wire [AW-1:0] addr_rd,
 output wire [N_CHAN*DATA_W-1:0] data_out // data_out[ch*DATA_W +: DATA_W]
);

 localparam integer DEPTH = IMG_W * IMG_H; // 3136 per channel

 // -------------------------------------------------------------------------
 // 24 BRAM arrays, one per channel
 // -------------------------------------------------------------------------
 (* ram_style = "block" *) reg [DATA_W-1:0] ch00 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch01 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch02 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch03 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch04 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch05 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch06 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch07 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch08 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch09 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch10 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch11 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch12 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch13 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch14 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch15 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch16 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch17 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch18 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch19 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch20 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch21 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch22 [0:DEPTH-1];
 (* ram_style = "block" *) reg [DATA_W-1:0] ch23 [0:DEPTH-1];

 // Registered read outputs (1-cycle latency)
 reg [DATA_W-1:0] dout00, dout01, dout02, dout03;
 reg [DATA_W-1:0] dout04, dout05, dout06, dout07;
 reg [DATA_W-1:0] dout08, dout09, dout10, dout11;
 reg [DATA_W-1:0] dout12, dout13, dout14, dout15;
 reg [DATA_W-1:0] dout16, dout17, dout18, dout19;
 reg [DATA_W-1:0] dout20, dout21, dout22, dout23;

 // Slice write data per channel: data_in[ch*DATA_W +: DATA_W]
 // (Verilog-2001: cannot use parameter in +: operator directly from data_in slices
 // in generate/always; extract to wires first.)
 wire [DATA_W-1:0] din00 = data_in[ 0*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din01 = data_in[ 1*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din02 = data_in[ 2*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din03 = data_in[ 3*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din04 = data_in[ 4*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din05 = data_in[ 5*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din06 = data_in[ 6*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din07 = data_in[ 7*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din08 = data_in[ 8*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din09 = data_in[ 9*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din10 = data_in[10*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din11 = data_in[11*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din12 = data_in[12*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din13 = data_in[13*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din14 = data_in[14*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din15 = data_in[15*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din16 = data_in[16*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din17 = data_in[17*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din18 = data_in[18*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din19 = data_in[19*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din20 = data_in[20*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din21 = data_in[21*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din22 = data_in[22*DATA_W +: DATA_W];
 wire [DATA_W-1:0] din23 = data_in[23*DATA_W +: DATA_W];

 // -------------------------------------------------------------------------
 // 24 BRAM instances: write port (separate from read for Vivado SDP pattern)
 // -------------------------------------------------------------------------
 always @(posedge clk) begin if (we) ch00[addr_wr] <= din00; end
 always @(posedge clk) begin if (we) ch01[addr_wr] <= din01; end
 always @(posedge clk) begin if (we) ch02[addr_wr] <= din02; end
 always @(posedge clk) begin if (we) ch03[addr_wr] <= din03; end
 always @(posedge clk) begin if (we) ch04[addr_wr] <= din04; end
 always @(posedge clk) begin if (we) ch05[addr_wr] <= din05; end
 always @(posedge clk) begin if (we) ch06[addr_wr] <= din06; end
 always @(posedge clk) begin if (we) ch07[addr_wr] <= din07; end
 always @(posedge clk) begin if (we) ch08[addr_wr] <= din08; end
 always @(posedge clk) begin if (we) ch09[addr_wr] <= din09; end
 always @(posedge clk) begin if (we) ch10[addr_wr] <= din10; end
 always @(posedge clk) begin if (we) ch11[addr_wr] <= din11; end
 always @(posedge clk) begin if (we) ch12[addr_wr] <= din12; end
 always @(posedge clk) begin if (we) ch13[addr_wr] <= din13; end
 always @(posedge clk) begin if (we) ch14[addr_wr] <= din14; end
 always @(posedge clk) begin if (we) ch15[addr_wr] <= din15; end
 always @(posedge clk) begin if (we) ch16[addr_wr] <= din16; end
 always @(posedge clk) begin if (we) ch17[addr_wr] <= din17; end
 always @(posedge clk) begin if (we) ch18[addr_wr] <= din18; end
 always @(posedge clk) begin if (we) ch19[addr_wr] <= din19; end
 always @(posedge clk) begin if (we) ch20[addr_wr] <= din20; end
 always @(posedge clk) begin if (we) ch21[addr_wr] <= din21; end
 always @(posedge clk) begin if (we) ch22[addr_wr] <= din22; end
 always @(posedge clk) begin if (we) ch23[addr_wr] <= din23; end

 // -------------------------------------------------------------------------
 // 24 BRAM instances: read port (registered, 1-cycle latency)
 // -------------------------------------------------------------------------
 always @(posedge clk) begin dout00 <= ch00[addr_rd]; end
 always @(posedge clk) begin dout01 <= ch01[addr_rd]; end
 always @(posedge clk) begin dout02 <= ch02[addr_rd]; end
 always @(posedge clk) begin dout03 <= ch03[addr_rd]; end
 always @(posedge clk) begin dout04 <= ch04[addr_rd]; end
 always @(posedge clk) begin dout05 <= ch05[addr_rd]; end
 always @(posedge clk) begin dout06 <= ch06[addr_rd]; end
 always @(posedge clk) begin dout07 <= ch07[addr_rd]; end
 always @(posedge clk) begin dout08 <= ch08[addr_rd]; end
 always @(posedge clk) begin dout09 <= ch09[addr_rd]; end
 always @(posedge clk) begin dout10 <= ch10[addr_rd]; end
 always @(posedge clk) begin dout11 <= ch11[addr_rd]; end
 always @(posedge clk) begin dout12 <= ch12[addr_rd]; end
 always @(posedge clk) begin dout13 <= ch13[addr_rd]; end
 always @(posedge clk) begin dout14 <= ch14[addr_rd]; end
 always @(posedge clk) begin dout15 <= ch15[addr_rd]; end
 always @(posedge clk) begin dout16 <= ch16[addr_rd]; end
 always @(posedge clk) begin dout17 <= ch17[addr_rd]; end
 always @(posedge clk) begin dout18 <= ch18[addr_rd]; end
 always @(posedge clk) begin dout19 <= ch19[addr_rd]; end
 always @(posedge clk) begin dout20 <= ch20[addr_rd]; end
 always @(posedge clk) begin dout21 <= ch21[addr_rd]; end
 always @(posedge clk) begin dout22 <= ch22[addr_rd]; end
 always @(posedge clk) begin dout23 <= ch23[addr_rd]; end

 // -------------------------------------------------------------------------
 // Pack 24 registered outputs onto flat data_out bus
 // data_out[ch*DATA_W +: DATA_W] = value for channel ch
 // -------------------------------------------------------------------------
 assign data_out[ 0*DATA_W +: DATA_W] = dout00;
 assign data_out[ 1*DATA_W +: DATA_W] = dout01;
 assign data_out[ 2*DATA_W +: DATA_W] = dout02;
 assign data_out[ 3*DATA_W +: DATA_W] = dout03;
 assign data_out[ 4*DATA_W +: DATA_W] = dout04;
 assign data_out[ 5*DATA_W +: DATA_W] = dout05;
 assign data_out[ 6*DATA_W +: DATA_W] = dout06;
 assign data_out[ 7*DATA_W +: DATA_W] = dout07;
 assign data_out[ 8*DATA_W +: DATA_W] = dout08;
 assign data_out[ 9*DATA_W +: DATA_W] = dout09;
 assign data_out[10*DATA_W +: DATA_W] = dout10;
 assign data_out[11*DATA_W +: DATA_W] = dout11;
 assign data_out[12*DATA_W +: DATA_W] = dout12;
 assign data_out[13*DATA_W +: DATA_W] = dout13;
 assign data_out[14*DATA_W +: DATA_W] = dout14;
 assign data_out[15*DATA_W +: DATA_W] = dout15;
 assign data_out[16*DATA_W +: DATA_W] = dout16;
 assign data_out[17*DATA_W +: DATA_W] = dout17;
 assign data_out[18*DATA_W +: DATA_W] = dout18;
 assign data_out[19*DATA_W +: DATA_W] = dout19;
 assign data_out[20*DATA_W +: DATA_W] = dout20;
 assign data_out[21*DATA_W +: DATA_W] = dout21;
 assign data_out[22*DATA_W +: DATA_W] = dout22;
 assign data_out[23*DATA_W +: DATA_W] = dout23;

endmodule

`default_nettype wire
// =============================================================================
// END maxpool_mem.v
// =============================================================================
