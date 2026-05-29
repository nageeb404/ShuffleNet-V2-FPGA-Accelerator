// =============================================================================
// adder_tree_12.v -- 12-input signed adder tree (for G2 PW conv, PAR_CHAN=12)
// -----------------------------------------------------------------------------
// Structure (purely combinational, 3 Adder3 levels):
// L1: 4 Adder3 (inputs 0..11, 4 groups of 3) -> 4 x [IN_W+2]
// L2: 1 Adder3 (l1_0, l1_1, l1_2) -> 1 x [IN_W+4], l1_3 left
// L3: 1 Adder3 (l2_out, l1_3_ext, zero) -> 1 x [IN_W+6]
// Bit growth: 3 Adder3 levels x +2 = +6 bits total.
// OUT_W = IN_W + 6
// Used by conv1x1_filter_unit when G2_PW_PAR_CHAN=12 (DSP fit for ZU19EG).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module adder_tree_12 #(
 parameter integer IN_W = `MUL_OUT_W, // 23 default (overridden to MAC_OUT_W)
 parameter integer OUT_W = IN_W + 6 // 3 Adder3 levels x +2
) (
 input wire signed [IN_W-1:0] in0, in1, in2, in3,
 input wire signed [IN_W-1:0] in4, in5, in6, in7,
 input wire signed [IN_W-1:0] in8, in9, in10, in11,
 output wire signed [OUT_W-1:0] sum_out
);

 // -----------------------------------------------------------------------
 // L1: 4 Adder3 covering inputs 0..11 (4 groups of 3)
 // -----------------------------------------------------------------------
 localparam L1_W = IN_W + 2;

 wire signed [L1_W-1:0] l1_0, l1_1, l1_2, l1_3;

 Adder3 #(.IN_W(IN_W)) u_l1_0(.a(in0), .b(in1), .c(in2), .sum_out(l1_0));
 Adder3 #(.IN_W(IN_W)) u_l1_1(.a(in3), .b(in4), .c(in5), .sum_out(l1_1));
 Adder3 #(.IN_W(IN_W)) u_l1_2(.a(in6), .b(in7), .c(in8), .sum_out(l1_2));
 Adder3 #(.IN_W(IN_W)) u_l1_3(.a(in9), .b(in10), .c(in11), .sum_out(l1_3));

 // -----------------------------------------------------------------------
 // L2: 1 Adder3 covering l1_0, l1_1, l1_2; l1_3 remains
 // -----------------------------------------------------------------------
 localparam L2_W = L1_W + 2;

 wire signed [L2_W-1:0] l2_out;

 Adder3 #(.IN_W(L1_W)) u_l2(.a(l1_0), .b(l1_1), .c(l1_2), .sum_out(l2_out));

 // -----------------------------------------------------------------------
 // L3: 1 Adder3 combining l2_out + l1_3 + zero
 // l1_3 sign-extended from L1_W to L2_W; zero constant at L2_W
 // -----------------------------------------------------------------------
 wire signed [L2_W-1:0] l1_3_ext = {{(L2_W - L1_W){l1_3[L1_W-1]}}, l1_3};
 wire signed [L2_W-1:0] zero_ext = {L2_W{1'b0}};

 Adder3 #(.IN_W(L2_W)) u_l3(.a(l2_out), .b(l1_3_ext), .c(zero_ext),
 .sum_out(sum_out));

endmodule

`default_nettype wire
// =============================================================================
// END adder_tree_12.v
// =============================================================================
