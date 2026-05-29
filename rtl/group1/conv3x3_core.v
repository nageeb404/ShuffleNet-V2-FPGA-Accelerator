// =============================================================================
// conv3x3_core.v -- 24-parallel-filter 3x3 convolution computation core
// -----------------------------------------------------------------------------
// "3x3 Convolution Core" / Figure 5.8 / Table 5.1
//
// Ch 6.2.5 + 6.2.8: per-layer widths applied.
// data inputs (photo pixels) : 8 bits (IN_W = PHOTO_W)
// weight inputs : 12 bits (W_W = G1_CONV_WW)
// bias inputs : 15 bits (BIAS_WD = DATA_W, original)
// results : 10 bits (OUT_W = G1_FM_W)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module conv3x3_core #(
    parameter integer N_FILT  = `G1_CONV_PAR_FILT, // 24
    parameter integer IN_W    = `PHOTO_W,           // 8 (photo pixel input)
    parameter integer W_W     = `G1_CONV_WW,        // 12 (weight width)
    parameter integer BIAS_WD = `DATA_W,            // 15 (bias, original format)
    parameter integer OUT_W   = `G1_FM_W            // 10 (result width)
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire        acc_clr,

    // 9 shared data inputs (photo pixels, IN_W bits each)
    input  wire signed [IN_W-1:0]  d0, d1, d2, d3, d4, d5, d6, d7, d8,

    // 24*9 weight inputs (W_W bits each)
    // Filter f, tap t at: weights_flat[(f*9 + t)*W_W +: W_W]
    input  wire [N_FILT*9*W_W-1:0] weights_flat,

    // 24 bias inputs (BIAS_WD bits each)
    // Filter f at: biases_flat[f*BIAS_WD +: BIAS_WD]
    input  wire [N_FILT*BIAS_WD-1:0] biases_flat,

    // 24 results (OUT_W bits each, post-ReLU)
    // Filter f at: results_flat[f*OUT_W +: OUT_W]
    output wire [N_FILT*OUT_W-1:0] results_flat
);

    genvar f;
    generate
        for (f = 0; f < N_FILT; f = f + 1) begin : gen_filt

            conv3x3_filter_unit #(
                .DATA_W (IN_W),
                .W_W    (W_W),
                .BIAS_WD(BIAS_WD),
                .OUT_W  (OUT_W)
            ) u_filt (
                .clk    (clk),
                .rst    (rst),
                .en     (en),
                .acc_clr(acc_clr),
                .d0(d0), .d1(d1), .d2(d2),
                .d3(d3), .d4(d4), .d5(d5),
                .d6(d6), .d7(d7), .d8(d8),
                .w0(weights_flat[(f*9+0)*W_W +: W_W]),
                .w1(weights_flat[(f*9+1)*W_W +: W_W]),
                .w2(weights_flat[(f*9+2)*W_W +: W_W]),
                .w3(weights_flat[(f*9+3)*W_W +: W_W]),
                .w4(weights_flat[(f*9+4)*W_W +: W_W]),
                .w5(weights_flat[(f*9+5)*W_W +: W_W]),
                .w6(weights_flat[(f*9+6)*W_W +: W_W]),
                .w7(weights_flat[(f*9+7)*W_W +: W_W]),
                .w8(weights_flat[(f*9+8)*W_W +: W_W]),
                .bias  (biases_flat[f*BIAS_WD +: BIAS_WD]),
                .result(results_flat[f*OUT_W  +: OUT_W])
            );

        end
    endgenerate

endmodule

`default_nettype wire
// =============================================================================
// END conv3x3_core.v
// =============================================================================
