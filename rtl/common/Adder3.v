// =============================================================================
// Adder3.v - 3-input adder using Carry-Save Adder (CSA) structure
// -----------------------------------------------------------------------------
//
// Quote (verbatim): "The 3-input adder is stage of full adders (FA) but instead
// of the carry input we use the third input. This allows them to work in
// parallel and the FAs generate 2 vectors the SUM vector and the CARRY vector
// this two vectors are added using 2-input adder."
//
// Quote (verbatim): "the 3-input adder increments the number of bits by 2"
// (Sec 5.4.1.1) -- so output width = input width + 2.
//
// Structure:
// 1) Sign-extend each of the 3 signed inputs to (IN_W + 2) bits to prevent
// overflow during the CSA stage and the final CPA stage.
// 2) For each bit position i: {carry[i], sum[i]} = a[i] + b[i] + c[i]
// using a Full Adder. SUM and CARRY vectors are produced in parallel.
// 3) CARRY vector is shifted left by 1 (the natural carry weighting).
// 4) Final 2-input CPA adds SUM + (CARRY << 1) to produce the result.
//
// Notes:
// - This module is purely combinational. Pipeline registers are inserted by
// the parent core (e.g. before/after the adder tree level), as described
// in ("The pipelining registers are used after the
// multipliers to break the long timing path").
// - All arithmetic is signed two's complement.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module Adder3 #(
    parameter integer IN_W  = 23,                  // input width (bits)
    parameter integer OUT_W = IN_W + 2             // output width = IN_W + 2 (CSA carry growth)
) (
    input  wire signed [IN_W-1:0]  a,
    input  wire signed [IN_W-1:0]  b,
    input  wire signed [IN_W-1:0]  c,
    output wire signed [OUT_W-1:0] sum_out
);

    // ----- 1) Sign-extend operands to OUT_W bits -----
    // Sign-extension is required so that the CSA + CPA produce a correct
    // signed result without overflow. With +2 bits of headroom the worst-case
    // sum of three IN_W-bit signed numbers (3 * (-2^(IN_W-1))) fits exactly.
    wire signed [OUT_W-1:0] a_ext = {{(OUT_W-IN_W){a[IN_W-1]}}, a};
    wire signed [OUT_W-1:0] b_ext = {{(OUT_W-IN_W){b[IN_W-1]}}, b};
    wire signed [OUT_W-1:0] c_ext = {{(OUT_W-IN_W){c[IN_W-1]}}, c};

    // ----- 2) Bitwise Full-Adder array (the CSA stage) -----
    // For each bit position i:
    // sum_vec[i] = a[i] XOR b[i] XOR c[i] (the FA sum output)
    // carry_vec[i] = majority(a[i], b[i], c[i]) (the FA carry output)
    // These two vectors are produced in parallel (no carry propagation).
    wire [OUT_W-1:0] sum_vec;
    wire [OUT_W-1:0] carry_vec;

    genvar i;
    generate
        for (i = 0; i < OUT_W; i = i + 1) begin : g_fa
            // Full-adder logic
            assign sum_vec  [i] = a_ext[i] ^ b_ext[i] ^ c_ext[i];
            assign carry_vec[i] = (a_ext[i] & b_ext[i])
                                | (b_ext[i] & c_ext[i])
                                | (a_ext[i] & c_ext[i]);
        end
    endgenerate

    // ----- 3) Shift CARRY vector left by 1 (natural weighting) -----
    // The carry from bit i contributes to bit (i+1) of the sum. Top bit of the
    // carry vector is dropped (out of range); the headroom from sign-extension
    // guarantees correctness for signed operands.
    wire signed [OUT_W-1:0] carry_shifted = {carry_vec[OUT_W-2:0], 1'b0};
    wire signed [OUT_W-1:0] sum_signed    = sum_vec;  // SUM vec viewed as signed

    // ----- 4) Final 2-input CPA -----
    // Adding the SUM vector and (CARRY << 1) yields the true 3-operand sum.
    assign sum_out = sum_signed + carry_shifted;

endmodule

`default_nettype wire
// =============================================================================
// END Adder3.v
// =============================================================================
