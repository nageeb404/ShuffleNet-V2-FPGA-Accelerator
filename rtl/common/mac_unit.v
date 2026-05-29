// =============================================================================
// mac_unit.v - Multiply-and-truncate unit with pipeline register
// -----------------------------------------------------------------------------
// Bit-format details:
// - Input data: signed Q6.8, 15 bits (1 sign + 6 int + 8 frac)
// - Input weight: signed Q6.8, 15 bits (same format)
// - 15x15 multiply result: signed Q12.16, 30 bits
// (1 sign-of-sign + 12 int + 16 frac, conceptually)
// Note: Verilog signed * signed yields a (W1+W2)-wide signed result.
// - Drop 7 LSBs (rounding-toward-negative-infinity by truncation):
// Q12.16 -> Q12.9, 23 bits (matches MUL_OUT_W in shufflenet_pkg.vh)
// - Output register holds the 23-bit truncated product
// DSP48 mapping:
// On Xilinx Virtex-7, signed 15x15 multiplication with a registered output
// is the canonical pattern that Vivado infers as a DSP48E1 MULT.
// No manual instantiation needed -- the `*` operator + the pipeline
// register at the output gives Vivado all the cues it needs.
// Pipeline characteristics:
// - Latency : 1 clock cycle (input -> registered output)
// - Throughput : 1 multiply per clock
// - Reset : REMOVED (Ch 6.2.2): async rst was a high-fanout net
// (e.g. 522 loads in DW core, 1682 loads in PW core).
// FPGA FFs power-up to 0; FIFO zeros via padding_sel=1
// in IDLE provide natural initialization for DW inputs;
// PW (1x1) is always operating; acc_clr handles the rest.
// Why drop 7 LSBs specifically:
// After a Q6.8 * Q6.8 multiply we have Q12.16 (16 fractional bits). The
// datapath only carries 8 fractional bits along the adder tree, so we'd
// eventually have to drop 8 LSBs anyway. Dropping 7 LSBs at the multiplier
// output leaves Q12.9 -- a small extra fractional bit of headroom for the
// adder tree, which the quantizer absorbs at the end of the core. This
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module mac_unit #(
 parameter integer DATA_W = `DATA_W, // data input width
 parameter integer W_W = DATA_W, // weight input width (Ch 6.2.5)
 parameter integer MUL_OUT_W = `MUL_OUT_W, // truncated product width
 parameter integer DROP_LSB = `MUL_DROP_LSB // LSBs dropped after multiply
) (
 input wire clk,
 input wire rst, // asynchronous, active-high
 input wire en, // pipeline-register enable
 input wire signed [DATA_W-1:0] a_data, // feature map input
 input wire signed [W_W-1:0] b_weight, // weight input (Ch 6.2.5)
 output reg signed [MUL_OUT_W-1:0] p_out // truncated product, registered
);

 // ------------- Full product (combinational) ---------------------------
 // Verilog signed*signed: width = DATA_W + W_W.
 // Vivado infers DSP48E1 from this pattern plus the registered output.
 localparam integer MUL_FULL_W = DATA_W + W_W; // Ch 6.2.5: asymmetric multiply
 wire signed [MUL_FULL_W-1:0] product_full = a_data * b_weight;

 // ------------- Drop the 7 LSBs ----
 // After dropping, the remaining width is (2*DATA_W - DROP_LSB) = 23 bits,
 // which equals MUL_OUT_W defined in shufflenet_pkg.vh. The slice
 // [MUL_FULL_W-1 : DROP_LSB] preserves the sign bit (MSB) and discards
 // the bottom DROP_LSB bits (7 LSBs discarded as quantization noise).
 wire signed [MUL_OUT_W-1:0] product_truncated =
 product_full[MUL_FULL_W-1 : DROP_LSB];

 // ------------- Pipeline register ----
 // Clock-gated by `en` for dynamic-power savings.
 // Ch 6.2.2: rst removed from sensitivity list to eliminate high-fanout
 // async-reset net. rst port kept for interface compatibility.
 always @(posedge clk) begin
 if (en)
 p_out <= product_truncated;
 end

endmodule

`default_nettype wire
// =============================================================================
// END mac_unit.v
// =============================================================================
