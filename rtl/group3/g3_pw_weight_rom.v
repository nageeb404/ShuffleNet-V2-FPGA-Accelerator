// =============================================================================
// g3_pw_weight_rom.v -- Group 3 Pointwise (conv5) Weight ROM (Step 6, Path A)
// -----------------------------------------------------------------------------
// Stores BN-folded, quantized conv5 weights for 64 filter groups x 16 acc steps.
// One entry per (filter_group, step): depth = 64 * 16 = 1024 entries.
// Address: filter_group * 16 + step_id (0..1023)
// Each entry: 16 filters x 29 channels x 9 bits = 4176 bits packed.
// Bit layout: weight[f][c] at bits (f*29+c)*9 +: 9 (f=0..15, c=0..28)
// Acc step s reads conv5 input channels s*29..(s+1)*29-1, which correspond
// to Group 2 loop s PW output (stored in extra_mem acc_group s).
// ROM style: block (BRAM), registered read (1-cycle latency).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module g3_pw_weight_rom #(
 parameter INIT_FILE = "rtl/group3/weights/g3_pw_weights.hex"
) (
 input wire clk,
 // address = filter_group * 16 + step_id (0..1023)
 input wire [9:0] addr,
 // data = all 16 filter weights for one step (4176 bits)
 // weight[f][c] at bits (f*29+c)*9 +: 9
 output reg [4175:0] data_out
);

 localparam integer DEPTH = 1024; // 64 filter groups * 16 acc steps
 localparam integer DW = 4176; // G3_PW_PAR_FILT * G3_PW_PAR_CHAN * G3_PW_WW

 (* rom_style = "block" *) reg [DW-1:0] rom [0:DEPTH-1];

 integer i;
 initial begin
 for (i = 0; i < DEPTH; i = i + 1)
 rom[i] = {DW{1'b0}};
 $readmemh(INIT_FILE, rom);
 end

 always @(posedge clk)
 data_out <= rom[addr];

endmodule

`default_nettype wire
// =============================================================================
// END g3_pw_weight_rom.v
// =============================================================================
