// =============================================================================
// g2_pw_weight_rom.v -- Group 2 Pointwise Weight ROM (Step 7, Path A)
// -----------------------------------------------------------------------------
//
// Stores BN-folded, quantized PW2 weights for all 16 loops x 20 steps.
// One entry per (loop, step): depth = 16 * 20 = 320 entries.
// Address: loop_id * 20 + step_id (0..319)
// Each entry: 58 filters x 12 channels x 11 bits = 7656 bits packed.
// Bit layout: weight[f][c] at bits (f*12+c)*11 +: 11 (f=0..57, c=0..11)
//
// ROM style: distributed (LUT-based), combinational read.
// Changed from BRAM to distributed to eliminate 1-cycle BRAM read latency.
// Area: ~38K LUTs (~7.3% of ZU19EG 522K LUTs) -- acceptable for grad project.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module g2_pw_weight_rom #(
    parameter INIT_FILE = "rtl/group2/weights/g2_pw_weights.hex"
) (
    // address = loop_id * 20 + step_id (0..319)
    input  wire [8:0]    addr,
    // data = all 58 filter weights for one step (7656 bits)
    // weight[f][c] at bits (f*12+c)*11 +: 11
    output wire [7655:0] data_out
);

    localparam integer DEPTH = 320;    // 16 loops * 20 max steps
    localparam integer DW    = 7656;   // G2_PW_PAR_FILT * G2_PW_PAR_CHAN * G2_PW_WW

    (* rom_style = "distributed" *) reg [DW-1:0] rom [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            rom[i] = {DW{1'b0}};
        $readmemh(INIT_FILE, rom);
    end

    assign data_out = rom[addr];

endmodule

`default_nettype wire
// =============================================================================
// END g2_pw_weight_rom.v
// =============================================================================
