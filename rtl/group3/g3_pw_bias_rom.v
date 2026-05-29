// =============================================================================
// g3_pw_bias_rom.v -- Group 3 Pointwise (conv5) Bias ROM (Step 7, Path A)
// -----------------------------------------------------------------------------
// Stores BN-folded, quantized conv5 biases for 64 filter groups x 16 filters.
// One entry per filter_group, all 16 filter biases packed.
// Depth = 64 entries. Width = 16 * 15 = 240 bits.
// Address: filter_group (0..63)
// Bit layout: bias[f] at bits f*15 +: 15 (f=0..15)
// ROM style: distributed (LUT-based), combinational read.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module g3_pw_bias_rom #(
 parameter INIT_FILE = "rtl/group3/weights/g3_pw_biases.hex"
) (
 // address = filter_group (0..63)
 input wire [5:0] addr,
 // data = all 16 conv5 biases for one filter_group, packed (240 bits)
 // bias[f] at bits f*15 +: 15 (f=0..15)
 output wire [239:0] data_out
);

 localparam integer DEPTH = 64; // one entry per filter_group
 localparam integer DW = 240; // G3_PW_PAR_FILT * DATA_W = 16 * 15

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
// END g3_pw_bias_rom.v
// =============================================================================
