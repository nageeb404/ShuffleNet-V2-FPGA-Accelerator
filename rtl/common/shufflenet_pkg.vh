// =============================================================================
// shufflenet_pkg.vh
// -----------------------------------------------------------------------------
// Central parameter file for the ShuffleNet V2 FPGA accelerator.
// Defines all architecture parameters: data widths, parallelism factors,
// memory dimensions, and Q6.8 fixed-point format constants.
// Project : RTL Implementation of Real-time ML Hardware Accelerator
// on FPGA - ShuffleNet V2
// Build Version : Chapter 5 baseline (uniform 15-bit Q6.8 datapath)
// Target FPGA : Xilinx Virtex-7 XC7VX690T-2FFG1761C (VC709)
// Target Clock : 100 MHz, single domain
// Reset Style : Global asynchronous reset
// =============================================================================

`ifndef SHUFFLENET_PKG_VH
`define SHUFFLENET_PKG_VH

// -----------------------------------------------------------------------------
// 1) Fixed-point format
// -----------------------------------------------------------------------------
// Format: 15-bit total, 1 sign + 6 integer + 8 fractional bits (Q6.8).
// All feature maps, weights, and photo pixels use this representation.
// -----------------------------------------------------------------------------
`define DATA_W 15 // total bits (sign + integer + fraction)
`define INT_W 6 // integer bits (excluding sign)
`define FRAC_W 8 // fractional bits
// Sign bit is implicit (DATA_W - INT_W - FRAC_W = 1)

// Saturation constants for the 15-bit signed Q6.8 format.
// Range: [-2^(DATA_W-1), 2^(DATA_W-1) - 1] = [-16384, 16383]
// (-2.0 ... +1.9921875 ... in Q6.8 decimal, since 16383/256 ~= 63.996,
// where the integer field including sign is interpreted as signed two's
// complement of the whole 15-bit word.)
`define DATA_MAX 15'sh3FFF // 15'b011_1111_1111_1111 = +16383
`define DATA_MIN 15'sh4000 // 15'b100_0000_0000_0000 = -16384 (signed)
 // (note: 15'sh4000 in 15-bit is the most-negative)

// -----------------------------------------------------------------------------
// 2) Multiplier output handling
// -----------------------------------------------------------------------------
// then the 7 LSBs are thrown away as quantization noise."
// So: mul -> 30 bits (Q12.16), drop 7 LSBs -> 23 bits (Q12.9) into the adder
// tree.
// -----------------------------------------------------------------------------
`define MUL_FULL_W 30 // 15 * 15 -> 30 bits
`define MUL_DROP_LSB 7 // bits discarded after multiply
`define MUL_OUT_W 23 // = MUL_FULL_W - MUL_DROP_LSB

// -----------------------------------------------------------------------------
// 3) Adder bit-growth rules
// -----------------------------------------------------------------------------
// the 2-input adder increments the number of bits by 1."
// log2(M), where M is the number of accumulations."
// -----------------------------------------------------------------------------
`define ADD3_GROW 2 // 3-input adder grows width by +2
`define ADD2_GROW 1 // 2-input adder grows width by +1

// -----------------------------------------------------------------------------
// 4) Parallelism factors [ Tables 5.1, 5.2, 5.3, 5.4, 5.9, 5.10, 5.11]
// -----------------------------------------------------------------------------
// Group 1: 3x3 Convolution [, T5.1]
`define G1_CONV_PAR_FILT 24 // parallelism in filters
`define G1_CONV_PAR_CHAN 3 // parallelism in channels
`define G1_CONV_PAR_WIN 3 // parallelism in window (window is 3x3=9)

// Group 1: Max Pooling [, T5.2]
`define G1_POOL_PAR_CHAN 24
`define G1_POOL_PAR_WIN 9 // full 3x3 window in parallel

// Group 2: 3x3 Depthwise Convolution [, T5.3]
`define G2_DW_PAR_FILT 58
`define G2_DW_PAR_WIN 9 // full 3x3 window in parallel

// Group 2: 1x1 Convolution [, T5.4]
`define G2_PW_PAR_FILT 58
`define G2_PW_PAR_CHAN 12 // reduced from 29: DSP fit for ZU19EG (1968 avail)

// Group 3: 1x1 Convolution [, T5.9]
`define G3_PW_PAR_FILT 16
`define G3_PW_PAR_CHAN 29

// Group 3: Average Pooling [, T5.10]
`define G3_AVG_PAR_CHAN 16

// Photo memory word width (Ch 6.2.6 optimization).
// Input pixels are in [0, 255/256] in Q6.8 format, so only 8 bits are
// significant (integer-side bits 14:8 are always 0). Store 8 bits per word;
// downstream data path uses PHOTO_W-wide ports (Ch 6.2.8).
`define PHOTO_W 8

// =============================================================================
// Ch 6.2.8 -- Per-layer feature map widths (Table 6.3)
// Reduces inter-layer data widths from the baseline DATA_W (15) to exact
// per-layer values determined by dynamic range analysis.
// photo: 8 bits, 5-bit fraction (= PHOTO_W, stored in BRAM)
// 3x3 conv output: 10 bits, 6-bit fraction
// Max-pooling output: 10 bits, 6-bit fraction (same as conv3x3 output)
// G2 DW/PW output: 12 bits, 8-bit fraction (shuffle group output)
// G3 1x1/avgpool/FC: 9 bits, 5-bit fraction
// =============================================================================
`define G1_FM_W 10 // Group 1 output: conv3x3 and maxpool output
`define G2_FM_W 12 // Group 2 output: DW conv and PW conv output
`define G3_FM_W 9 // Group 3 output: avgpool output, FC in/out

