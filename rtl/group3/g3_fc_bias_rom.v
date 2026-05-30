// =============================================================================
// g3_fc_bias_rom.v -- Group 3 FC Layer Bias ROM (Step 6, Path A)
// -----------------------------------------------------------------------------
//
// Stores quantized FC biases for all 1000 ImageNet classes.
// One entry per class: depth = 1000 entries.
// Address: class_id (0..999)
//
// ROM style: distributed (LUT-based), combinational read.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module g3_fc_bias_rom #(
    parameter INIT_FILE = "g3_fc_biases.hex"
) (
    // address = class_id (0..999)
    input  wire [9:0]    addr,
    // data = one 11-bit FC bias (FC_BIAS_W format, signed)
    output wire [10:0]   data_out
);

    localparam integer DEPTH = 1000;   // G3_FC_OUT

    (* rom_style = "distributed" *) reg [10:0] rom [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            rom[i] = 11'b0;
        $readmemh(INIT_FILE, rom);
    end

    assign data_out = rom[addr];

endmodule

`default_nettype wire
// =============================================================================
// END g3_fc_bias_rom.v
// =============================================================================
