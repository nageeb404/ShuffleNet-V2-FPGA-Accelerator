// =============================================================================
// fc_core.v -- Fully-Connected Layer Core for Group 3 (Module 3.3)
// -----------------------------------------------------------------------------
// "The FC layer processes 1000 output classes using 32 channels in parallel
// from the register file. Each of 1024 input pixels multiplied by
// corresponding filter weight." --
// Parallelism in Channels: 32 (= G3_FC_PAR_CHAN)
// Total input channels: 1024 (= G3_FC_IN)
// Total output classes: 1000 (= G3_FC_OUT)
// Accumulation steps per class: 1024 / 32 = 32
// Ch 6.2.5 + 6.2.8: per-layer widths applied.
// data inputs (from avgpool/regfile) : 9 bits (DATA_W = G3_FM_W)
// weight inputs : 9 bits (W_W = FC_WW)
// bias inputs : 11 bits (BIAS_WD = FC_BIAS_W)
// result : 9 bits (OUT_W = G3_FM_W)
// PORT MAP:
// clk, rst -- system clock / async reset
// en -- MAC register enable
// acc_clr -- 1 = start new accumulation (first of 32 steps)
// d0..d31 -- DATA_W input data (32 channels from register file)
// w0..w31 -- W_W weights for current class
// bias -- BIAS_WD signed bias for current class
// result -- DATA_W signed quantized output for current class
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module fc_core #(
 parameter integer N_PAR = `G3_FC_PAR_CHAN, // 32 parallel channels
 parameter integer DATA_W = `G3_FM_W, // 9 (Ch 6.2.8: avgpool output)
 parameter integer W_W = `FC_WW, // 9 (Ch 6.2.5: FC weight width)
 parameter integer BIAS_WD = `FC_BIAS_W // 11 (Ch 6.2.5: FC bias width)
) (
 input wire clk,
 input wire rst,
 input wire en,
 input wire acc_clr,

 // 32 data inputs (from register file, current 32-channel group)
 input wire signed [DATA_W-1:0] d0, d1, d2, d3, d4, d5, d6, d7,
 input wire signed [DATA_W-1:0] d8, d9, d10, d11, d12, d13, d14, d15,
 input wire signed [DATA_W-1:0] d16, d17, d18, d19, d20, d21, d22, d23,
 input wire signed [DATA_W-1:0] d24, d25, d26, d27, d28, d29, d30, d31,

 // 32 weight inputs (from FC filter memory, current class)
 input wire signed [W_W-1:0] w0, w1, w2, w3, w4, w5, w6, w7,
 input wire signed [W_W-1:0] w8, w9, w10, w11, w12, w13, w14, w15,
 input wire signed [W_W-1:0] w16, w17, w18, w19, w20, w21, w22, w23,
 input wire signed [W_W-1:0] w24, w25, w26, w27, w28, w29, w30, w31,

 // Bias for current class
 input wire signed [BIAS_WD-1:0] bias,

 // Quantized output for current class (valid after accumulation + bias)
 output wire signed [DATA_W-1:0] result
);

 fc_filter_unit #(
 .N_PAR (N_PAR),
 .DATA_W (DATA_W),
 .W_W (W_W),
 .BIAS_WD (BIAS_WD),
 .HAS_RELU (0)
 ) u_filter (
 .clk(clk), .rst(rst), .en(en), .acc_clr(acc_clr),
 .d0(d0), .d1(d1), .d2(d2), .d3(d3),
 .d4(d4), .d5(d5), .d6(d6), .d7(d7),
 .d8(d8), .d9(d9), .d10(d10), .d11(d11),
 .d12(d12), .d13(d13), .d14(d14), .d15(d15),
 .d16(d16), .d17(d17), .d18(d18), .d19(d19),
 .d20(d20), .d21(d21), .d22(d22), .d23(d23),
 .d24(d24), .d25(d25), .d26(d26), .d27(d27),
 .d28(d28), .d29(d29), .d30(d30), .d31(d31),
 .w0(w0), .w1(w1), .w2(w2), .w3(w3),
 .w4(w4), .w5(w5), .w6(w6), .w7(w7),
 .w8(w8), .w9(w9), .w10(w10), .w11(w11),
 .w12(w12), .w13(w13), .w14(w14), .w15(w15),
 .w16(w16), .w17(w17), .w18(w18), .w19(w19),
 .w20(w20), .w21(w21), .w22(w22), .w23(w23),
 .w24(w24), .w25(w25), .w26(w26), .w27(w27),
 .w28(w28), .w29(w29), .w30(w30), .w31(w31),
 .bias(bias),
 .result(result)
 );

endmodule

`default_nettype wire
// =============================================================================
// END fc_core.v
// =============================================================================