// =============================================================================
// Ch 6.2.5 -- Per-layer optimum weight widths (Table 6.2)
// Reduces BRAM weight storage from 1453 to 1155.5 BRAMs.
// Only G2 PW biases and FC biases are explicitly specified in Table 6.2;
// other biases retain the original DATA_W (15-bit) format.
// =============================================================================
`define G1_CONV_WW 12 // G1 3x3 conv weights (9-bit fraction)
`define G2_DW_WW 15 // G2 DW 3x3 weights (8-bit fraction, unchanged)
`define G2_PW_WW 11 // G2 PW 1x1 weights (9-bit fraction)
`define G2_BIAS_W 13 // G2 PW biases (9-bit fraction)
`define G3_PW_WW 9 // G3 1x1 weights (8-bit fraction)
`define FC_WW 9 // FC weights (8-bit fraction)
`define FC_BIAS_W 11 // FC biases (8-bit fraction)

// Group 3: conv1x1 pre-quantizer output width (Ch 6.2.7 + 6.2.5 + 6.2.8).
// With G3 PW filter using DATA_W=G2_FM_W(12) and W_W=G3_PW_WW(9):
// DROP_LSB = DATA_F(8) + W_F(8) - 9 = 7
// MAC_OUT = 12+9-7=14, TREE+8=22, ACC+4=26, BIAS+1=27
// (was 35 in the baseline; reduced by narrower MAC operands from 6.2.5+6.2.8)
`define G3_CONV_OUT_W 27

// Group 3: Fully Connected [, T5.11]
`define G3_FC_PAR_CHAN 32

// -----------------------------------------------------------------------------
// 5) Network dimensions [ Chapter 3, Sections 5.3]
// -----------------------------------------------------------------------------
// Input image:
// "input photo size expected by the model is 224*224*3 where 3 is number of
// channels as photos in RGB"
`define IMG_H 224
`define IMG_W 224
`define IMG_C 3

// Group 1 output / Maxpool memory feeding Group 2:
// "The input to Group 2 is a 56*56*24 feature map coming from the Maxpool
// memory."
`define G1_OUT_H 56
`define G1_OUT_W 56
`define G1_OUT_C 24

// 3x3 Conv intermediate output before maxpool:
// "convolution operation on the input image matrix of size 224x224x3 with
// 24 filters each of size 3x3x3 that produce an output of size 112x112x24"
`define G1_CONV_OUT_H 112
`define G1_CONV_OUT_W 112
`define G1_CONV_OUT_C 24

// Group 2 output feeding Group 3 via Extra memory:
// "till it reaches 7*7*464 at the Group 2 output which is stored in the
// Extra memory."
`define G2_OUT_H 7
`define G2_OUT_W 7
`define G2_OUT_C 464

// Group 3 1x1 conv:
// "we have a 7*7*464 input feature map and 1024 filters and it produces a
// 7*7*1024 output feature map."
`define G3_PW_OUT_H 7
`define G3_PW_OUT_W 7
`define G3_PW_OUT_C 1024

// Group 3 FC:
// "the flattened output of the average pooling layer (1024 pixels) ...
// a layer of 1000 neurons"
`define G3_FC_IN 1024
`define G3_FC_OUT 1000

// Group 2 stage widths:
// "we have 4 possible widths of the feature maps in group, so FIFO must
// support all the 4 widths (56, 28, 14, 7)"
`define G2_W_MAX 56
`define G2_W_S2 28
`define G2_W_S3 14
`define G2_W_S4 7

// Group 2 channel counts per stage:
// "Each filter has multiple channels that can be 24, 58, 116 or 232
// channels depending on the layer"
`define G2_C_INIT 24 // first stride 2 block input
`define G2_C_S2 58
`define G2_C_S3 116
`define G2_C_S4 232

// -----------------------------------------------------------------------------
// 6) FIFO sizing [, 5.4.6]
// -----------------------------------------------------------------------------
// Generic rule: FIFO_SIZE = 2*W + 3
// Group 1 3x3 Conv FIFO depth:
// "we use 3 FIFOs of size (2*226+3) as the size of the input photo is 224
// and we have 2 bits for the padding." -> 226 includes padding columns
`define G1_CONV_FIFO_DEPTH 455 // = 2*226 + 3

// Group 1 Maxpool FIFO depth:
// "we use a 24 FIFOs of size (2*114+3) the store the output of the 3x3
// conv block" -> 114 includes padding columns of the 112x112 maxpool input
`define G1_POOL_FIFO_DEPTH 231 // = 2*114 + 3

// Group 2 one-fits-all FIFO depth:
// "The size of the FIFO register will be (2*Wmax + 3) = 119 registers"
// Wmax = 58 (padded width: 56 feature map cols + 1 col zero-pad each side)
`define G2_FIFO_DEPTH 119 // = 2*58 + 3 (58 = 56 + 2 padding cols)

// -----------------------------------------------------------------------------
// 7) Address widths (derived for memory IO, computed via $clog2 in modules)
// -----------------------------------------------------------------------------
// Photo memory: 224*224 = 50176 words per channel instance
`define PHOTO_MEM_DEPTH 50176 // per channel instance, per ping-pong half
`define PHOTO_MEM_AW 16 // ceil(log2(50176)) = 16

// Maxpool memory: 56*56 = 3136 words per channel instance
`define MAXPOOL_MEM_DEPTH 3136
`define MAXPOOL_MEM_AW 12 // ceil(log2(3136)) = 12

// =============================================================================
// END shufflenet_pkg.vh
// =============================================================================
`endif
