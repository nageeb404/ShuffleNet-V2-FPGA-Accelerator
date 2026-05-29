// =============================================================================
// conv3x3_filter_unit.v -- Single-filter computation unit for the 3x3 conv core
// -----------------------------------------------------------------------------
// "3x3 Convolution Core" / Figure 5.8
//
// Ch 6.2.5 + 6.2.8: per-layer optimum widths applied.
// data input (photo pixels) : 8 bits (PHOTO_W, 5-bit fraction)
// weight input : 12 bits (G1_CONV_WW, 9-bit fraction)
// DROP_LSB = DATA_F+W_F-9 : 5 (5+9-9=5)
// MAC output : 15 bits (8+12-5)
// adder_tree_9 output : 19 bits (+4 from 2 Adder3 levels)
// accumulator register : 21 bits (+2 from ceil(log2(3)))
// bias adder output : 22 bits (+1 from 2-input bias add)
// final output : 10 bits (G1_FM_W, 6-bit fraction, HAS_RELU=1)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module conv3x3_filter_unit #(
    parameter integer DATA_W     = `PHOTO_W,               // 8 (photo pixel input)
    parameter integer W_W        = `G1_CONV_WW,            // 12 (weight width)
    parameter integer BIAS_WD    = `DATA_W,                // 15 (bias, original format)
    parameter integer DROP_LSB   = 5,                      // DATA_F+W_F-9 = 5+9-9
    parameter integer MAC_OUT_W  = DATA_W + W_W - DROP_LSB,// 15
    parameter integer TREE_OUT_W = MAC_OUT_W + 4,          // 19 (2 Adder3 levels)
    parameter integer ACC_W      = TREE_OUT_W + 2,         // 21 (ceil(log2(3))=2)
    parameter integer BIAS_OUT_W = ACC_W + 1,              // 22 (2-input bias add)
    parameter integer OUT_W      = `G1_FM_W                // 10 (quantizer output)
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire        acc_clr,
    // 9 data inputs from FIFOs (photo pixels, PHOTO_W bits)
    input  wire signed [DATA_W-1:0] d0, d1, d2, d3, d4, d5, d6, d7, d8,
    // 9 weights for this filter (G1_CONV_WW bits)
    input  wire signed [W_W-1:0]    w0, w1, w2, w3, w4, w5, w6, w7, w8,
    // 1 bias (original DATA_W format, 8-bit fraction)
    input  wire signed [BIAS_WD-1:0] bias,
    // result: G1_FM_W bits, post-ReLU, quantized (6-bit fraction)
    output wire signed [OUT_W-1:0] result
);

    // ------------------------------------------------------------------
    // 9 MAC units (Ch 6.2.5: asymmetric DATA_W x W_W multiply)
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // adder_tree_9: 9-input signed sum (+4 bits for 2 Adder3 levels)
    // ------------------------------------------------------------------
    wire signed [TREE_OUT_W-1:0] tree_out;

    adder_tree_9 #(.IN_W(MAC_OUT_W), .OUT_W(TREE_OUT_W)) u_tree (
        .in0(mac0), .in1(mac1), .in2(mac2),
        .in3(mac3), .in4(mac4), .in5(mac5),
        .in6(mac6), .in7(mac7), .in8(mac8),
        .sum_out(tree_out)
    );

    // ------------------------------------------------------------------
    // Accumulator with MUX (3 accumulation cycles)
    // ------------------------------------------------------------------
    wire signed [ACC_W-1:0] tree_ext;
    assign tree_ext = {{(ACC_W - TREE_OUT_W){tree_out[TREE_OUT_W-1]}}, tree_out};

    reg  signed [ACC_W-1:0] acc_reg;
    wire signed [ACC_W-1:0] acc_mux;
    wire signed [ACC_W-1:0] acc_sum;
    assign acc_mux = acc_clr ? {ACC_W{1'b0}} : acc_reg;
    assign acc_sum = acc_mux + tree_ext;

    always @(posedge clk or posedge rst) begin
        if (rst)
            acc_reg <= {ACC_W{1'b0}};
        else if (en)
            acc_reg <= acc_sum;
    end

    // ------------------------------------------------------------------
    // Bias addition (+1 bit)
    // Bias is BIAS_WD-wide (original 15-bit format, 8-bit fraction).
    // After accumulation the value has 9 frac bits; bias has 8 frac bits.
    // The 1-bit fraction mismatch is compensated by pre-doubled bias values
    // in the weight ROM (consistent with original design convention).
    // ------------------------------------------------------------------
    wire signed [BIAS_OUT_W-1:0] acc_ext;
    wire signed [BIAS_OUT_W-1:0] bias_ext;
    wire signed [BIAS_OUT_W-1:0] bias_sum;

    assign acc_ext  = {{(BIAS_OUT_W - ACC_W){acc_reg[ACC_W-1]}},   acc_reg};
    assign bias_ext = {{(BIAS_OUT_W - BIAS_WD){bias[BIAS_WD-1]}},  bias};
    assign bias_sum = acc_ext + bias_ext;

    // ------------------------------------------------------------------
    // ReLU (MSB test)
    // ------------------------------------------------------------------
    wire signed [BIAS_OUT_W-1:0] relu_out;
    assign relu_out = bias_sum[BIAS_OUT_W-1] ? {BIAS_OUT_W{1'b0}} : bias_sum;

    // ------------------------------------------------------------------
    // Quantizer: HAS_RELU=1, output G1_FM_W = 10 bits (6-bit fraction)
    // ------------------------------------------------------------------
    quantizer #(
        .IN_W     (BIAS_OUT_W),
        .OUT_W    (OUT_W),
        .HAS_RELU (1)
    ) u_quant (
        .in_data (relu_out),
        .out_data(result)
    );

endmodule

`default_nettype wire
// =============================================================================
// END conv3x3_filter_unit.v
// =============================================================================
