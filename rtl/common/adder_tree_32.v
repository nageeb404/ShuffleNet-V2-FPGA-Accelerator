// =============================================================================
// adder_tree_32.v -- 32-input adder tree (for FC layer, Group 3)
// -----------------------------------------------------------------------------
// "30 products are added in a 3-Adder level, 9 of them are added in 2-level
// adder tree. Final 2 products added in extra Adder3 level, then accumulated."
// -- (FC layer description)
// Structure (all Adder3 blocks, purely combinational):
// L1: 10 Adder3(IN_W) -> 10 sums [IN_W+2] (inputs 0..29)
// in30,in31 pass through (sign-ext to IN_W+2) -> 12 values total
// L2: 4 Adder3(IN_W+2) -> 4 sums [IN_W+4] (all 12 values in groups of 3)
// L3: 1 Adder3(IN_W+4) -> 1 sum [IN_W+6] (l2_0,l2_1,l2_2)
// l2_3 passes through (sign-ext to IN_W+6) -> 2 values total
// L4: 1 binary adder(IN_W+6) -> 1 sum [IN_W+7] (L3 + l2_3)
// Bit growth: 3 Adder3 levels * +2 + 1 binary adder * +1 = +7 bits total.
// OUT_W = IN_W + 7 (default: 23+7=30 for FC conv)
// Purely combinational. Pipeline registers live in parent filter unit.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module adder_tree_32 #(
 parameter integer IN_W = `MUL_OUT_W, // 23 (MAC output width)
 parameter integer OUT_W = IN_W + 7 // 30 (3 Adder3 + 1 binary adder)
) (
 // 32 signed inputs
 input wire signed [IN_W-1:0] in0, in1, in2, in3, in4,
 input wire signed [IN_W-1:0] in5, in6, in7, in8, in9,
 input wire signed [IN_W-1:0] in10, in11, in12, in13, in14,
 input wire signed [IN_W-1:0] in15, in16, in17, in18, in19,
 input wire signed [IN_W-1:0] in20, in21, in22, in23, in24,
 input wire signed [IN_W-1:0] in25, in26, in27, in28, in29,
 input wire signed [IN_W-1:0] in30, in31,
 output wire signed [OUT_W-1:0] sum_out
);

 // -----------------------------------------------------------------------
 // L1: 10 Adder3 covering inputs 0..29 (30 inputs, 10 groups of 3)
 // Remaining: in30, in31 (sign-extended to L1_W in L2)
 // -----------------------------------------------------------------------
 localparam L1_W = IN_W + 2;

 wire signed [L1_W-1:0] l1_0, l1_1, l1_2, l1_3, l1_4;
 wire signed [L1_W-1:0] l1_5, l1_6, l1_7, l1_8, l1_9;

 Adder3 #(.IN_W(IN_W)) u_l1_0(.a(in0), .b(in1), .c(in2), .sum_out(l1_0));
 Adder3 #(.IN_W(IN_W)) u_l1_1(.a(in3), .b(in4), .c(in5), .sum_out(l1_1));
 Adder3 #(.IN_W(IN_W)) u_l1_2(.a(in6), .b(in7), .c(in8), .sum_out(l1_2));
 Adder3 #(.IN_W(IN_W)) u_l1_3(.a(in9), .b(in10), .c(in11), .sum_out(l1_3));
 Adder3 #(.IN_W(IN_W)) u_l1_4(.a(in12), .b(in13), .c(in14), .sum_out(l1_4));
 Adder3 #(.IN_W(IN_W)) u_l1_5(.a(in15), .b(in16), .c(in17), .sum_out(l1_5));
 Adder3 #(.IN_W(IN_W)) u_l1_6(.a(in18), .b(in19), .c(in20), .sum_out(l1_6));
 Adder3 #(.IN_W(IN_W)) u_l1_7(.a(in21), .b(in22), .c(in23), .sum_out(l1_7));
 Adder3 #(.IN_W(IN_W)) u_l1_8(.a(in24), .b(in25), .c(in26), .sum_out(l1_8));
 Adder3 #(.IN_W(IN_W)) u_l1_9(.a(in27), .b(in28), .c(in29), .sum_out(l1_9));

 // Sign-extend in30, in31 to L1_W for L2 mixing
 wire signed [L1_W-1:0] in30_e = {{(L1_W-IN_W){in30[IN_W-1]}}, in30};
 wire signed [L1_W-1:0] in31_e = {{(L1_W-IN_W){in31[IN_W-1]}}, in31};

 // -----------------------------------------------------------------------
 // L2: 4 Adder3 covering all 12 L1-width values (10 L1 sums + in30 + in31)
 // Groups: (l1_0,l1_1,l1_2), (l1_3,l1_4,l1_5), (l1_6,l1_7,l1_8),
 // (l1_9,in30_e,in31_e)
 // -----------------------------------------------------------------------
 localparam L2_W = L1_W + 2;

 wire signed [L2_W-1:0] l2_0, l2_1, l2_2, l2_3;

 Adder3 #(.IN_W(L1_W)) u_l2_0(.a(l1_0), .b(l1_1), .c(l1_2), .sum_out(l2_0));
 Adder3 #(.IN_W(L1_W)) u_l2_1(.a(l1_3), .b(l1_4), .c(l1_5), .sum_out(l2_1));
 Adder3 #(.IN_W(L1_W)) u_l2_2(.a(l1_6), .b(l1_7), .c(l1_8), .sum_out(l2_2));
 Adder3 #(.IN_W(L1_W)) u_l2_3(.a(l1_9), .b(in30_e),.c(in31_e),.sum_out(l2_3));

 // -----------------------------------------------------------------------
 // L3: 1 Adder3 covering l2_0, l2_1, l2_2
 // Remaining: l2_3 (sign-extended to L3_W in L4)
 // -----------------------------------------------------------------------
 localparam L3_W = L2_W + 2;

 wire signed [L3_W-1:0] l3_out;

 Adder3 #(.IN_W(L2_W)) u_l3(.a(l2_0), .b(l2_1), .c(l2_2), .sum_out(l3_out));

 // Sign-extend l2_3 to L3_W
 wire signed [L3_W-1:0] l2_3_e = {{(L3_W-L2_W){l2_3[L2_W-1]}}, l2_3};

 // -----------------------------------------------------------------------
 // L4: 1 binary adder combining L3 result + l2_3
 // Note: only 2 values remain so a simple 2-input add suffices.
 // OUT_W = L3_W + 1 = IN_W + 7
 // -----------------------------------------------------------------------
 assign sum_out = l3_out + l2_3_e;

endmodule

`default_nettype wire
// =============================================================================
// END adder_tree_32.v
// =============================================================================
