// =============================================================================
// adder_tree_9.v - 9-input signed adder tree built from 4x Adder3 (2 levels)
// -----------------------------------------------------------------------------
//
// Sec 5.3.2.1 (3x3 Conv Core methodology):
// "adding the nine multiplayer outputs using an adder tree, adding each
// three of outputs using the Adder3 block."
//
// Sec 5.4.1.1 (3by3 DW Conv methodology, same tree structure):
// "adding the 9 products together using an adder tree, where the Adder3
// block is used to add each 3 products."
//
// Sec 5.4.1.1 (bit-width growth):
// "the 3-input adder increments the number of bits by 2 ... Thus, the
// output of convolution is 27-bits"
// -> 23-bit inputs * 2 Adder3 levels = 23 + 4 = 27 bits.
//
// Structure (purely combinational; pipeline registers live in mac_unit before
// the tree and around the accumulator after the tree):
//
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
//
// Bit-widths:
// Inputs : IN_W (default 23 = MUL_OUT_W from the MAC unit)
// After Level 1 : IN_W + 2 (per Adder3 contract)
// After Level 2 : IN_W + 4 (final output)
//
// Why this width:
// so 9-input -> 2 levels -> +4 bits total. With IN_W=23, OUT_W=27, which
// 3by3 DW conv core that uses the same 9-input tree.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module adder_tree_9 #(
    parameter integer IN_W  = `MUL_OUT_W,             // 23
    parameter integer OUT_W = IN_W + 4                // 27 (= IN_W + 2*ADD3_GROW)
) (
    input  wire signed [IN_W -1:0] in0,
    input  wire signed [IN_W -1:0] in1,
    input  wire signed [IN_W -1:0] in2,
    input  wire signed [IN_W -1:0] in3,
    input  wire signed [IN_W -1:0] in4,
    input  wire signed [IN_W -1:0] in5,
    input  wire signed [IN_W -1:0] in6,
    input  wire signed [IN_W -1:0] in7,
    input  wire signed [IN_W -1:0] in8,
    output wire signed [OUT_W-1:0] sum_out
);

    // Intermediate widths
    localparam integer L1_W = IN_W + `ADD3_GROW;   // = IN_W + 2 (25)
    localparam integer L2_W = L1_W + `ADD3_GROW;   // = IN_W + 4 (27)

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
