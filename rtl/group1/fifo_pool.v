// =============================================================================
// fifo_pool.v -- Shift-register FIFO for maxpool input (depth 231)
// -----------------------------------------------------------------------------
// "For the Max Pooling: we use a 24 FIFOs of size (2*114+3) to store
// the output of the 3x3 conv block and get each window ready for the
// max pooling core to process it without store to memory."
// -> DEPTH = 2*114+3 = 231 (= G1_POOL_FIFO_DEPTH in shufflenet_pkg.vh)
// -> TAP_STRIDE = (231-3)/2 = 114 = padded maxpool input width (112+2)
// Structure identical to fifo_3x3; only the depth and tap stride differ.
// This module is a parameter-override wrapper around fifo_3x3 to avoid
// code duplication (as noted in: "almost having the same
// operation and functions").
// The 24 instances of this FIFO sit between the conv3x3_core output and
// the maxpool_core input (Figure 5.11).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module fifo_pool #(
 parameter integer DATA_W = `DATA_W, // 15
 parameter integer DEPTH = `G1_POOL_FIFO_DEPTH, // 231
 parameter integer TAP_STRIDE = (DEPTH - 3) / 2 // 114
) (
 input wire clk,
 input wire rst,
 input wire shift_and_load,
 input wire padding_sel,
 input wire signed [DATA_W-1:0] data_in,
 output wire signed [DATA_W-1:0] tap0,
 output wire signed [DATA_W-1:0] tap1,
 output wire signed [DATA_W-1:0] tap2
);

 fifo_3x3 #(
 .DATA_W (DATA_W),
 .DEPTH (DEPTH),
 .TAP_STRIDE(TAP_STRIDE)
 ) u_fifo (
 .clk (clk),
 .rst (rst),
 .shift_and_load(shift_and_load),
 .padding_sel (padding_sel),
 .data_in (data_in),
 .tap0 (tap0),
 .tap1 (tap1),
 .tap2 (tap2)
 );

endmodule

`default_nettype wire
// =============================================================================
// END fifo_pool.v
// =============================================================================
