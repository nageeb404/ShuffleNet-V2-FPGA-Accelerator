// =============================================================================
// g2_dw_bias_rom.v -- Group 2 Depthwise Bias ROM (Step 7, Path A)
// -----------------------------------------------------------------------------
//
// Stores BN-folded, quantized DW conv biases for all 16 Shuffle block loops.
// One entry per loop, all 58 filter biases packed.
// Depth = 16 entries. Width = 58 * 15 = 870 bits.
// Address: loop_id (0..15)
// Bit layout: bias[f] at bits f*15 +: 15 (f=0..57)
//
// ROM style: distributed (LUT-based), combinational read.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module g2_dw_bias_rom #(
    parameter INIT_FILE = "rtl/group2/weights/g2_dw_biases.hex"
) (
    // address = loop_id (0..15)
    input  wire [3:0]    addr,
    // data = all 58 DW biases for one loop, packed (870 bits)
    // bias[f] at bits f*15 +: 15 (f=0..57)
    output wire [869:0]  data_out
);

    localparam integer DEPTH = 16;    // one entry per loop
    localparam integer DW    = 870;   // G2_DW_PAR_FILT * DATA_W = 58 * 15

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
// END g2_dw_bias_rom.v
// =============================================================================
