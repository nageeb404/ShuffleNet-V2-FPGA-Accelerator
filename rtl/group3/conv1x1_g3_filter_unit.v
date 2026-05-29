// =============================================================================
// conv1x1_g3_filter_unit.v -- Single 1x1 conv filter unit for Group 3
// -----------------------------------------------------------------------------
// "Remove quantizer after Group3 1x1 Convolution" +
// Ch 6.2.5 + 6.2.8 per-layer optimum widths.
//
// data input (Extra memory = G2 output) : 12 bits (G2_FM_W, 8-bit fraction)
// weight input : 9 bits (G3_PW_WW, 8-bit fraction)
// DROP_LSB = DATA_F+W_F-9 : 7 (8+8-9=7)
// MAC output : 14 bits (12+9-7)
// adder_tree_29 output : 22 bits (+8 from 4 Adder3 levels)
// accumulator output : 26 bits (+4 from ceil(log2(16))=4)
// bias adder output : 27 bits (+1, = G3_CONV_OUT_W)
// result output : 27 bits (full precision, NO quantizer)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module conv1x1_g3_filter_unit #(
    parameter integer DATA_W    = `G2_FM_W,                // 12 (Extra memory data)
    parameter integer W_W       = `G3_PW_WW,              // 9 (weight width)
    parameter integer BIAS_WD   = `DATA_W,                // 15 (bias, original format)
    parameter integer DROP_LSB  = 7,                      // DATA_F+W_F-9 = 8+8-9
    parameter integer MAC_OUT_W = DATA_W + W_W - DROP_LSB,// 14
    parameter integer TREE_OUT_W = MAC_OUT_W + 8,         // 22 (4 Adder3 levels)
    parameter integer ACC_OUT_W  = TREE_OUT_W + 4,        // 26 (ceil(log2(16))=4)
    parameter integer BIAS_OUT_W = ACC_OUT_W + 1          // 27 (= G3_CONV_OUT_W)
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire        acc_clr,

    // 29 data inputs (G2_FM_W bits)
    input  wire signed [DATA_W-1:0] d0,  d1,  d2,  d3,  d4,
    input  wire signed [DATA_W-1:0] d5,  d6,  d7,  d8,  d9,
    input  wire signed [DATA_W-1:0] d10, d11, d12, d13, d14,
    input  wire signed [DATA_W-1:0] d15, d16, d17, d18, d19,
    input  wire signed [DATA_W-1:0] d20, d21, d22, d23, d24,
    input  wire signed [DATA_W-1:0] d25, d26, d27, d28,

    // 29 weights (G3_PW_WW bits)
    input  wire signed [W_W-1:0]    w0,  w1,  w2,  w3,  w4,
    input  wire signed [W_W-1:0]    w5,  w6,  w7,  w8,  w9,
    input  wire signed [W_W-1:0]    w10, w11, w12, w13, w14,
    input  wire signed [W_W-1:0]    w15, w16, w17, w18, w19,
    input  wire signed [W_W-1:0]    w20, w21, w22, w23, w24,
    input  wire signed [W_W-1:0]    w25, w26, w27, w28,

    // bias (original DATA_W format, 15 bits)
    input  wire signed [BIAS_WD-1:0] bias,

    // Full-precision output: 27-bit post-ReLU (no quantizer, per Sec 6.2.7)
    output wire signed [BIAS_OUT_W-1:0] result
);

    // -------------------------------------------------------------------------
    // 29 MAC units (Ch 6.2.5: asymmetric DATA_W x W_W multiply)
    // -------------------------------------------------------------------------
    wire signed [MAC_OUT_W-1:0] mac0,  mac1,  mac2,  mac3,  mac4,
                                 mac5,  mac6,  mac7,  mac8,  mac9,
                                 mac10, mac11, mac12, mac13, mac14,
                                 mac15, mac16, mac17, mac18, mac19,
                                 mac20, mac21, mac22, mac23, mac24,
                                 mac25, mac26, mac27, mac28;

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
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac12(.clk(clk),.rst(rst),.en(en),.a_data(d12),.b_weight(w12),.p_out(mac12));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac13(.clk(clk),.rst(rst),.en(en),.a_data(d13),.b_weight(w13),.p_out(mac13));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac14(.clk(clk),.rst(rst),.en(en),.a_data(d14),.b_weight(w14),.p_out(mac14));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac15(.clk(clk),.rst(rst),.en(en),.a_data(d15),.b_weight(w15),.p_out(mac15));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac16(.clk(clk),.rst(rst),.en(en),.a_data(d16),.b_weight(w16),.p_out(mac16));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac17(.clk(clk),.rst(rst),.en(en),.a_data(d17),.b_weight(w17),.p_out(mac17));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac18(.clk(clk),.rst(rst),.en(en),.a_data(d18),.b_weight(w18),.p_out(mac18));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac19(.clk(clk),.rst(rst),.en(en),.a_data(d19),.b_weight(w19),.p_out(mac19));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac20(.clk(clk),.rst(rst),.en(en),.a_data(d20),.b_weight(w20),.p_out(mac20));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac21(.clk(clk),.rst(rst),.en(en),.a_data(d21),.b_weight(w21),.p_out(mac21));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac22(.clk(clk),.rst(rst),.en(en),.a_data(d22),.b_weight(w22),.p_out(mac22));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac23(.clk(clk),.rst(rst),.en(en),.a_data(d23),.b_weight(w23),.p_out(mac23));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac24(.clk(clk),.rst(rst),.en(en),.a_data(d24),.b_weight(w24),.p_out(mac24));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac25(.clk(clk),.rst(rst),.en(en),.a_data(d25),.b_weight(w25),.p_out(mac25));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac26(.clk(clk),.rst(rst),.en(en),.a_data(d26),.b_weight(w26),.p_out(mac26));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac27(.clk(clk),.rst(rst),.en(en),.a_data(d27),.b_weight(w27),.p_out(mac27));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MAC_OUT_W),.DROP_LSB(DROP_LSB))
        u_mac28(.clk(clk),.rst(rst),.en(en),.a_data(d28),.b_weight(w28),.p_out(mac28));

    // -------------------------------------------------------------------------
    // adder_tree_29
    // -------------------------------------------------------------------------
    wire signed [TREE_OUT_W-1:0] tree_out;

    adder_tree_29 #(.IN_W(MAC_OUT_W), .OUT_W(TREE_OUT_W)) u_tree (
        .in0 (mac0),  .in1 (mac1),  .in2 (mac2),  .in3 (mac3),  .in4 (mac4),
        .in5 (mac5),  .in6 (mac6),  .in7 (mac7),  .in8 (mac8),  .in9 (mac9),
        .in10(mac10), .in11(mac11), .in12(mac12), .in13(mac13), .in14(mac14),
        .in15(mac15), .in16(mac16), .in17(mac17), .in18(mac18), .in19(mac19),
        .in20(mac20), .in21(mac21), .in22(mac22), .in23(mac23), .in24(mac24),
        .in25(mac25), .in26(mac26), .in27(mac27), .in28(mac28),
        .sum_out(tree_out)
    );

    // -------------------------------------------------------------------------
    // Accumulator (16 max accumulation steps for 464-ch / 29-par)
    // -------------------------------------------------------------------------
    wire signed [ACC_OUT_W-1:0] tree_ext;
    assign tree_ext = {{(ACC_OUT_W - TREE_OUT_W){tree_out[TREE_OUT_W-1]}}, tree_out};

    reg  signed [ACC_OUT_W-1:0] acc_reg;
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
    // Bias addition (+1 bit -> BIAS_OUT_W = 27 = G3_CONV_OUT_W)
    // -------------------------------------------------------------------------
    wire signed [BIAS_OUT_W-1:0] acc_ext;
    wire signed [BIAS_OUT_W-1:0] bias_ext;
    wire signed [BIAS_OUT_W-1:0] bias_sum;

    assign acc_ext  = {{(BIAS_OUT_W - ACC_OUT_W){acc_reg[ACC_OUT_W-1]}}, acc_reg};
    assign bias_ext = {{(BIAS_OUT_W - BIAS_WD){bias[BIAS_WD-1]}}, bias};
    assign bias_sum = acc_ext + bias_ext;

    // -------------------------------------------------------------------------
    // ReLU (MSB-test): clamp negative values to 0
    // -------------------------------------------------------------------------
    wire signed [BIAS_OUT_W-1:0] relu_out;
    assign relu_out = bias_sum[BIAS_OUT_W-1] ? {BIAS_OUT_W{1'b0}} : bias_sum;

    // Output: full-precision post-ReLU (quantizer removed per Sec 6.2.7)
    assign result = relu_out;

endmodule

`default_nettype wire
// =============================================================================
// END conv1x1_g3_filter_unit.v
// =============================================================================
