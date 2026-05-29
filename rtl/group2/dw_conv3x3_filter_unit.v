// =============================================================================
// dw_conv3x3_filter_unit.v -- Single depthwise 3x3 filter unit (Module 2.1)
// -----------------------------------------------------------------------------
// Ch 6.2.5 + 6.2.8: per-layer optimum widths applied.
// data input (maxpool output) : 10 bits (G1_FM_W, 6-bit fraction)
// weight input : 15 bits (G2_DW_WW, 8-bit fraction, unchanged)
// DROP_LSB = DATA_F+W_F-9 : 5 (6+8-9=5)
// MAC output : 20 bits (10+15-5)
// adder_tree_9 output : 24 bits (+4 from 2 Adder3 levels)
// bias adder output : 25 bits (+1 from 2-input bias add)
// final output : 12 bits (G2_FM_W, 8-bit fraction, HAS_RELU=0)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module dw_conv3x3_filter_unit #(
 parameter integer DATA_W = `G1_FM_W, // 10 (maxpool output)
 parameter integer W_W = `G2_DW_WW, // 15 (weight, unchanged)
 parameter integer BIAS_WD = `DATA_W, // 15 (bias, original format)
 parameter integer DROP_LSB = 5, // DATA_F+W_F-9 = 6+8-9
 parameter integer MAC_OUT_W = DATA_W + W_W - DROP_LSB,// 20
 parameter integer TREE_OUT_W = MAC_OUT_W + 4, // 24 (2 Adder3 levels)
 parameter integer BIAS_OUT_W = TREE_OUT_W + 1, // 25 (2-input bias add)
 parameter integer OUT_W = `G2_FM_W // 12 (quantizer output)
) (
 input wire clk,
 input wire rst,
 input wire en,
 // 9 data inputs (all from the same input channel for DW conv)
 input wire signed [DATA_W-1:0] d0, d1, d2, d3, d4, d5, d6, d7, d8,
 // 9 weights for this filter (G2_DW_WW bits)
 input wire signed [W_W-1:0] w0, w1, w2, w3, w4, w5, w6, w7, w8,
 // 1 bias (original DATA_W format)
 input wire signed [BIAS_WD-1:0] bias,
 // result: G2_FM_W bits, two-sided saturated (no ReLU for DW conv)
 output wire signed [OUT_W-1:0] result
);

 // -------------------------------------------------------------------------
 // 9 MAC units (Ch 6.2.5: asymmetric DATA_W x W_W multiply)
 // -------------------------------------------------------------------------
 wire signed [MAC_OUT_W-1:0] mac0, mac1, mac2, mac3, mac4,
 mac5, mac6, mac7, mac8;

 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac0(.clk(clk),.rst(rst),.en(en),.a_data(d0),.b_weight(w0),.p_out(mac0));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac1(.clk(clk),.rst(rst),.en(en),.a_data(d1),.b_weight(w1),.p_out(mac1));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac2(.clk(clk),.rst(rst),.en(en),.a_data(d2),.b_weight(w2),.p_out(mac2));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac3(.clk(clk),.rst(rst),.en(en),.a_data(d3),.b_weight(w3),.p_out(mac3));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac4(.clk(clk),.rst(rst),.en(en),.a_data(d4),.b_weight(w4),.p_out(mac4));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac5(.clk(clk),.rst(rst),.en(en),.a_data(d5),.b_weight(w5),.p_out(mac5));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac6(.clk(clk),.rst(rst),.en(en),.a_data(d6),.b_weight(w6),.p_out(mac6));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac7(.clk(clk),.rst(rst),.en(en),.a_data(d7),.b_weight(w7),.p_out(mac7));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac8(.clk(clk),.rst(rst),.en(en),.a_data(d8),.b_weight(w8),.p_out(mac8));

 // -------------------------------------------------------------------------
 // adder_tree_9: 9-input signed sum
 // -------------------------------------------------------------------------
 wire signed [TREE_OUT_W-1:0] tree_out;

 adder_tree_9 #(.IN_W(MAC_OUT_W), .OUT_W(TREE_OUT_W)) u_tree (
 .in0(mac0), .in1(mac1), .in2(mac2),
 .in3(mac3), .in4(mac4), .in5(mac5),
 .in6(mac6), .in7(mac7), .in8(mac8),
 .sum_out(tree_out)
 );

 // -------------------------------------------------------------------------
 // Bias addition (+1 bit) -- combinational
 // -------------------------------------------------------------------------
 wire signed [BIAS_OUT_W-1:0] tree_ext;
 wire signed [BIAS_OUT_W-1:0] bias_ext;
 wire signed [BIAS_OUT_W-1:0] bias_sum;

 assign tree_ext = {{(BIAS_OUT_W - TREE_OUT_W){tree_out[TREE_OUT_W-1]}}, tree_out};
 assign bias_ext = {{(BIAS_OUT_W - BIAS_WD){bias[BIAS_WD-1]}}, bias};
 assign bias_sum = tree_ext + bias_ext;

 // -------------------------------------------------------------------------
 // Two-sided quantizer (HAS_RELU=0): DW conv has NO ReLU in ShuffleNet V2
 // -------------------------------------------------------------------------
 quantizer #(
 .IN_W (BIAS_OUT_W),
 .OUT_W (OUT_W),
 .HAS_RELU (0)
 ) u_quant (
 .in_data (bias_sum),
 .out_data(result)
 );

endmodule

`default_nettype wire
// =============================================================================
// END dw_conv3x3_filter_unit.v
// =============================================================================
