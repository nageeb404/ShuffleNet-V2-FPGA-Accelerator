// =============================================================================
// adder_tree_9.v - 9-input signed adder tree built from 4x Adder3 (2 levels)
// -----------------------------------------------------------------------------
// Bit-growth: +2 bits per Adder3 level, so 2 levels = +4 bits total.
// With IN_W=23 (MAC output), OUT_W=27 (used by conv3x3/DW cores).
// Structure (purely combinational; pipeline registers live in mac_unit before
// the tree and around the accumulator after the tree):
// in[0] -+
// in[1] -+-- Adder3 -- L1[0] -+
// in[2] -+ |
// |
// in[3] -+ |
// in[4] -+-- Adder3 -- L1[1] -+-- Adder3 -- out
// in[5] -+ |
// |
// in[6] -+ |
// in[7] -+-- Adder3 -- L1[2] -+
// in[8] -+
// Bit-widths:
// Inputs : IN_W (default 23 = MUL_OUT_W from the MAC unit)
// After Level 1 : IN_W + 2 (per Adder3 contract)
// After Level 2 : IN_W + 4 (final output)
// Bit-widths: +2 bits per Adder3 level. 2 levels -> +4 bits total.
// With IN_W=23 (MAC output): OUT_W=27 (matches conv3x3/DW core output).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module adder_tree_9 #(
 parameter integer IN_W = `MUL_OUT_W, // 23
 parameter integer OUT_W = IN_W + 4 // 27 (= IN_W + 2*ADD3_GROW)
) (
 input wire signed [IN_W -1:0] in0,
 input wire signed [IN_W -1:0] in1,
 input wire signed [IN_W -1:0] in2,
 input wire signed [IN_W -1:0] in3,
 input wire signed [IN_W -1:0] in4,
 input wire signed [IN_W -1:0] in5,
 input wire signed [IN_W -1:0] in6,
 input wire signed [IN_W -1:0] in7,
 input wire signed [IN_W -1:0] in8,
 output wire signed [OUT_W-1:0] sum_out
);

 // Intermediate widths
 localparam integer L1_W = IN_W + `ADD3_GROW; // = IN_W + 2 (25)
 localparam integer L2_W = L1_W + `ADD3_GROW; // = IN_W + 4 (27)

 // ----- Level 1: three Adder3 in parallel -----
 wire signed [L1_W-1:0] l1_0;
 wire signed [L1_W-1:0] l1_1;
 wire signed [L1_W-1:0] l1_2;

 Adder3 #(.IN_W(IN_W), .OUT_W(L1_W)) u_l1_0 (
 .a(in0), .b(in1), .c(in2), .sum_out(l1_0)
 );
 Adder3 #(.IN_W(IN_W), .OUT_W(L1_W)) u_l1_1 (
 .a(in3), .b(in4), .c(in5), .sum_out(l1_1)
 );
 Adder3 #(.IN_W(IN_W), .OUT_W(L1_W)) u_l1_2 (
 .a(in6), .b(in7), .c(in8), .sum_out(l1_2)
 );

 // ----- Level 2: one Adder3 combining the three L1 outputs -----
 Adder3 #(.IN_W(L1_W), .OUT_W(L2_W)) u_l2 (
 .a(l1_0), .b(l1_1), .c(l1_2), .sum_out(sum_out)
 );

endmodule

`default_nettype wire
// =============================================================================
// END adder_tree_9.v
// =============================================================================
