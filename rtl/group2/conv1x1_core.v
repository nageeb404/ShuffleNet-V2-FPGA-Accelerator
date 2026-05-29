// =============================================================================
// conv1x1_core.v -- 58-parallel-filter 1x1 convolution computation core
// -----------------------------------------------------------------------------
// "1by1 Convolution" / Table 5.4
//
// G2_PW_PAR_CHAN reduced from 29 to 12 for ZU19EG DSP budget.
//
// Table 5.4 (Parallelism in the 1x1 Conv Core):
// Parallelism in Filters : 58 (= G2_PW_PAR_FILT)
// Parallelism in Channels : 12 (= G2_PW_PAR_CHAN, reduced from 29)
//
// Ch 6.2.5 + 6.2.8: per-layer widths applied.
// data inputs : 12 bits (IN_W = G2_FM_W)
// weight inputs: 11 bits (W_W = G2_PW_WW)
// bias inputs : 13 bits (BIAS_WD = G2_BIAS_W)
// results : 12 bits (OUT_W = G2_FM_W)
//
// Port packing convention:
// weights_flat : [N_FILT*N_CHAN*W_W-1 : 0]
// Filter f, channel c --> weights_flat[(f*N_CHAN + c)*W_W +: W_W]
// biases_flat : [N_FILT*BIAS_WD-1 : 0]
// results_flat : [N_FILT*OUT_W-1 : 0]
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module conv1x1_core #(
    parameter integer N_FILT  = `G2_PW_PAR_FILT,  // 58
    parameter integer N_CHAN  = `G2_PW_PAR_CHAN,   // 12
    parameter integer IN_W    = `G2_FM_W,           // 12
    parameter integer W_W     = `G2_PW_WW,          // 11
    parameter integer BIAS_WD = `G2_BIAS_W,         // 13
    parameter integer OUT_W   = `G2_FM_W            // 12
) (
    input  wire clk,
    input  wire rst,
    input  wire en,
    input  wire acc_clr,

    // 12 shared data inputs (same for all 58 filters; step-loaded from memory)
    input  wire signed [IN_W-1:0] d0,  d1,  d2,  d3,
    input  wire signed [IN_W-1:0] d4,  d5,  d6,  d7,
    input  wire signed [IN_W-1:0] d8,  d9,  d10, d11,

    // 58*12 weight inputs: filter f, channel c: weights_flat[(f*N_CHAN+c)*W_W +: W_W]
    input  wire [N_FILT*N_CHAN*W_W-1:0] weights_flat,

    // 58 bias inputs
    input  wire [N_FILT*BIAS_WD-1:0] biases_flat,

    // 58 results
    output wire [N_FILT*OUT_W-1:0] results_flat
);

    genvar f;
    generate
        for (f = 0; f < N_FILT; f = f + 1) begin : gen_pw_filt

            conv1x1_filter_unit #(
                .DATA_W (IN_W),
                .W_W    (W_W),
                .BIAS_WD(BIAS_WD),
                .OUT_W  (OUT_W)
            ) u_filt (
                .clk    (clk),
                .rst    (rst),
                .en     (en),
                .acc_clr(acc_clr),
                // shared 12-channel data bus
                .d0 (d0),  .d1 (d1),  .d2 (d2),  .d3 (d3),
                .d4 (d4),  .d5 (d5),  .d6 (d6),  .d7 (d7),
                .d8 (d8),  .d9 (d9),  .d10(d10), .d11(d11),
                // per-filter weight slice (12 channels)
                .w0 (weights_flat[(f*N_CHAN+ 0)*W_W +: W_W]),
                .w1 (weights_flat[(f*N_CHAN+ 1)*W_W +: W_W]),
                .w2 (weights_flat[(f*N_CHAN+ 2)*W_W +: W_W]),
                .w3 (weights_flat[(f*N_CHAN+ 3)*W_W +: W_W]),
                .w4 (weights_flat[(f*N_CHAN+ 4)*W_W +: W_W]),
                .w5 (weights_flat[(f*N_CHAN+ 5)*W_W +: W_W]),
                .w6 (weights_flat[(f*N_CHAN+ 6)*W_W +: W_W]),
                .w7 (weights_flat[(f*N_CHAN+ 7)*W_W +: W_W]),
                .w8 (weights_flat[(f*N_CHAN+ 8)*W_W +: W_W]),
                .w9 (weights_flat[(f*N_CHAN+ 9)*W_W +: W_W]),
                .w10(weights_flat[(f*N_CHAN+10)*W_W +: W_W]),
                .w11(weights_flat[(f*N_CHAN+11)*W_W +: W_W]),
                // per-filter bias and result
                .bias  (biases_flat[f*BIAS_WD +: BIAS_WD]),
                .result(results_flat[f*OUT_W  +: OUT_W])
            );

        end
    endgenerate

endmodule

`default_nettype wire
// =============================================================================
// END conv1x1_core.v
// =============================================================================
