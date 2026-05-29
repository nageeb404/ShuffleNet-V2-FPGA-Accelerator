// =============================================================================
// dw_conv3x3_core.v -- 58-parallel-filter depthwise 3x3 convolution core
// -----------------------------------------------------------------------------
// "3by3 DW Convolution" / Table 5.3
//
// "Since each filter has one channel consisting of 9 elements which is a small
// number, then convolution is performed to the whole window in parallel. And
// to speed up the convolution operation, 58 filters are executed in parallel
// for a window of parameters." -- Sec 5.4.1.1
//
// Table 5.3 (Parallelism in the 3x3 DW Convolution):
// Parallelism in Filters : 58 (= G2_DW_PAR_FILT)
// Parallelism in Channels: NA (depthwise -- each filter has 1 channel)
// Parallelism in Window : 9 (full 3x3 window in parallel)
//
// KEY DIFFERENCE FROM conv3x3_core (Group 1):
// In Group 1, all 24 filters share the same 9 data inputs (3-channel conv).
// In depthwise conv, each filter operates on its OWN channel, so each of
// the 58 filters receives different 9-tap data from its channel's FIFO.
//
// Ch 6.2.5 + 6.2.8: per-layer widths applied.
// data inputs : 10 bits (IN_W = G1_FM_W, maxpool output)
// weight inputs: 15 bits (W_W = G2_DW_WW, unchanged)
// bias inputs : 15 bits (BIAS_WD = DATA_W, original format)
// results : 12 bits (OUT_W = G2_FM_W)
//
// Port packing convention:
// data_flat : [N_FILT*9*IN_W-1 : 0]
// Filter f, tap t --> data_flat[(f*9 + t)*IN_W +: IN_W]
// weights_flat : [N_FILT*9*W_W-1 : 0]
// Filter f, tap t --> weights_flat[(f*9 + t)*W_W +: W_W]
// biases_flat : [N_FILT*BIAS_WD-1 : 0]
// Filter f --> biases_flat[f*BIAS_WD +: BIAS_WD]
// results_flat : [N_FILT*OUT_W-1 : 0]
// Filter f --> results_flat[f*OUT_W +: OUT_W]
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module dw_conv3x3_core #(
    parameter integer N_FILT  = `G2_DW_PAR_FILT, // 58
    parameter integer IN_W    = `G1_FM_W,          // 10 (Ch 6.2.8: maxpool output)
    parameter integer W_W     = `G2_DW_WW,         // 15 (Ch 6.2.5: DW weight width)
    parameter integer BIAS_WD = `DATA_W,            // 15 (bias, original format)
    parameter integer OUT_W   = `G2_FM_W            // 12 (Ch 6.2.8: DW conv output)
) (
    input  wire clk,
    input  wire rst,
    input  wire en,

    // 58*9 data inputs: each filter sees 9 taps from its own channel.
    // Filter f, tap t: data_flat[(f*9+t)*IN_W +: IN_W]
    input  wire [N_FILT*9*IN_W-1:0] data_flat,

    // 58*9 weight inputs: filter f, tap t: weights_flat[(f*9+t)*W_W +: W_W]
    input  wire [N_FILT*9*W_W-1:0] weights_flat,

    // 58 bias inputs: filter f: biases_flat[f*BIAS_WD +: BIAS_WD]
    input  wire [N_FILT*BIAS_WD-1:0] biases_flat,

    // 58 results: filter f: results_flat[f*OUT_W +: OUT_W]
    output wire [N_FILT*OUT_W-1:0] results_flat
);

    genvar f;
    generate
        for (f = 0; f < N_FILT; f = f + 1) begin : gen_dw_filt

            dw_conv3x3_filter_unit #(
                .DATA_W (IN_W),
                .W_W    (W_W),
                .BIAS_WD(BIAS_WD),
                .OUT_W  (OUT_W)
            ) u_filt (
                .clk (clk),
                .rst (rst),
                .en  (en),
                // per-filter data slice (9 taps from filter f's own channel)
                .d0(data_flat[(f*9+0)*IN_W +: IN_W]),
                .d1(data_flat[(f*9+1)*IN_W +: IN_W]),
                .d2(data_flat[(f*9+2)*IN_W +: IN_W]),
                .d3(data_flat[(f*9+3)*IN_W +: IN_W]),
                .d4(data_flat[(f*9+4)*IN_W +: IN_W]),
                .d5(data_flat[(f*9+5)*IN_W +: IN_W]),
                .d6(data_flat[(f*9+6)*IN_W +: IN_W]),
                .d7(data_flat[(f*9+7)*IN_W +: IN_W]),
                .d8(data_flat[(f*9+8)*IN_W +: IN_W]),
                // per-filter weight slice
                .w0(weights_flat[(f*9+0)*W_W +: W_W]),
                .w1(weights_flat[(f*9+1)*W_W +: W_W]),
                .w2(weights_flat[(f*9+2)*W_W +: W_W]),
                .w3(weights_flat[(f*9+3)*W_W +: W_W]),
                .w4(weights_flat[(f*9+4)*W_W +: W_W]),
                .w5(weights_flat[(f*9+5)*W_W +: W_W]),
                .w6(weights_flat[(f*9+6)*W_W +: W_W]),
                .w7(weights_flat[(f*9+7)*W_W +: W_W]),
                .w8(weights_flat[(f*9+8)*W_W +: W_W]),
                // per-filter bias
                .bias  (biases_flat[f*BIAS_WD +: BIAS_WD]),
                // per-filter result
                .result(results_flat[f*OUT_W  +: OUT_W])
            );

        end
    endgenerate

endmodule

`default_nettype wire
// =============================================================================
// END dw_conv3x3_core.v
// =============================================================================
