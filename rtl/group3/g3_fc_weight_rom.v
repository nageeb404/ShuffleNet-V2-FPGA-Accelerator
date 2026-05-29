// =============================================================================
// g3_fc_weight_rom.v -- Group 3 FC Layer Weight ROM (Step 6, Path A)
// -----------------------------------------------------------------------------
//
// Stores quantized FC (linear 1024->1000) weights for all 1000 classes.
// One entry per (class, step): depth = 1000 * 32 = 32000 entries.
// Address: class_id * 32 + step_id (0..31999)
// Each entry: 32 channels x 9 bits = 288 bits packed.
// Bit layout: weight[c] at bits c*9 +: 9 (c=0..31)
//
// Acc step s reads FC input channels s*32..(s+1)*32-1 from the register file
// (32 steps x 32 channels = 1024 total avgpool outputs).
//
// ROM style: block (BRAM), registered read (1-cycle latency).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module g3_fc_weight_rom #(
    parameter INIT_FILE = "rtl/group3/weights/g3_fc_weights.hex"
) (
    input  wire         clk,
    // address = class_id * 32 + step_id (0..31999)
    input  wire [14:0]  addr,
    // data = 32 FC weights for one step (288 bits)
    // weight[c] at bits c*9 +: 9
    output reg  [287:0] data_out
);

    localparam integer DEPTH = 32000;  // 1000 classes * 32 steps
    localparam integer DW    = 288;    // G3_FC_PAR_CHAN * FC_WW = 32*9

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
// END g3_fc_weight_rom.v
// =============================================================================
