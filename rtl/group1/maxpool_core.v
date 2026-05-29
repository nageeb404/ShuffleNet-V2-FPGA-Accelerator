// =============================================================================
// maxpool_core.v -- 24-channel x 9-window max-of-9 pooling core
// -----------------------------------------------------------------------------
// "Max Pooling Core" / Figure 5.9 / Table 5.2
//
// "This core takes 3x3 window from the output of the 3x3 convolution core
// and outputs the maximum of them. Using a tree of comparators. The sizes
// don't change along the tree because comparing does not increase the size.
// We break the critical path with registers after the second stage of
// comparing as shown in Figure 5.9." -- Sec 5.3.2.2
//
// Table 5.2 (Parallelism in the Maxpooling core):
// Parallelism in Filters : NA
// Parallelism in Channels: 24 (= G1_POOL_PAR_CHAN)
// Parallelism in window : 9 (= G1_POOL_PAR_WIN)
//
// Datapath: no bit growth -- all stages stay at DATA_W (15 bits).
// Inputs always non-negative (post-ReLU from conv3x3_core).
// No quantizer needed.
//
// Pipeline structure per channel (Fig 5.9):
// Stage 1 (comb): 4 pairwise comparisons: max(0,1) max(2,3) max(4,5) max(6,7)
// Stage 2 (comb): 2 pairwise comparisons: max(01,23) max(45,67); in[8] bypasses
// Pipeline register: captures the 3 stage-2 results [one cycle latency]
// Stage 3 (comb): max(r01234567, r8) via 2 comparisons -> channel result
//
// Port packing (flat buses, channel c, window tap t):
// data_flat : [(c*9 + t)*DATA_W +: DATA_W] (24*9*DATA_W bits total)
// results : [c*DATA_W +: DATA_W] (24*DATA_W bits total)
//
// Latency: 1 clock cycle (pipeline register in stage 2->3 boundary).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Ch 6.2.8: DATA_W changed from DATA_W (15) to G1_FM_W (10).
// Maxpool inputs are post-ReLU conv3x3 outputs, now 10-bit.
// No quantizer needed -- comparators keep same bit-width.
module maxpool_core #(
    parameter integer N_CHAN  = `G1_POOL_PAR_CHAN, // 24
    parameter integer N_WIN   = `G1_POOL_PAR_WIN,  // 9
    parameter integer DATA_W  = `G1_FM_W           // 10 (Ch 6.2.8)
) (
    input  wire        clk,
    input  wire        rst,   // async active-high
    input  wire        en,    // pipeline register enable

    // 24*9 data inputs from maxpool FIFOs (Q6.8).
    // Channel c, window tap t: data_flat[(c*9 + t)*DATA_W +: DATA_W]
    input  wire [N_CHAN*N_WIN*DATA_W-1:0] data_flat,

    // 24 max results (Q6.8, same width as inputs -- no quantizer).
    // Channel c: results_flat[c*DATA_W +: DATA_W]
    output wire [N_CHAN*DATA_W-1:0] results_flat
);

    // -----------------------------------------------------------------------
    // Generate one max-of-9 comparator tree per channel.
    // -----------------------------------------------------------------------
    genvar c;
    generate
        for (c = 0; c < N_CHAN; c = c + 1) begin : gen_chan

            // ---- Extract 9 signed inputs for this channel ----
            wire signed [DATA_W-1:0] d0, d1, d2, d3, d4, d5, d6, d7, d8;
            assign d0 = $signed(data_flat[(c*9+0)*DATA_W +: DATA_W]);
            assign d1 = $signed(data_flat[(c*9+1)*DATA_W +: DATA_W]);
            assign d2 = $signed(data_flat[(c*9+2)*DATA_W +: DATA_W]);
            assign d3 = $signed(data_flat[(c*9+3)*DATA_W +: DATA_W]);
            assign d4 = $signed(data_flat[(c*9+4)*DATA_W +: DATA_W]);
            assign d5 = $signed(data_flat[(c*9+5)*DATA_W +: DATA_W]);
            assign d6 = $signed(data_flat[(c*9+6)*DATA_W +: DATA_W]);
            assign d7 = $signed(data_flat[(c*9+7)*DATA_W +: DATA_W]);
            assign d8 = $signed(data_flat[(c*9+8)*DATA_W +: DATA_W]);

            // ---- Stage 1 (comb): 4 pairwise comparisons ----
            wire signed [DATA_W-1:0] m01 = (d0 > d1) ? d0 : d1;
            wire signed [DATA_W-1:0] m23 = (d2 > d3) ? d2 : d3;
            wire signed [DATA_W-1:0] m45 = (d4 > d5) ? d4 : d5;
            wire signed [DATA_W-1:0] m67 = (d6 > d7) ? d6 : d7;
            // d8 bypasses stage 1

            // ---- Stage 2 (comb): 2 pairwise comparisons ----
            wire signed [DATA_W-1:0] m0123 = (m01 > m23) ? m01 : m23;
            wire signed [DATA_W-1:0] m4567 = (m45 > m67) ? m45 : m67;
            // d8 still bypasses

            // ---- Pipeline register ( / Fig 5.9) ----
            // Captures the 3 stage-2 candidates after the second stage of
            // comparing to break the critical path.
            reg signed [DATA_W-1:0] r0123, r4567, r8;
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    r0123 <= {DATA_W{1'b0}};
                    r4567 <= {DATA_W{1'b0}};
                    r8    <= {DATA_W{1'b0}};
                end else if (en) begin
                    r0123 <= m0123;
                    r4567 <= m4567;
                    r8    <= d8;
                end
            end

            // ---- Stage 3 (comb): final max of the 3 registered values ----
            wire signed [DATA_W-1:0] m01234567 = (r0123 > r4567) ? r0123 : r4567;
            wire signed [DATA_W-1:0] chan_max  = (m01234567 > r8)  ? m01234567 : r8;

            // ---- Drive output slice ----
            assign results_flat[c*DATA_W +: DATA_W] = chan_max;

        end // for c
    endgenerate

endmodule

`default_nettype wire
// =============================================================================
// END maxpool_core.v
// =============================================================================
