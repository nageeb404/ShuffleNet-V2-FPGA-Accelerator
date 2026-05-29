// =============================================================================
// fifo_3x3.v -- Shift-register FIFO with zero-padding MUX
// -----------------------------------------------------------------------------
// "FIFOs" / Figure 5.10 / Figure 5.13
//
// "We use FIFO with the size of (2W+3), where W is feature map number of
// columns, the FIFO is simply a shift register and we read the data from
// the feature map 1 by 1 and store it in the FIFO." -- Sec 5.3.3
//
// "By adding a mux in the input of the FIFO to choose from load a data from
// the memory or to load a zero as shown in Figure 5.13." -- Sec 5.3.3
//
// For Group 1 3x3 convolution (Sec 5.3.3):
// "we use 3 FIFOs of size (2*226+3) as the size of the input photo is 224
// and we have 2 bits for the padding."
// -> DEPTH = 2*226+3 = 455 (= G1_CONV_FIFO_DEPTH in shufflenet_pkg.vh)
// -> TAP_STRIDE = (DEPTH-3)/2 = 226 = padded image width
//
// For Group 1 maxpool input (Module 1.6, fifo_pool.v, same structure):
// "we use a 24 FIFOs of size (2*114+3)"
// -> DEPTH = 231 (= G1_POOL_FIFO_DEPTH), TAP_STRIDE = 114
//
// Tap positions (Figure 5.10 / Figure 5.13):
// tap0 = shift_reg[0] -- newest element (current row pixel)
// tap1 = shift_reg[TAP_STRIDE] -- one row back
// tap2 = shift_reg[2*TAP_STRIDE] -- two rows back
// The three taps provide the 3-row window column for one channel.
//
// Control signals:
// shift_and_load : 1 = shift the register and load new value at front
// padding_sel : 1 = load zero (zero-padding), 0 = load data_in
// rst : async active-high, clears all registers to 0
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module fifo_3x3 #(
    parameter integer DATA_W     = `DATA_W,               // 15
    parameter integer DEPTH      = `G1_CONV_FIFO_DEPTH,   // 455
    parameter integer TAP_STRIDE = (DEPTH - 3) / 2        // 226
) (
    input  wire        clk,
    input  wire        rst,            // async active-high, clears to 0
    input  wire        shift_and_load, // shift enable
    input  wire        padding_sel,    // 1=insert zero, 0=use data_in
    input  wire signed [DATA_W-1:0] data_in,
    // 3 row taps ( / Fig 5.10)
    output wire signed [DATA_W-1:0] tap0, // newest (current row)
    output wire signed [DATA_W-1:0] tap1, // one row back
    output wire signed [DATA_W-1:0] tap2  // two rows back
);

    // -----------------------------------------------------------------------
    // Shift register array
    // -----------------------------------------------------------------------
    // Index 0 holds the newest value (most recently shifted in).
    // Index DEPTH-1 holds the oldest value.
    // All 15-bit elements, signed Q6.8.
    reg signed [DATA_W-1:0] shift_reg [0:DEPTH-1];

    // -----------------------------------------------------------------------
    // Input MUX ( / Fig 5.13)
    // "adding a mux in the input of the FIFO to choose from load a data
    // from the memory or to load a zero"
    // -----------------------------------------------------------------------
    wire signed [DATA_W-1:0] din_mux;
    assign din_mux = padding_sel ? {DATA_W{1'b0}} : data_in;

    // -----------------------------------------------------------------------
    // Shift operation (: "the FIFO is simply a shift register")
    // On each rising edge with shift_and_load=1:
    // shift_reg[DEPTH-1] <- shift_reg[DEPTH-2] <- ... <- shift_reg[0] <- din_mux
    // On rst: all elements cleared to 0.
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin : sr_proc
        integer k;
        if (rst) begin
            for (k = 0; k < DEPTH; k = k + 1)
                shift_reg[k] <= {DATA_W{1'b0}};
        end else if (shift_and_load) begin
            // Shift existing contents toward the tail
            for (k = DEPTH-1; k > 0; k = k - 1)
                shift_reg[k] <= shift_reg[k-1];
            // Load new value at head
            shift_reg[0] <= din_mux;
        end
    end

    // -----------------------------------------------------------------------
    // Output taps ( / Fig 5.10 / Fig 5.13)
    // TAP_STRIDE = (DEPTH-3)/2 = 226 for 3x3 conv FIFO
    // 2*TAP_STRIDE = DEPTH-3 = 452 for 3x3 conv FIFO
    // -----------------------------------------------------------------------
    assign tap0 = shift_reg[0];
    assign tap1 = shift_reg[TAP_STRIDE];
    assign tap2 = shift_reg[2 * TAP_STRIDE];

endmodule

`default_nettype wire
// =============================================================================
// END fifo_3x3.v
// =============================================================================
