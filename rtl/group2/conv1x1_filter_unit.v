// =============================================================================
// conv1x1_filter_unit.v -- Single 1x1 convolution filter unit (Module 2.4)
// -----------------------------------------------------------------------------
// G2_PW_PAR_CHAN reduced from 29 to 12 for ZU19EG DSP budget.
// Uses adder_tree_12 (3 Adder3 levels, +6 bits) instead of adder_tree_29.
// Ch 6.2.5 + 6.2.8: per-layer optimum widths applied.
// data input (G2 feature map) : 12 bits (G2_FM_W, 8-bit fraction)
// weight input : 11 bits (G2_PW_WW, 9-bit fraction)
// DROP_LSB = DATA_F+W_F-9 : 8 (8+9-9=8)
// MAC output : 15 bits (12+11-8)
// adder_tree_12 output : 21 bits (15+6 from 3 Adder3 levels)
// accumulator output : 26 bits (+5 from ceil(log2(20)) accum steps)
// bias adder output : 27 bits (+1 from 2-input bias add)
// final output : 12 bits (G2_FM_W, 8-bit fraction, HAS_RELU=1)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module conv1x1_filter_unit #(
 parameter integer DATA_W = `G2_FM_W, // 12 (PW data input)
 parameter integer W_W = `G2_PW_WW, // 11 (weight width)
 parameter integer BIAS_WD = `G2_BIAS_W, // 13 (bias, 9-bit fraction)
 parameter integer DROP_LSB = 8, // DATA_F+W_F-9 = 8+9-9
 parameter integer MAC_OUT_W = DATA_W + W_W - DROP_LSB,// 15
 parameter integer TREE_OUT_W = MAC_OUT_W + 6, // 21 (3 Adder3 levels, +6)
 parameter integer ACC_OUT_W = TREE_OUT_W + 5, // 26 (ceil(log2(20))=5)
 parameter integer BIAS_OUT_W = ACC_OUT_W + 1, // 27 (2-input bias add)
 parameter integer OUT_W = `G2_FM_W // 12 (quantizer output)
) (
 input wire clk,
 input wire rst,
 input wire en,
 input wire acc_clr,

 // 12 data inputs (G2_FM_W bits, from feature map memory; step-loaded)
 input wire signed [DATA_W-1:0] d0, d1, d2, d3,
 input wire signed [DATA_W-1:0] d4, d5, d6, d7,
 input wire signed [DATA_W-1:0] d8, d9, d10, d11,

 // 12 weights (G2_PW_WW bits; one row of weight ROM per step)
 input wire signed [W_W-1:0] w0, w1, w2, w3,
 input wire signed [W_W-1:0] w4, w5, w6, w7,
 input wire signed [W_W-1:0] w8, w9, w10, w11,

 // 1 bias (G2_BIAS_W bits, 9-bit fraction)
 input wire signed [BIAS_WD-1:0] bias,

 // result: G2_FM_W bits, one-sided saturated (ReLU applied)
 output wire signed [OUT_W-1:0] result
);

 // -------------------------------------------------------------------------
 // 12 MAC units (Ch 6.2.5: asymmetric DATA_W x W_W multiply)
 // -------------------------------------------------------------------------
 wire signed [MAC_OUT_W-1:0] mac0, mac1, mac2, mac3,
 mac4, mac5, mac6, mac7,
 mac8, mac9, mac10, mac11;

 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac0 (.clk(clk),.rst(rst),.en(en),.a_data(d0), .b_weight(w0), .p_out(mac0));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac1 (.clk(clk),.rst(rst),.en(en),.a_data(d1), .b_weight(w1), .p_out(mac1));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac2 (.clk(clk),.rst(rst),.en(en),.a_data(d2), .b_weight(w2), .p_out(mac2));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac3 (.clk(clk),.rst(rst),.en(en),.a_data(d3), .b_weight(w3), .p_out(mac3));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac4 (.clk(clk),.rst(rst),.en(en),.a_data(d4), .b_weight(w4), .p_out(mac4));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac5 (.clk(clk),.rst(rst),.en(en),.a_data(d5), .b_weight(w5), .p_out(mac5));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac6 (.clk(clk),.rst(rst),.en(en),.a_data(d6), .b_weight(w6), .p_out(mac6));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac7 (.clk(clk),.rst(rst),.en(en),.a_data(d7), .b_weight(w7), .p_out(mac7));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac8 (.clk(clk),.rst(rst),.en(en),.a_data(d8), .b_weight(w8), .p_out(mac8));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac9 (.clk(clk),.rst(rst),.en(en),.a_data(d9), .b_weight(w9), .p_out(mac9));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac10(.clk(clk),.rst(rst),.en(en),.a_data(d10),.b_weight(w10),.p_out(mac10));
 mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
 u_mac11(.clk(clk),.rst(rst),.en(en),.a_data(d11),.b_weight(w11),.p_out(mac11));

 // -------------------------------------------------------------------------
 // adder_tree_12: 12-input signed sum (+6 bits, 3 Adder3 levels)
 // -------------------------------------------------------------------------
 wire signed [TREE_OUT_W-1:0] tree_out;

 adder_tree_12 #(.IN_W(MAC_OUT_W), .OUT_W(TREE_OUT_W)) u_tree (
 .in0 (mac0), .in1 (mac1), .in2 (mac2), .in3 (mac3),
 .in4 (mac4), .in5 (mac5), .in6 (mac6), .in7 (mac7),
 .in8 (mac8), .in9 (mac9), .in10(mac10), .in11(mac11),
 .sum_out(tree_out)
 );

 // -------------------------------------------------------------------------
 // Accumulator (clears on acc_clr; sized for up to 20 accumulation steps)
 // -------------------------------------------------------------------------
 wire signed [ACC_OUT_W-1:0] tree_ext;
 assign tree_ext = {{(ACC_OUT_W - TREE_OUT_W){tree_out[TREE_OUT_W-1]}}, tree_out};

 reg signed [ACC_OUT_W-1:0] acc_reg;
 wire signed [ACC_OUT_W-1:0] acc_mux;
 wire signed [ACC_OUT_W-1:0] acc_sum;
 assign acc_mux = acc_clr ? {ACC_OUT_W{1'b0}} : acc_reg;
 assign acc_sum = acc_mux + tree_ext;

 always @(posedge clk or posedge rst) begin
 if (rst)
 acc_reg <= {ACC_OUT_W{1'b0}};
 else if (en)
 acc_reg <= acc_sum;
 end

 // -------------------------------------------------------------------------
 // Bias addition (+1 bit)
 // G2_BIAS_W = 13 bits, 9-bit fraction. Accumulator also has 9 frac bits.
 // -------------------------------------------------------------------------
 wire signed [BIAS_OUT_W-1:0] acc_ext;
 wire signed [BIAS_OUT_W-1:0] bias_ext;
 wire signed [BIAS_OUT_W-1:0] bias_sum;

 assign acc_ext = {{(BIAS_OUT_W - ACC_OUT_W){acc_reg[ACC_OUT_W-1]}}, acc_reg};
 assign bias_ext = {{(BIAS_OUT_W - BIAS_WD){bias[BIAS_WD-1]}}, bias};
 assign bias_sum = acc_ext + bias_ext;

 // -------------------------------------------------------------------------
 // ReLU (MSB-test)
 // -------------------------------------------------------------------------
 wire signed [BIAS_OUT_W-1:0] relu_out;
 assign relu_out = bias_sum[BIAS_OUT_W-1] ? {BIAS_OUT_W{1'b0}} : bias_sum;

 // -------------------------------------------------------------------------
 // One-sided quantizer (HAS_RELU=1), output G2_FM_W = 12 bits
 // -------------------------------------------------------------------------
 quantizer #(
 .IN_W (BIAS_OUT_W),
 .OUT_W (OUT_W),
 .HAS_RELU (1)
 ) u_quant (
 .in_data (relu_out),
 .out_data(result)
 );

endmodule

`default_nettype wire
// =============================================================================
// END conv1x1_filter_unit.v
// =============================================================================
