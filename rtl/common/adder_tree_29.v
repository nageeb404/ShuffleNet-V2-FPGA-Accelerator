// =============================================================================
// adder_tree_29.v -- 29-input adder tree (Module for 1x1 conv, Group 2/3)
// -----------------------------------------------------------------------------
// "adding the 29 products together using an adder tree, where the Adder3
// block is used to add each 3 products ... 27 products are added in a
// 3-level adder tree then the remaining two products are added using an
// extra 3-input adder level." --
// Structure (all Adder3 blocks, purely combinational):
// L1: 9 Adder3(IN_W) -> 9 sums [IN_W+2] (inputs 0..26)
// L2: 3 Adder3(IN_W+2) -> 3 sums [IN_W+4] (L1 sums)
// L3: 1 Adder3(IN_W+4) -> 1 sum [IN_W+6] (L2 sums)
// L4: 1 Adder3(IN_W+6) -> 1 sum [IN_W+8] (L3 + in27 + in28
// both sign-extended to IN_W+6)
// Bit growth: 4 Adder3 levels * +2 = +8 bits total.
// OUT_W = IN_W + 8 (default: 23+8=31 for 1x1 conv)
// This module is purely combinational; all pipeline registers live in the
// parent filter unit (mac_unit provides the only register stage).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module adder_tree_29 #(
 parameter integer IN_W = `MUL_OUT_W, // 23 (MAC output width)
 parameter integer OUT_W = IN_W + 8 // 31 (4 Adder3 levels x +2)
) (
 // 29 signed inputs
 input wire signed [IN_W-1:0] in0, in1, in2, in3, in4,
 input wire signed [IN_W-1:0] in5, in6, in7, in8, in9,
 input wire signed [IN_W-1:0] in10, in11, in12, in13, in14,
 input wire signed [IN_W-1:0] in15, in16, in17, in18, in19,
 input wire signed [IN_W-1:0] in20, in21, in22, in23, in24,
 input wire signed [IN_W-1:0] in25, in26, in27, in28,
 output wire signed [OUT_W-1:0] sum_out
);

 // -----------------------------------------------------------------------
 // L1: 9 Adder3 covering inputs 0..26 (27 inputs, 9 groups of 3)
 // -----------------------------------------------------------------------
 localparam L1_W = IN_W + 2;

 wire signed [L1_W-1:0] l1_0, l1_1, l1_2, l1_3, l1_4,
 l1_5, l1_6, l1_7, l1_8;

 Adder3 #(.IN_W(IN_W)) u_l1_0(.a(in0), .b(in1), .c(in2), .sum_out(l1_0));
 Adder3 #(.IN_W(IN_W)) u_l1_1(.a(in3), .b(in4), .c(in5), .sum_out(l1_1));
 Adder3 #(.IN_W(IN_W)) u_l1_2(.a(in6), .b(in7), .c(in8), .sum_out(l1_2));
 Adder3 #(.IN_W(IN_W)) u_l1_3(.a(in9), .b(in10), .c(in11), .sum_out(l1_3));
 Adder3 #(.IN_W(IN_W)) u_l1_4(.a(in12), .b(in13), .c(in14), .sum_out(l1_4));
 Adder3 #(.IN_W(IN_W)) u_l1_5(.a(in15), .b(in16), .c(in17), .sum_out(l1_5));
 Adder3 #(.IN_W(IN_W)) u_l1_6(.a(in18), .b(in19), .c(in20), .sum_out(l1_6));
 Adder3 #(.IN_W(IN_W)) u_l1_7(.a(in21), .b(in22), .c(in23), .sum_out(l1_7));
 Adder3 #(.IN_W(IN_W)) u_l1_8(.a(in24), .b(in25), .c(in26), .sum_out(l1_8));

 // -----------------------------------------------------------------------
 // L2: 3 Adder3 covering L1 outputs (9 -> 3)
 // -----------------------------------------------------------------------
 localparam L2_W = L1_W + 2;

 wire signed [L2_W-1:0] l2_0, l2_1, l2_2;

 Adder3 #(.IN_W(L1_W)) u_l2_0(.a(l1_0), .b(l1_1), .c(l1_2), .sum_out(l2_0));
 Adder3 #(.IN_W(L1_W)) u_l2_1(.a(l1_3), .b(l1_4), .c(l1_5), .sum_out(l2_1));
 Adder3 #(.IN_W(L1_W)) u_l2_2(.a(l1_6), .b(l1_7), .c(l1_8), .sum_out(l2_2));

 // -----------------------------------------------------------------------
 // L3: 1 Adder3 covering L2 outputs (3 -> 1)
 // -----------------------------------------------------------------------
 localparam L3_W = L2_W + 2;

 wire signed [L3_W-1:0] l3_out;

 Adder3 #(.IN_W(L2_W)) u_l3(.a(l2_0), .b(l2_1), .c(l2_2), .sum_out(l3_out));

 // -----------------------------------------------------------------------
 // L4 (extra): 1 Adder3 combining L3 result + in27 + in28
 // (: "remaining two products are added using an extra
 // 3-input adder level")
 // All three inputs sign-extended to L3_W (the widest input).
 // -----------------------------------------------------------------------
 wire signed [L3_W-1:0] in27_ext = {{(L3_W - IN_W){in27[IN_W-1]}}, in27};
 wire signed [L3_W-1:0] in28_ext = {{(L3_W - IN_W){in28[IN_W-1]}}, in28};

 Adder3 #(.IN_W(L3_W)) u_l4(.a(l3_out), .b(in27_ext), .c(in28_ext),
 .sum_out(sum_out));

endmodule

`default_nettype wire
// =============================================================================
// END adder_tree_29.v
// =============================================================================
