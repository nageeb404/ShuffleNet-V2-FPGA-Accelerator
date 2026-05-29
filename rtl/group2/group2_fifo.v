// =============================================================================
// group2_fifo.v -- Variable-width 3x3-window FIFO for Group 2 DW conv
// -----------------------------------------------------------------------------
// "Group 2 FIFO" / Figure 5.36, 5.37, 5.38
//
// "In Group 2, we have 4 possible widths of the feature maps in group, so
// FIFO must support the 4 widths (56, 28, 14, 7) or we should have four
// FIFOs, one for each width. ... So, we will use one FIFO of the largest
// required size to be a one-fit-all FIFO.
// The size of the FIFO register will be (2 * W_max + 3) = 119 shift
// registers." -- Sec 5.4.6 (W_max = 58 = 56 feature map cols + 2 padding)
//
// "The FIFO register, has input MUX to select zeros to add padding when
// required or input data from the feature map memory. It has output MUXs
// to select between outputs of different widths, where the first three
// outputs are always taken from the same registers, so we only need six
// 4:1 MUXs with select line coming from the FIFO controller according to
// the current width." -- Sec 5.4.6
//
// Tap positions by width_sel (Fig 5.38):
// width_sel=11 (W=56, padded stride=58): rows at [0..2], [58..60], [116..118]
// width_sel=10 (W=28, padded stride=30): rows at [0..2], [30..32], [60..62]
// width_sel=01 (W=14, padded stride=16): rows at [0..2], [16..18], [32..34]
// width_sel=00 (W=7, padded stride=9 ): rows at [0..2], [9..11], [18..20]
//
// This module is instantiated 58 times in the DW conv block -- one per
// depthwise channel.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Ch 6.2.8: shift-register word width changed from DATA_W (15) to G1_FM_W (10).
// This FIFO holds maxpool output (G1 feature map) feeding the DW conv.
module group2_fifo #(
    parameter integer DATA_W = `G1_FM_W,       // 10 (Ch 6.2.8)
    parameter integer DEPTH  = `G2_FIFO_DEPTH  // 119 = 2*58 + 3
) (
    input  wire        clk,
    input  wire        rst,            // async active-high, clears to 0
    input  wire        shift_and_load, // 1 = shift register and load new value
    input  wire        padding_sel,    // 1 = insert zero, 0 = use data_in
    input  wire [1:0]  width_sel,      // 00=W7 01=W14 10=W28 11=W56 (Fig 5.38)
    input  wire signed [DATA_W-1:0] data_in,

    // 9 window taps: [row][col], row0=newest (current), row2=oldest
    output wire signed [DATA_W-1:0] tap00, tap01, tap02,  // row 0 (always fixed)
    output wire signed [DATA_W-1:0] tap10, tap11, tap12,  // row 1 (via 4:1 MUX)
    output wire signed [DATA_W-1:0] tap20, tap21, tap22   // row 2 (via 4:1 MUX)
);

    // -------------------------------------------------------------------------
    // 119-element shift register (Sec 5.4.6 / Fig 5.36)
    // Index 0 = newest (most recently loaded); index DEPTH-1 = oldest.
    // -------------------------------------------------------------------------
    reg signed [DATA_W-1:0] shift_reg [0:DEPTH-1];

    // Input MUX: zero-padding or data_in (Sec 5.4.6 / Fig 5.37)
    wire signed [DATA_W-1:0] din_mux;
    assign din_mux = padding_sel ? {DATA_W{1'b0}} : data_in;

    // Ch 6.2.2: rst and shift_and_load removed from FF logic to eliminate two
    // high-fanout nets (119 FFs x 58 instances = 6902 loads each).
    // FFs initialize to 0 at FPGA configuration; shift occurs every cycle.
    // rst and shift_and_load ports kept for interface compatibility.
    always @(posedge clk) begin : sr_proc
        integer k;
        for (k = DEPTH-1; k > 0; k = k - 1)
            shift_reg[k] <= shift_reg[k-1];
        shift_reg[0] <= din_mux;
    end

    // -------------------------------------------------------------------------
    // Row 0: always positions 0, 1, 2 (Sec 5.4.6 -- "first three outputs are
    // always taken from the same registers")
    // -------------------------------------------------------------------------
    assign tap00 = shift_reg[0];
    assign tap01 = shift_reg[1];
    assign tap02 = shift_reg[2];

    // -------------------------------------------------------------------------
    // Row 1: six 4:1 MUXes (Sec 5.4.6 / Fig 5.36 / Fig 5.38)
    // Stride = padded width: 9 / 16 / 30 / 58 for W= 7 / 14 / 28 / 56
    // -------------------------------------------------------------------------
    assign tap10 = (width_sel == 2'b11) ? shift_reg[58]  :
                   (width_sel == 2'b10) ? shift_reg[30]  :
                   (width_sel == 2'b01) ? shift_reg[16]  :
                                          shift_reg[9];
    assign tap11 = (width_sel == 2'b11) ? shift_reg[59]  :
                   (width_sel == 2'b10) ? shift_reg[31]  :
                   (width_sel == 2'b01) ? shift_reg[17]  :
                                          shift_reg[10];
    assign tap12 = (width_sel == 2'b11) ? shift_reg[60]  :
                   (width_sel == 2'b10) ? shift_reg[32]  :
                   (width_sel == 2'b01) ? shift_reg[18]  :
                                          shift_reg[11];

    // Row 2: stride * 2
    assign tap20 = (width_sel == 2'b11) ? shift_reg[116] :
                   (width_sel == 2'b10) ? shift_reg[60]  :
                   (width_sel == 2'b01) ? shift_reg[32]  :
                                          shift_reg[18];
    assign tap21 = (width_sel == 2'b11) ? shift_reg[117] :
                   (width_sel == 2'b10) ? shift_reg[61]  :
                   (width_sel == 2'b01) ? shift_reg[33]  :
                                          shift_reg[19];
    assign tap22 = (width_sel == 2'b11) ? shift_reg[118] :
                   (width_sel == 2'b10) ? shift_reg[62]  :
                   (width_sel == 2'b01) ? shift_reg[34]  :
                                          shift_reg[20];

endmodule

`default_nettype wire
// =============================================================================
// END group2_fifo.v
// =============================================================================
