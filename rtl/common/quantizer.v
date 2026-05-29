// =============================================================================
// quantizer.v - Saturating quantizer to the 15-bit Q6.8 datapath format
// -----------------------------------------------------------------------------
//
// Sec 5.4.1.1 (3by3 DW Conv core, "two-sided" quantizer):
// "a quantizer is placed at the end of each computation core to compare
// the output of convolution to the maximum and minimum possible values
// of the 15-bit fixed point output. The quantizer consists of two
// multiplexers, one for maximum checking and the other for minimum
// checking. Firstly, we check for the minimum value using a comparator
// and if the number is larger than the minimum value, the number is
// passed as it is. Otherwise, the minimum value is passed (saturation
// case to avoid overflow). Secondly, we check for the maximum value
// using a simple logic circuit instead of a comparator and if the number
// is smaller than the maximum value, the number is passed as it is.
// Otherwise, the maximum value is passed."
//
// Sec 5.4.1.2 (1by1 Conv core, "one-sided / post-ReLU" quantizer):
// "The quantizer consists of a multiplexer and a simple logic for maximum
// checking. We check for the maximum value using a simple logic circuit
// instead of a comparator to save power and area. ... Checking for the
// minimum case is not required here as the ReLU output will never be a
// negative value."
//
// Sec 5.4.1.2 ("simple logic circuit" detail):
// The "simple logic circuit" for max checking exploits the fact that the
// incoming value is wider than DATA_W and is in two's complement. The
// value EXCEEDS +DATA_MAX (i.e. needs saturating to MAX) iff the value is
// non-negative AND any of the bits above bit (DATA_W-2) are set. For a
// post-ReLU input we only need: any bit above bit (DATA_W-2) being set
// means saturate. (See FA-style logic; we OR all "above-range" bits.)
//
// Modes (selected via the parameter HAS_RELU):
// HAS_RELU = 0 -> two-sided quantizer (min check + max check), used after
// cores whose output can be negative (e.g. 3by3 conv,
// 3by3 DW conv, average-pooling, FC).
// HAS_RELU = 1 -> one-sided quantizer (max check only), used after cores
// that already applied ReLU (1by1 conv in both Group 2
// and Group 3).
//
// Bit-format conventions:
// - Input : signed two's complement, IN_W bits, fractional length matches
// the rest of the datapath via the upstream pipeline. The 7-LSB
// quantization-noise drop after the multiplier (Sec 5.4.1.1) is
// done in the parent core BEFORE entering the adder tree, NOT
// here. This module receives an already 7-LSB-dropped value
// that has only grown via additions and accumulation.
// - Output : signed two's complement, DATA_W bits, in Q6.8 format
// (see shufflenet_pkg.vh).
//
// Notes:
// - The +DATA_MAX of a 15-bit signed format is +16383 = 15'h3FFF.
// - The -DATA_MIN of a 15-bit signed format is -16384 = 15'h4000 (when
// interpreted as a signed 15-bit number, this is the MOST negative).
// - This module is purely combinational. Pipeline registers, if needed,
// are inserted by the parent.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module quantizer #(
    parameter integer IN_W      = 27,                      // input width (bits)
    parameter integer OUT_W     = `DATA_W,                 // = 15
    parameter integer HAS_RELU  = 0                        // 1 = post-ReLU
) (
    input  wire signed [IN_W-1:0]  in_data,
    output wire signed [OUT_W-1:0] out_data
);

    // -------------------------------------------------------------------------
    // Maximum-check "simple logic" (per Sec 5.4.1.2)
    // -------------------------------------------------------------------------
    // Define:
    // - low_bits : the OUT_W-1 LSBs of in_data (these are the bits that
    // fit into the magnitude portion of the OUT_W-wide signed
    // representation, i.e. bits [OUT_W-2:0]).
    // - high_bits: the IN_W - (OUT_W-1) MSBs of in_data
    // (these are bits [IN_W-1:OUT_W-1]).
    //
    // For a non-negative input, the value fits in OUT_W bits iff all the
    // high_bits are zero (because a non-negative OUT_W-bit signed value
    // has its sign bit = 0 and uses only bits [OUT_W-2:0]).
    // If any high_bit is 1 (and the value is non-negative), the value is too
    // large -> saturate to +DATA_MAX.

    // Number of "above range" high bits.
    localparam integer HIGH_W = IN_W - (OUT_W - 1);  // e.g. 27 - 14 = 13
    wire [HIGH_W-1:0] high_bits = in_data[IN_W-1 : OUT_W-1];

    // For non-negative input, "any high_bit is 1" indicates overflow above MAX.
    wire any_high_set = |high_bits;

    // -------------------------------------------------------------------------
    // Minimum-check (per Sec 5.4.1.1) - only when HAS_RELU == 0
    // -------------------------------------------------------------------------
    // Use a real signed comparator:
    // "we check for the minimum value using a comparator"
    //
    // We copy the macro values into local signed constants so we can compare
    // them directly with the wider signed input. Verilog automatically
    // sign-extends the narrower operand in a signed comparison, so no explicit
    // sign-extension assign is needed.
    localparam signed [OUT_W-1:0] LP_DATA_MAX = `DATA_MAX;
    localparam signed [OUT_W-1:0] LP_DATA_MIN = `DATA_MIN;

    wire below_min = (in_data < $signed(LP_DATA_MIN));
    wire is_neg    = in_data[IN_W-1];   // sign bit of input

    // -------------------------------------------------------------------------
    // Two saturation paths
    // -------------------------------------------------------------------------
    // Mode A: HAS_RELU == 1 (post-ReLU, input is guaranteed >= 0)
    // - Only need max check. If any high_bit is set -> saturate to MAX,
    // else pass low OUT_W bits (with leading zero implicitly because
    // in_data is non-negative).
    //
    // Mode B: HAS_RELU == 0 (general signed)
    // - If in_data is non-negative AND any high_bit set -> +MAX
    // - Else if in_data < min_ext -> -MIN
    // - Else -> truncate to OUT_W

    // Truncated value: keep the sign bit + the (OUT_W-1) LSBs.
    // (Accumulation/adders only grow the integer side; the
    // fractional length stays at FRAC_W along the datapath, so truncating from
    // the top -- i.e. dropping the now-redundant high bits -- preserves the
    // Q6.8 format.)
    wire signed [OUT_W-1:0] trunc_val =
        { in_data[IN_W-1], in_data[OUT_W-2:0] };

    reg signed [OUT_W-1:0] q_out;

    always @(*) begin
        if (HAS_RELU) begin
            // Post-ReLU: value cannot be negative (parent forces it >= 0).
            // Saturate above MAX only.
            if (any_high_set)
                q_out = LP_DATA_MAX;
            else
                q_out = in_data[OUT_W-1:0];   // safe truncation (top bit = 0)
        end else begin
            // General signed quantization with saturation.
            if (!is_neg && any_high_set)
                q_out = LP_DATA_MAX;
            else if (is_neg && below_min)
                q_out = LP_DATA_MIN;
            else
                q_out = trunc_val;
        end
    end

    assign out_data = q_out;

endmodule

`default_nettype wire
// =============================================================================
// END quantizer.v
// =============================================================================
