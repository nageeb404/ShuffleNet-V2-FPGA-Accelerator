// =============================================================================
// weights_rom_3x3.v -- LUT-based weight ROM for the 3x3 Conv core (Group 1)
// -----------------------------------------------------------------------------
// "Weights Memory" / Figure 5.6
//
// "As Group1 parallelism is 24 filter, 3 in the window and 3 parallel channels
// this mean we need 3*3*24 = 216 weight each clock cycle ... each instance
// will have only 3 weights stored (very bad utilization) so we implement it
// by LUTs and its output goes to mux as shown in Figure 5.6." -- Sec 5.3.1.3
//
// STRUCTURE (Fig 5.6 -- "One Filter"):
// For each (filter f, channel c, row r): one LUT cell stores 3 weight values,
// one per spatial column (col=0,1,2). A 2-bit address selects the column.
// Total LUT cells: 24 filters x 3 channels x 3 rows = 216.
// All 216 outputs (15 bits each) are packed onto the flat bus simultaneously.
//
// WEIGHT ORDERING in the flat bus (matches conv3x3_core.v port packing):
// weights_flat[(f*9 + t)*DATA_W +: DATA_W] where t = c*3 + r
// t=0: ch0,row0 t=1: ch0,row1 t=2: ch0,row2
// t=3: ch1,row0 t=4: ch1,row1 t=5: ch1,row2
// t=6: ch2,row0 t=7: ch2,row1 t=8: ch2,row2
//
// IMPLEMENTATION:
// Three column-packed parameter buses (COL0, COL1, COL2) defined in
// weights_rom_3x3_init.vh. A 3-way combinational MUX on addr selects
// the correct column bus. This synthesizes to LUT6 instances (distributed
// ROM)
//
// To load real BN-folded Q6.8 weights:
// 1. Run scripts/extract_weights_conv1.py on Colab
// 2. Replace rtl/common/weights_rom_3x3_init.vh with generated output
// 3. Re-synthesize / re-simulate
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Ch 6.2.5: weight width changed from DATA_W (15) to G1_CONV_WW (12).
// weights_rom_3x3_init.vh must be regenerated with 12-bit Q2.9 values.
module weights_rom_3x3 #(
    parameter integer N_FILT  = `G1_CONV_PAR_FILT,  // 24
    parameter integer N_CHAN  = `G1_CONV_PAR_CHAN,   // 3
    parameter integer N_WIN   = `G1_CONV_PAR_WIN,    // 3 rows per channel
    parameter integer DATA_W  = `G1_CONV_WW          // 12 (Ch 6.2.5)
) (
    input  wire [1:0]  addr,   // column address: 0=left, 1=centre, 2=right

    // 216 x 12-bit weight bus (packed per conv3x3_core convention)
    output reg  [N_FILT * N_CHAN * N_WIN * DATA_W - 1 : 0] weights_flat
);

    // -----------------------------------------------------------------------
    // Weight constants (localparams for COL0/1/2_WEIGHTS).
    // Included here (inside the module) so declarations are in module scope.
    // Replace this file with real Colab weights when available.
    // -----------------------------------------------------------------------
    `include "weights_rom_3x3_init.vh"

    // -----------------------------------------------------------------------
    // 3-way column MUX
    // Each column bus contains all 216 weights for that spatial column.
    // addr selects which column the convolution is currently accumulating.
    // Synthesizes to: one LUT per weight bit (distributed ROM, no BRAM).
    // -----------------------------------------------------------------------
    always @(*) begin
        case (addr)
            2'd0:    weights_flat = COL0_WEIGHTS;
            2'd1:    weights_flat = COL1_WEIGHTS;
            2'd2:    weights_flat = COL2_WEIGHTS;
            default: weights_flat = {(N_FILT * N_CHAN * N_WIN * DATA_W){1'b0}};
        endcase
    end

endmodule

`default_nettype wire
// =============================================================================
// END weights_rom_3x3.v
// =============================================================================
