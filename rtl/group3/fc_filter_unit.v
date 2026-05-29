// =============================================================================
// fc_filter_unit.v -- Single FC filter computation unit for Group 3 (Module 3.3a)
// -----------------------------------------------------------------------------
// "Group 3 Design" / Figure 5.60, Table 5.11
//
// Ch 6.2.5 + 6.2.8 + 6.2.4: per-layer optimum widths applied.
// data input (avgpool output) : 9 bits (G3_FM_W, 5-bit fraction)
// weight input : 9 bits (FC_WW, 8-bit fraction)
// DROP_LSB = DATA_F+W_F-9 : 4 (5+8-9=4)
// MAC output : 14 bits (9+9-4)
// adder_tree_32 output : 21 bits (+7 from 4-level tree)
// accumulator output : 26 bits (+5 from ceil(log2(32))=5)
// bias adder output : 27 bits (+1, bias=FC_BIAS_W=11)
// Ch 6.2.4: arithmetic right-shift >>2 before quantizer
// final output : 9 bits (G3_FM_W, HAS_RELU=0)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module fc_filter_unit #(
    parameter integer N_PAR   = 32,           // parallel channels
    parameter integer DATA_W  = `G3_FM_W,     // 9 (avgpool output = FC input)
    parameter integer W_W     = `FC_WW,       // 9 (weight width)
    parameter integer BIAS_WD = `FC_BIAS_W,   // 11 (bias width)
    parameter integer DROP_LSB = 4,           // DATA_F+W_F-9 = 5+8-9
    parameter integer MUL_W   = DATA_W + W_W - DROP_LSB, // 14
    parameter integer TREE_W  = MUL_W + 7,   // 21 (+7 for 32-input tree)
    parameter integer ACC_W   = TREE_W + 5,  // 26 (+5 for ceil(log2(32)))
    parameter integer BIAS_W  = ACC_W + 1,   // 27 (2-input bias add)
    parameter integer OUT_W   = `G3_FM_W,     // 9 (quantizer output)
    parameter integer HAS_RELU = 0
) (
    input  wire clk,
    input  wire rst,
    input  wire en,
    input  wire acc_clr,

    input  wire signed [DATA_W-1:0] d0,  d1,  d2,  d3,  d4,  d5,  d6,  d7,
    input  wire signed [DATA_W-1:0] d8,  d9,  d10, d11, d12, d13, d14, d15,
    input  wire signed [DATA_W-1:0] d16, d17, d18, d19, d20, d21, d22, d23,
    input  wire signed [DATA_W-1:0] d24, d25, d26, d27, d28, d29, d30, d31,

    input  wire signed [W_W-1:0]    w0,  w1,  w2,  w3,  w4,  w5,  w6,  w7,
    input  wire signed [W_W-1:0]    w8,  w9,  w10, w11, w12, w13, w14, w15,
    input  wire signed [W_W-1:0]    w16, w17, w18, w19, w20, w21, w22, w23,
    input  wire signed [W_W-1:0]    w24, w25, w26, w27, w28, w29, w30, w31,

    input  wire signed [BIAS_WD-1:0] bias,
    output wire signed [OUT_W-1:0]   result
);

    // -------------------------------------------------------------------------
    // 32 MAC units (Ch 6.2.5: asymmetric DATA_W x W_W multiply)
    // -------------------------------------------------------------------------
    wire signed [MUL_W-1:0] mac0,  mac1,  mac2,  mac3,  mac4,  mac5,  mac6,  mac7;
    wire signed [MUL_W-1:0] mac8,  mac9,  mac10, mac11, mac12, mac13, mac14, mac15;
    wire signed [MUL_W-1:0] mac16, mac17, mac18, mac19, mac20, mac21, mac22, mac23;
    wire signed [MUL_W-1:0] mac24, mac25, mac26, mac27, mac28, mac29, mac30, mac31;

    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m0 (.clk(clk),.rst(rst),.en(en),.a_data(d0) ,.b_weight(w0) ,.p_out(mac0));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m1 (.clk(clk),.rst(rst),.en(en),.a_data(d1) ,.b_weight(w1) ,.p_out(mac1));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m2 (.clk(clk),.rst(rst),.en(en),.a_data(d2) ,.b_weight(w2) ,.p_out(mac2));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m3 (.clk(clk),.rst(rst),.en(en),.a_data(d3) ,.b_weight(w3) ,.p_out(mac3));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m4 (.clk(clk),.rst(rst),.en(en),.a_data(d4) ,.b_weight(w4) ,.p_out(mac4));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m5 (.clk(clk),.rst(rst),.en(en),.a_data(d5) ,.b_weight(w5) ,.p_out(mac5));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m6 (.clk(clk),.rst(rst),.en(en),.a_data(d6) ,.b_weight(w6) ,.p_out(mac6));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m7 (.clk(clk),.rst(rst),.en(en),.a_data(d7) ,.b_weight(w7) ,.p_out(mac7));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m8 (.clk(clk),.rst(rst),.en(en),.a_data(d8) ,.b_weight(w8) ,.p_out(mac8));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m9 (.clk(clk),.rst(rst),.en(en),.a_data(d9) ,.b_weight(w9) ,.p_out(mac9));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m10(.clk(clk),.rst(rst),.en(en),.a_data(d10),.b_weight(w10),.p_out(mac10));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m11(.clk(clk),.rst(rst),.en(en),.a_data(d11),.b_weight(w11),.p_out(mac11));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m12(.clk(clk),.rst(rst),.en(en),.a_data(d12),.b_weight(w12),.p_out(mac12));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m13(.clk(clk),.rst(rst),.en(en),.a_data(d13),.b_weight(w13),.p_out(mac13));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m14(.clk(clk),.rst(rst),.en(en),.a_data(d14),.b_weight(w14),.p_out(mac14));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m15(.clk(clk),.rst(rst),.en(en),.a_data(d15),.b_weight(w15),.p_out(mac15));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m16(.clk(clk),.rst(rst),.en(en),.a_data(d16),.b_weight(w16),.p_out(mac16));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m17(.clk(clk),.rst(rst),.en(en),.a_data(d17),.b_weight(w17),.p_out(mac17));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m18(.clk(clk),.rst(rst),.en(en),.a_data(d18),.b_weight(w18),.p_out(mac18));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m19(.clk(clk),.rst(rst),.en(en),.a_data(d19),.b_weight(w19),.p_out(mac19));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m20(.clk(clk),.rst(rst),.en(en),.a_data(d20),.b_weight(w20),.p_out(mac20));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m21(.clk(clk),.rst(rst),.en(en),.a_data(d21),.b_weight(w21),.p_out(mac21));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m22(.clk(clk),.rst(rst),.en(en),.a_data(d22),.b_weight(w22),.p_out(mac22));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m23(.clk(clk),.rst(rst),.en(en),.a_data(d23),.b_weight(w23),.p_out(mac23));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m24(.clk(clk),.rst(rst),.en(en),.a_data(d24),.b_weight(w24),.p_out(mac24));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m25(.clk(clk),.rst(rst),.en(en),.a_data(d25),.b_weight(w25),.p_out(mac25));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m26(.clk(clk),.rst(rst),.en(en),.a_data(d26),.b_weight(w26),.p_out(mac26));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m27(.clk(clk),.rst(rst),.en(en),.a_data(d27),.b_weight(w27),.p_out(mac27));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m28(.clk(clk),.rst(rst),.en(en),.a_data(d28),.b_weight(w28),.p_out(mac28));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m29(.clk(clk),.rst(rst),.en(en),.a_data(d29),.b_weight(w29),.p_out(mac29));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m30(.clk(clk),.rst(rst),.en(en),.a_data(d30),.b_weight(w30),.p_out(mac30));
    mac_unit #(.DATA_W(DATA_W),.W_W(W_W),.MUL_OUT_W(MUL_W),.DROP_LSB(DROP_LSB))
        u_m31(.clk(clk),.rst(rst),.en(en),.a_data(d31),.b_weight(w31),.p_out(mac31));

    // -------------------------------------------------------------------------
    // Adder tree: 32 MAC outputs -> 21-bit sum
    // -------------------------------------------------------------------------
    wire signed [TREE_W-1:0] tree_sum;

    adder_tree_32 u_tree (
        .in0(mac0),   .in1(mac1),   .in2(mac2),   .in3(mac3),
        .in4(mac4),   .in5(mac5),   .in6(mac6),   .in7(mac7),
        .in8(mac8),   .in9(mac9),   .in10(mac10), .in11(mac11),
        .in12(mac12), .in13(mac13), .in14(mac14), .in15(mac15),
        .in16(mac16), .in17(mac17), .in18(mac18), .in19(mac19),
        .in20(mac20), .in21(mac21), .in22(mac22), .in23(mac23),
        .in24(mac24), .in25(mac25), .in26(mac26), .in27(mac27),
        .in28(mac28), .in29(mac29), .in30(mac30), .in31(mac31),
        .sum_out(tree_sum)
    );

    // -------------------------------------------------------------------------
    // Accumulator: 26-bit register
    // -------------------------------------------------------------------------
    reg signed [ACC_W-1:0] acc_reg;
    wire signed [ACC_W-1:0] tree_ext = {{(ACC_W-TREE_W){tree_sum[TREE_W-1]}}, tree_sum};
    wire signed [ACC_W-1:0] acc_mux  = acc_clr ? tree_ext : (acc_reg + tree_ext);

    always @(posedge clk or posedge rst) begin
        if (rst)
            acc_reg <= {ACC_W{1'b0}};
        else
            acc_reg <= acc_mux;
    end

    // -------------------------------------------------------------------------
    // Bias addition: 27-bit signed (FC_BIAS_W = 11 bits, 8-bit fraction)
    // -------------------------------------------------------------------------
    wire signed [BIAS_W-1:0] acc_biased;
    wire signed [BIAS_W-1:0] bias_ext = {{(BIAS_W-BIAS_WD){bias[BIAS_WD-1]}}, bias};
    assign acc_biased = {{(BIAS_W-ACC_W){acc_reg[ACC_W-1]}}, acc_reg} + bias_ext;

    // -------------------------------------------------------------------------
    // Ch 6.2.4: arithmetic right-shift by 2 before quantizer.
    // -------------------------------------------------------------------------
    wire signed [BIAS_W-1:0] acc_shifted;
    assign acc_shifted = acc_biased >>> 2;

    // -------------------------------------------------------------------------
    // Two-sided saturating quantizer (HAS_RELU=0), output G3_FM_W = 9 bits
    // -------------------------------------------------------------------------
    quantizer #(
        .IN_W    (BIAS_W),
        .OUT_W   (OUT_W),
        .HAS_RELU(HAS_RELU)
    ) u_quant (
        .in_data (acc_shifted),
        .out_data(result)
    );

endmodule

`default_nettype wire
// =============================================================================
// END fc_filter_unit.v
// =============================================================================
