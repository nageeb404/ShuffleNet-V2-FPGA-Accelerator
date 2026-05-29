// =============================================================================
// bias_rom_3x3.v -- LUT-based bias ROM for the 3x3 Conv core (Group 1)
// -----------------------------------------------------------------------------
// "Bias Memory" / Figure 5.7
//
// "As known each filter has a bias weight this mean we have 24 bias that should
// be read in parallel, so we also implement this memory as LUTs and get the
// output to the 3x3 core as shown in Figure 5.7." -- Sec 5.3.1.4
//
// STRUCTURE (Fig 5.7):
// 24 bias values, all output simultaneously. No address input needed.
// Each bias is a 15-bit Q6.8 signed value (BN-folded from conv1).
// The entire 24*15 = 360-bit bus is driven combinationally from a single
// localparam constant, which Vivado maps to LUT primitives (no BRAM).
//
// PORT MAP:
// biases_flat [N_FILT*DATA_W-1:0] -- all 24 biases in one flat bus
// biases_flat[f*DATA_W +: DATA_W] = bias for filter f (0-indexed)
// This packing matches the biases_flat port of conv3x3_core.v.
//
// IMPLEMENTATION:
// The 24 bias values are hardcoded in bias_rom_3x3_init.vh as a single
// packed localparam BIASES. assign biases_flat = BIASES synthesizes to
// 360 constant wires -- no logic cells at all (just routing).
// Replace bias_rom_3x3_init.vh (via gen_bias_rom_3x3_init.py) whenever
// new BN-folded weights are extracted.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module bias_rom_3x3 #(
    parameter integer N_FILT = `G1_CONV_PAR_FILT,   // 24
    parameter integer DATA_W = `DATA_W               // 15
) (
    // All 24 biases simultaneously; biases_flat[f*DATA_W +: DATA_W] = filter f
    output wire [N_FILT * DATA_W - 1 : 0] biases_flat
);

    // -----------------------------------------------------------------------
    // Bias constants (packed localparam from bias_rom_3x3_init.vh).
    // Included inside the module to keep localparams in module scope.
    // -----------------------------------------------------------------------
    `include "bias_rom_3x3_init.vh"

    // -----------------------------------------------------------------------
    // Drive output -- purely combinational, synthesizes to constant wires
    // (: "implement this memory as LUTs")
    // -----------------------------------------------------------------------
    assign biases_flat = BIASES;

endmodule

`default_nettype wire
// =============================================================================
// END bias_rom_3x3.v
// =============================================================================
