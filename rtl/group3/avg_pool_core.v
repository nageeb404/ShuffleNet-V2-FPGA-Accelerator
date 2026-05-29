// =============================================================================
// avg_pool_core.v -- Global Average Pooling Core for Group 3 (Module 3.2)
// -----------------------------------------------------------------------------
// "average pooling is now just a summation unit and it has a quantizer
// at the end." The multiply-by-5-then-shift-right-8 approximation of 1/49
// is replaced by a saturating quantizer applied to the raw accumulated sum.
// full-precision values (no inter-stage quantizer), so IN_W = G3_CONV_OUT_W.
// Parallelism in Channels: 16 (= G3_PW_PAR_FILT)
// Input spatial: 7x7 = 49 pixels per channel
// Output: 1 pixel per channel (DATA_W-bit Q6.8)
// COMPUTATION (Ch 6 optimized):
// acc += data_in for each of 49 pixels (IN_W + 6 = 41-bit accumulator)
// result = quantize(acc) -> DATA_W-bit Q6.8, one-sided saturation (HAS_RELU=1)
// PORT MAP:
// clk, rst -- system clock / async reset
// acc_en -- 1: accumulate data_in into acc
// acc_clr -- 1: clear acc at start of a new channel accumulation
// data_in_flat -- 16 x IN_W input pixels (35-bit full-precision from conv)
// result_we -- capture final result into output register
// results_flat -- 16 x DATA_W quantized sums (Q6.8)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Ch 6.2.8: IN_W auto-updates to 27 (G3_CONV_OUT_W now=27 after 6.2.5+6.2.8).
// DATA_W (output) = G3_FM_W = 9 (5-bit fraction).
// ACC_W = 27+6 = 33 (was 41 with old IN_W=35).
module avg_pool_core #(
 parameter integer N_CHAN = `G3_PW_PAR_FILT, // 16
 parameter integer IN_W = `G3_CONV_OUT_W, // 27 (Ch 6.2.5+6.2.8: was 35)
 parameter integer DATA_W = `G3_FM_W // 9 (Ch 6.2.8: was DATA_W=15)
) (
 input wire clk,
 input wire rst,
 input wire acc_en,
 input wire acc_clr,
 input wire result_we,

 // N_CHAN input pixels (one per channel, current cycle) -- 35-bit wide
 input wire signed [N_CHAN*IN_W-1:0] data_in_flat,

 // N_CHAN quantized outputs (valid on result_we pulse and held)
 output reg signed [N_CHAN*DATA_W-1:0] results_flat
);

 // Accumulator width: IN_W + ceil(log2(49)) = IN_W + 6
 localparam ACC_W = IN_W + 6; // 41 for Ch6 path

 genvar ch;
 generate
 for (ch = 0; ch < N_CHAN; ch = ch + 1) begin : gen_ch

 // ----------------------------------------------------------------
 // Accumulator register
 // ----------------------------------------------------------------
 reg signed [ACC_W-1:0] acc;

 always @(posedge clk or posedge rst) begin
 if (rst)
 acc <= {ACC_W{1'b0}};
 else if (acc_clr)
 acc <= {ACC_W{1'b0}};
 else if (acc_en)
 acc <= acc + {{(ACC_W-IN_W){data_in_flat[ch*IN_W + IN_W-1]}},
 data_in_flat[ch*IN_W +: IN_W]};
 end

 // ----------------------------------------------------------------
 // Quantizer: ACC_W-bit raw sum -> DATA_W-bit Q6.8
 // HAS_RELU=1: inputs are post-ReLU (>= 0), so sum >= 0.
 // Saturates at DATA_MAX when sum exceeds Q6.8 range.
 // ----------------------------------------------------------------
 wire signed [DATA_W-1:0] avg_sat;

 quantizer #(
 .IN_W (ACC_W),
 .OUT_W (DATA_W),
 .HAS_RELU(1)
 ) u_quant (
 .in_data (acc),
 .out_data(avg_sat)
 );

 // ----------------------------------------------------------------
 // Output register: captured on result_we pulse
 // ----------------------------------------------------------------
 always @(posedge clk or posedge rst) begin
 if (rst)
 results_flat[ch*DATA_W +: DATA_W] <= {DATA_W{1'b0}};
 else if (result_we)
 results_flat[ch*DATA_W +: DATA_W] <= avg_sat;
 end

 end
 endgenerate

endmodule

`default_nettype wire
// =============================================================================
// END avg_pool_core.v
// =============================================================================
