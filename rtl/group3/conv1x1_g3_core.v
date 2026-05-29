// =============================================================================
// conv1x1_g3_core.v -- 16-parallel-filter 1x1 PW conv core for Group 3 (Module 3.1)
// -----------------------------------------------------------------------------
// Ch 6.2.7 change: output is full-precision relu_out per filter rather than
// quantized Q6.8. avg_pool_core receives wider values and applies a single
// quantizer after summing (Sec 6.2.3).
// Ch 6.2.5 + 6.2.8: per-layer widths applied.
// data inputs (from G2 feature map) : 12 bits (IN_W = G2_FM_W)
// weight inputs : 9 bits (W_W = G3_PW_WW)
// bias inputs : 15 bits (BIAS_WD = DATA_W, original format)
// results (full-precision, no quant) : 27 bits (BIAS_OUT_W = G3_CONV_OUT_W)
// Parallelism in Filters : 16 (= G3_PW_PAR_FILT)
// Parallelism in Channels : 29 (= G3_PW_PAR_CHAN)
// Port packing convention:
// weights_flat : filter f, channel c: weights_flat[(f*N_CHAN+c)*W_W +: W_W]
// biases_flat : filter f: biases_flat[f*BIAS_WD +: BIAS_WD]
// results_flat : filter f: results_flat[f*BIAS_OUT_W +: BIAS_OUT_W] (27-bit)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module conv1x1_g3_core #(
 parameter integer N_FILT = `G3_PW_PAR_FILT, // 16
 parameter integer N_CHAN = `G3_PW_PAR_CHAN, // 29
 parameter integer IN_W = `G2_FM_W, // 12 (Ch 6.2.8: G2 output)
 parameter integer W_W = `G3_PW_WW, // 9 (Ch 6.2.5: G3 PW weight)
 parameter integer BIAS_WD = `DATA_W, // 15 (bias, original format)
 parameter integer BIAS_OUT_W = `G3_CONV_OUT_W // 27 (Ch 6.2.5+6.2.8: was 35)
) (
 input wire clk,
 input wire rst,
 input wire en,
 input wire acc_clr,

 // 29 shared data inputs (same for all 16 filters)
 input wire signed [IN_W-1:0] d0, d1, d2, d3, d4,
 input wire signed [IN_W-1:0] d5, d6, d7, d8, d9,
 input wire signed [IN_W-1:0] d10, d11, d12, d13, d14,
 input wire signed [IN_W-1:0] d15, d16, d17, d18, d19,
 input wire signed [IN_W-1:0] d20, d21, d22, d23, d24,
 input wire signed [IN_W-1:0] d25, d26, d27, d28,

 // 16*29 weight inputs
 input wire [N_FILT*N_CHAN*W_W-1:0] weights_flat,

 // 16 bias inputs
 input wire [N_FILT*BIAS_WD-1:0] biases_flat,

 // 16 results: BIAS_OUT_W-bit full-precision per filter (Ch 6.2.7: no output quantizer)
 output wire [N_FILT*BIAS_OUT_W-1:0] results_flat
);

 genvar f;
 generate
 for (f = 0; f < N_FILT; f = f + 1) begin : gen_g3_filt

 conv1x1_g3_filter_unit #(
 .DATA_W (IN_W),
 .W_W (W_W),
 .BIAS_WD (BIAS_WD),
 .BIAS_OUT_W(BIAS_OUT_W)
 ) u_filt (
 .clk(clk), .rst(rst), .en(en), .acc_clr(acc_clr),
 // shared data bus
 .d0 (d0), .d1 (d1), .d2 (d2), .d3 (d3), .d4 (d4),
 .d5 (d5), .d6 (d6), .d7 (d7), .d8 (d8), .d9 (d9),
 .d10(d10), .d11(d11), .d12(d12), .d13(d13), .d14(d14),
 .d15(d15), .d16(d16), .d17(d17), .d18(d18), .d19(d19),
 .d20(d20), .d21(d21), .d22(d22), .d23(d23), .d24(d24),
 .d25(d25), .d26(d26), .d27(d27), .d28(d28),
 // per-filter weights
 .w0 (weights_flat[(f*N_CHAN+ 0)*W_W +: W_W]),
 .w1 (weights_flat[(f*N_CHAN+ 1)*W_W +: W_W]),
 .w2 (weights_flat[(f*N_CHAN+ 2)*W_W +: W_W]),
 .w3 (weights_flat[(f*N_CHAN+ 3)*W_W +: W_W]),
 .w4 (weights_flat[(f*N_CHAN+ 4)*W_W +: W_W]),
 .w5 (weights_flat[(f*N_CHAN+ 5)*W_W +: W_W]),
 .w6 (weights_flat[(f*N_CHAN+ 6)*W_W +: W_W]),
 .w7 (weights_flat[(f*N_CHAN+ 7)*W_W +: W_W]),
 .w8 (weights_flat[(f*N_CHAN+ 8)*W_W +: W_W]),
 .w9 (weights_flat[(f*N_CHAN+ 9)*W_W +: W_W]),
 .w10(weights_flat[(f*N_CHAN+10)*W_W +: W_W]),
 .w11(weights_flat[(f*N_CHAN+11)*W_W +: W_W]),
 .w12(weights_flat[(f*N_CHAN+12)*W_W +: W_W]),
 .w13(weights_flat[(f*N_CHAN+13)*W_W +: W_W]),
 .w14(weights_flat[(f*N_CHAN+14)*W_W +: W_W]),
 .w15(weights_flat[(f*N_CHAN+15)*W_W +: W_W]),
 .w16(weights_flat[(f*N_CHAN+16)*W_W +: W_W]),
 .w17(weights_flat[(f*N_CHAN+17)*W_W +: W_W]),
 .w18(weights_flat[(f*N_CHAN+18)*W_W +: W_W]),
 .w19(weights_flat[(f*N_CHAN+19)*W_W +: W_W]),
 .w20(weights_flat[(f*N_CHAN+20)*W_W +: W_W]),
 .w21(weights_flat[(f*N_CHAN+21)*W_W +: W_W]),
 .w22(weights_flat[(f*N_CHAN+22)*W_W +: W_W]),
 .w23(weights_flat[(f*N_CHAN+23)*W_W +: W_W]),
 .w24(weights_flat[(f*N_CHAN+24)*W_W +: W_W]),
 .w25(weights_flat[(f*N_CHAN+25)*W_W +: W_W]),
 .w26(weights_flat[(f*N_CHAN+26)*W_W +: W_W]),
 .w27(weights_flat[(f*N_CHAN+27)*W_W +: W_W]),
 .w28(weights_flat[(f*N_CHAN+28)*W_W +: W_W]),
 // per-filter bias
 .bias (biases_flat[f*BIAS_WD +: BIAS_WD]),
 // per-filter full-precision result
 .result(results_flat[f*BIAS_OUT_W +: BIAS_OUT_W])
 );

 end
 endgenerate

endmodule

`default_nettype wire
// =============================================================================
// END conv1x1_g3_core.v
// =============================================================================
