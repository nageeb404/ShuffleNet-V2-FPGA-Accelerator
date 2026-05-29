/*
 * shufflenet_hls.cpp -- ShuffleNet V2 x1.0 Vitis HLS Implementation
 *
 * Thesis Chapter 7: High Level Synthesis (HLS)
 *
 * Implementation follows the "Pipeline Model" (Sec 7.4.1) as the
 * starting point: #pragma HLS PIPELINE in the innermost loop of
 * every conv/pool function gives a 2.9x speedup over the baseline.
 *
 * Full PW->DW->PW architecture (matches the Python software model
 * which gives ~71% Top-1 accuracy on ImageNet validation).
 *
 * Data type: short int (Q6.8), accumulators: long long.
 * Weights: included from hls/weights/ header files (decimal integers,
 * Sec 7.3.2.1: only decimal format produces correct results with
 * ap_fixed/short int arrays).
 *
 * Memory layout: channel-major [C][H_PAD][W_PAD] flattened to 1D.
 * Padding convention: each function writes zeros to the output border
 * before writing data values, so the next function sees a pre-padded
 * input.  (Thesis Sec 7.2.3.2)
 */

#include "shufflenet_hls.h"
#include "../weights/conv1_weights.h"
#include "../weights/block_s2_0.h"
#include "../weights/block_s2_1.h"
#include "../weights/block_s2_2.h"
#include "../weights/block_s2_3.h"
#include "../weights/block_s3_0.h"
#include "../weights/block_s3_1.h"
#include "../weights/block_s3_2.h"
#include "../weights/block_s3_3.h"
#include "../weights/block_s3_4.h"
#include "../weights/block_s3_5.h"
#include "../weights/block_s3_6.h"
#include "../weights/block_s3_7.h"
#include "../weights/block_s4_0.h"
#include "../weights/block_s4_1.h"
#include "../weights/block_s4_2.h"
#include "../weights/block_s4_3.h"
#include "../weights/conv5_weights.h"
#include "../weights/fc_weights.h"

/* ================================================================== */
/*  Helper: zero-fill a memory region                                  */
/* ================================================================== */
static void zero_mem(data_t* mem, int size)
{
    for (int i = 0; i < size; i++) {
#pragma HLS PIPELINE
        mem[i] = 0;
    }
}

/* ================================================================== */
/*  GROUP 1: 3x3 Convolution + ReLU                                    */
/*                                                                      */
/*  Reads:  sm_in  [CONV1_IN_C][CONV1_IN_H_P][CONV1_IN_W_P]           */
/*          (photo stored with 1-pixel zero border = 226x226x3)        */
/*  Writes: sm_out [CONV1_OUT_C][CONV1_OUT_H_P][CONV1_OUT_W_P]        */
/*          (conv output 112x112x24 with 1-pixel zero border at rows   */
/*           and cols 0 and 113, ready for maxpool to read as 114x114) */
/*  Kernel: 3x3, stride=2, padding=1 (pre-padded in sm_in)            */
/*  Weights: conv1_w [24,3,3,3], conv1_b [24]                          */
/* ================================================================== */
static void conv3x3_group1(data_t sm_in[], data_t sm_out[])
{
    /* Padding the output (Sec 7.2.3.2): zero border so maxpool
       reads a properly-padded 114x114 input */
    zero_mem(sm_out, CONV1_OUT_C * CONV1_OUT_H_P * CONV1_OUT_W_P);

    /* Nested loops: filters, output rows, output cols (Sec 7.2.3.1, Fig 7.9) */
    for (int oc = 0; oc < CONV1_OUT_C; oc++) {
        for (int oh = 0; oh < CONV1_OUT_H; oh++) {
            for (int ow = 0; ow < CONV1_OUT_W; ow++) {
                acc_t acc = 0;
                /* 3-D filter: input_ch * kernel_row * kernel_col */
                for (int ic = 0; ic < CONV1_IN_C; ic++) {
                    for (int kh = 0; kh < 3; kh++) {
                        for (int kw = 0; kw < 3; kw++) {
#pragma HLS PIPELINE
                            /* stride=2, input is pre-padded so ih starts at 0 */
                            int ih = oh * 2 + kh;
                            int iw = ow * 2 + kw;
                            acc += (acc_t)sm_in[IDX(ic, ih, iw,
                                                    CONV1_IN_H_P, CONV1_IN_W_P)]
                                 * (acc_t)conv1_w[oc * (CONV1_IN_C * 9)
                                                  + ic * 9 + kh * 3 + kw];
                        }
                    }
                }
                /* Bias, quantise, ReLU -- write to inner (non-border) position */
                data_t val = q_relu(q_norm(acc, conv1_b[oc]));
                sm_out[IDX(oc, oh + 1, ow + 1,
                           CONV1_OUT_H_P, CONV1_OUT_W_P)] = val;
            }
        }
    }
}

/* ================================================================== */
/*  GROUP 1: 3x3 Max Pooling                                           */
/*                                                                      */
/*  Reads:  sm_in  [CONV1_OUT_C][CONV1_OUT_H_P][CONV1_OUT_W_P]        */
/*  Writes: sm_out [CONV1_OUT_C][MP_OUT_H_P][MP_OUT_W_P]              */
/*          (56x56x24 with 1-pixel zero border = 58x58x24)             */
/*  Kernel: 3x3, stride=2, padding=1 (pre-padded in sm_in)            */
/* ================================================================== */
static void max_pool_group1(data_t sm_in[], data_t sm_out[])
{
    zero_mem(sm_out, CONV1_OUT_C * MP_OUT_H_P * MP_OUT_W_P);

    for (int c = 0; c < CONV1_OUT_C; c++) {
        for (int oh = 0; oh < MP_OUT_H; oh++) {
            for (int ow = 0; ow < MP_OUT_W; ow++) {
                data_t mx = (data_t)-16384;
                for (int kh = 0; kh < 3; kh++) {
                    for (int kw = 0; kw < 3; kw++) {
#pragma HLS PIPELINE
                        int ih = oh * 2 + kh;   /* stride=2, pre-padded */
                        int iw = ow * 2 + kw;
                        data_t v = sm_in[IDX(c, ih, iw,
                                             CONV1_OUT_H_P, CONV1_OUT_W_P)];
                        if (v > mx) mx = v;
                    }
                }
                sm_out[IDX(c, oh + 1, ow + 1, MP_OUT_H_P, MP_OUT_W_P)] = mx;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 1x1 Pointwise Convolution + ReLU                          */
/*                                                                      */
/*  Generic 1x1 conv. Input/output are flat arrays (no padding needed  */
/*  for 1x1 conv).  Used for both branch PW layers and conv5.          */
/*                                                                      */
/*  in_flat  [in_C][H][W]  -- channel-major, NO padding                */
/*  out_flat [out_C][H][W] -- channel-major, NO padding                */
/*  w        [out_C * in_C]                                            */
/*  b        [out_C]                                                   */
/*  relu: 1 = apply ReLU, 0 = skip (not needed in this architecture)  */
/* ================================================================== */
static void conv1x1(
    const data_t* in_flat, data_t* out_flat,
    int in_C, int out_C, int H, int W,
    const data_t* w, const data_t* b, int relu)
{
    for (int oc = 0; oc < out_C; oc++) {
        for (int oh = 0; oh < H; oh++) {
            for (int ow = 0; ow < W; ow++) {
                acc_t acc = 0;
                for (int ic = 0; ic < in_C; ic++) {
#pragma HLS PIPELINE
                    acc += (acc_t)in_flat[ic * H * W + oh * W + ow]
                         * (acc_t)w[oc * in_C + ic];
                }
                data_t val = q_norm(acc, b[oc]);
                if (relu && val < 0) val = 0;
                out_flat[oc * H * W + oh * W + ow] = val;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 3x3 Depthwise Convolution (no ReLU, two-sided quantiser)  */
/*                                                                      */
/*  in_flat  [C][H_P][W_P] -- channel-major, WITH 1-pixel zero border */
/*  out_flat [C][H_out][W_out] -- channel-major, NO padding            */
/*  w        [C * 9]   (depthwise: one 3x3 kernel per channel)        */
/*  b        [C]                                                        */
/*  stride: 1 or 2                                                     */
/*  H_P, W_P: PADDED input dimensions (real input = H_P-2, W_P-2)     */
/* ================================================================== */
static void dw_conv3x3(
    const data_t* in_flat, data_t* out_flat,
    int C, int H_P, int W_P, int H_out, int W_out, int stride,
    const data_t* w, const data_t* b)
{
    for (int c = 0; c < C; c++) {
        for (int oh = 0; oh < H_out; oh++) {
            for (int ow = 0; ow < W_out; ow++) {
                acc_t acc = 0;
                for (int kh = 0; kh < 3; kh++) {
                    for (int kw = 0; kw < 3; kw++) {
#pragma HLS PIPELINE
                        int ih = oh * stride + kh;
                        int iw = ow * stride + kw;
                        acc += (acc_t)in_flat[c * H_P * W_P + ih * W_P + iw]
                             * (acc_t)w[c * 9 + kh * 3 + kw];
                    }
                }
                /* Two-sided quantiser: NO ReLU for DW (Thesis Sec 5.4.1.1) */
                out_flat[c * H_out * W_out + oh * W_out + ow] =
                    q_sat((acc >> 8) + (acc_t)b[c]);
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: Channel Shuffle                                            */
/*                                                                      */
/*  Implements the ShuffleNet V2 channel shuffle:                      */
/*    reshape(G=2, C/G) -> transpose(0,1) -> reshape(C)               */
/*  Equivalent to interleaving two halves:                             */
/*    out[2k]   = in[k]         (branch_a)                            */
/*    out[2k+1] = in[k + C/2]  (branch_b)                            */
/*  Operates in-place on a flat [C][H][W] array.                      */
/* ================================================================== */
static void channel_shuffle(data_t* fm, int C, int H, int W)
{
    int half = C / 2;
    int hw   = H * W;
    /* Max size: stage-2 with 116 channels @ 28x28 = 90,944 elements */
    static data_t tmp[116 * 28 * 28];
    int sz = C * hw;
    for (int i = 0; i < sz; i++) tmp[i] = fm[i];

    for (int ch = 0; ch < C; ch++) {
        /* out_ch = ch; source: (ch&1)*half + (ch>>1) */
        int src = (ch & 1) * half + (ch >> 1);
        for (int i = 0; i < hw; i++) {
#pragma HLS PIPELINE
            fm[ch * hw + i] = tmp[src * hw + i];
        }
    }
}

/* ================================================================== */
/*  SHUFFLE BLOCK -- STRIDE 1                                          */
/*                                                                      */
/*  Input:  sm_in  [in_C][H_P][W_P]  (padded, H=out_H, W=out_W)      */
/*  Output: sm_out [in_C][H_P][W_P]  (padded same size)               */
/*                                                                      */
/*  Thesis Sec 7.2.3: branch_b: PW1 -> DW3x3 -> PW2                  */
/*  branch_a: passthrough (Passing Unit).                              */
/*                                                                      */
/*  Local intermediates (on stack / synthesised as internal BRAM):    */
/*   temp_pw1 [half_C * H * W]   -- PW1 output                       */
/*   temp_dw  [half_C * H_P * W_P] -- DW output (pad for next PW2 not*/
/*              needed since PW2 is 1x1; padded for the DW read)      */
/*   temp_pw2 [half_C * H * W]   -- PW2 output                       */
/*                                                                      */
/*  branch_a passthrough + branch_b PW2 output are interleaved by     */
/*  channel_shuffle before writing to sm_out.                          */
/* ================================================================== */
static void shuffle_block_s1(
    data_t* sm_in, data_t* sm_out,
    int C, int H, int W,          /* actual (unpadded) spatial dims */
    int H_P, int W_P,             /* padded spatial dims            */
    const data_t* b2_pw1_w, const data_t* b2_pw1_b,
    const data_t* b2_dw_w,  const data_t* b2_dw_b,
    const data_t* b2_pw2_w, const data_t* b2_pw2_b)
{
    int half = C / 2;
    int hw   = H * W;
    int hw_p = H_P * W_P;

    /*
     * Local intermediates.
     * Worst case: stage-2 blocks: half=58, H=28, W=28 -> 45,248 per array.
     * These are synthesised as internal BRAMs by Vitis HLS.
     * (Thesis Sec 7.4.2.1: "we put internal memory inside every function")
     */
    /*
     * Static local arrays avoid stack overflow (large allocs on the stack
     * would exceed Windows' default 1 MB stack for the C simulation).
     * In Vitis HLS synthesis, static locals are synthesised as internal BRAMs.
     * Max sizes: stage-2 blocks (half=58, H=28, W=28) are the worst case.
     */
    static data_t temp_pw1  [58 * 28 * 28]; /* 45,248 -- PW1 output            */
    static data_t temp_dw_in[58 * 30 * 30]; /* 52,200 -- DW padded input        */
    static data_t temp_dw_out[58 * 28 * 28];/* 45,248 -- DW output              */
    static data_t temp_pw2  [58 * 28 * 28]; /* 45,248 -- PW2 output             */
    static data_t concat    [116 * 28 * 28];/* 90,944 -- cat branches            */
    static data_t b2_in     [58 * 28 * 28]; /* 45,248 -- branch_b unpadded input */

    /* --- Branch A: passthrough (first half_C channels) into concat --- */
    for (int c = 0; c < half; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                concat[c * hw + h * W + w_i] =
                    sm_in[IDX(c, h + 1, w_i + 1, H_P, W_P)];

    /* --- Branch B: collect second half_C channels (unpadded) --- */
    for (int c = 0; c < half; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                b2_in[c * hw + h * W + w_i] =
                    sm_in[IDX(half + c, h + 1, w_i + 1, H_P, W_P)];

    /* PW1: half -> half channels, ReLU */
    conv1x1(b2_in, temp_pw1, half, half, H, W, b2_pw1_w, b2_pw1_b, 1);

    /* Build padded input for DW (1-pixel zero border around temp_pw1) */
    for (int i = 0; i < half * H_P * W_P; i++) temp_dw_in[i] = 0;
    for (int c = 0; c < half; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                temp_dw_in[c * hw_p + (h + 1) * W_P + (w_i + 1)] =
                    temp_pw1[c * hw + h * W + w_i];

    /* DW conv: stride=1, no ReLU (two-sided quantiser) */
    dw_conv3x3(temp_dw_in, temp_dw_out,
               half, H_P, W_P, H, W, 1,
               b2_dw_w, b2_dw_b);

    /* PW2: half -> half channels, ReLU -- separate in/out to avoid aliasing */
    conv1x1(temp_dw_out, temp_pw2, half, half, H, W, b2_pw2_w, b2_pw2_b, 1);

    /* --- Concatenate branch_a (first half) + branch_b (second half) --- */
    for (int c = 0; c < half; c++)
        for (int i = 0; i < hw; i++)
            concat[(half + c) * hw + i] = temp_pw2[c * hw + i];

    /* --- Channel shuffle on concat --- */
    channel_shuffle(concat, C, H, W);

    /* --- Write padded output to sm_out --- */
    zero_mem(sm_out, C * H_P * W_P);
    for (int c = 0; c < C; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                sm_out[IDX(c, h + 1, w_i + 1, H_P, W_P)] =
                    concat[c * hw + h * W + w_i];
}

/* ================================================================== */
/*  SHUFFLE BLOCK -- STRIDE 2                                          */
/*                                                                      */
/*  Input:  sm_in  [in_C][H_P_in][W_P_in]  (padded)                  */
/*  Output: sm_out [out_C][H_P_out][W_P_out] (padded)                 */
/*  Scratch:sm3[] used for branch_b PW1 output (large intermediate)   */
/*                                                                      */
/*  Branch 1 (thesis "branch1"): DW stride=2 -> PW -> out_half ch     */
/*  Branch 2 (thesis "branch2"): PW1 -> DW stride=2 -> PW2 -> out_h  */
/*  Concat + channel shuffle.                                           */
/* ================================================================== */
static void shuffle_block_s2(
    data_t* sm_in,  data_t* sm_out,
    data_t* sm_scratch,               /* SM3 used for PW1 large temp  */
    int in_C,  int in_H,  int in_W,   /* real (unpadded) input dims   */
    int in_H_P, int in_W_P,           /* padded input dims            */
    int out_C, int out_H, int out_W,  /* real output dims             */
    int out_H_P, int out_W_P,         /* padded output dims           */
    /* branch1 weights (DW -> PW) */
    const data_t* b1_dw_w, const data_t* b1_dw_b,
    const data_t* b1_pw_w, const data_t* b1_pw_b,
    /* branch2 weights (PW1 -> DW -> PW2) */
    const data_t* b2_pw1_w, const data_t* b2_pw1_b,
    const data_t* b2_dw_w,  const data_t* b2_dw_b,
    const data_t* b2_pw2_w, const data_t* b2_pw2_b)
{
    int half   = out_C / 2;  /* = 58/116/232 for stages 2/3/4 */
    int hw_in  = in_H  * in_W;
    int hw_out = out_H * out_W;
    int hw_inp = in_H_P * in_W_P;
    int hw_op  = out_H_P * out_W_P;

    /*
     * Large intermediates.
     * Worst case per array (choose max across all stride-2 calls):
     *   b1_dw_out: max(24*28*28, 116*14*14, 232*7*7) = 22,736 (stage-3)
     *   b1_pw_out: max(58*28*28, 116*14*14, 232*7*7) = 22,736
     *   b2_in:     max(24*56*56, 116*28*28, 232*14*14) = 90,944 (stage-3)
     *   PW1 out:   same as b2_in -- stored in SM3 scratch
     */

    /* branch1: all in_C channels -> DW stride=2 -> PW -> half output channels */
    static data_t b1_dw_out[116 * 14 * 14]; /* 22,736 covers all stages */
    dw_conv3x3(sm_in, b1_dw_out,
               in_C, in_H_P, in_W_P, out_H, out_W, 2,
               b1_dw_w, b1_dw_b);

    static data_t b1_pw_out[116 * 14 * 14]; /* 22,736 */
    conv1x1(b1_dw_out, b1_pw_out, in_C, half, out_H, out_W, b1_pw_w, b1_pw_b, 1);

    /* branch2: extract unpadded input then PW1 -> DW stride=2 -> PW2 */
    /* b2_in: max 116*28*28=90,944 for stage-3 block-0               */
    static data_t b2_in[116 * 28 * 28]; /* 90,944 elements */
    for (int c = 0; c < in_C; c++)
        for (int h = 0; h < in_H; h++)
            for (int w_i = 0; w_i < in_W; w_i++)
                b2_in[c * hw_in + h * in_W + w_i] =
                    sm_in[IDX(c, h + 1, w_i + 1, in_H_P, in_W_P)];

    /*
     * PW1: in_C -> half channels, written DIRECTLY into padded layout in SM3.
     * This avoids needing two separate SM3 regions.
     * SM3 holds: half * (in_H+2) * (in_W+2) elements with 1-pixel zero border.
     * Max size across all stride-2 calls:
     *   Stage-2 b0: 58*(56+2)*(56+2) = 58*58*58 = 195,284
     *   Stage-3 b0: 116*30*30        = 104,400
     *   Stage-4 b0: 232*16*16        = 59,392
     * SM3_SIZE = 200,000 covers all cases.
     */
    int in_H_P2 = in_H + 2, in_W_P2 = in_W + 2;
    data_t* b2_pw1_pad = sm_scratch;   /* SM3 = padded PW1 output */
    for (int i = 0; i < half * in_H_P2 * in_W_P2; i++) b2_pw1_pad[i] = 0;

    /* Inline PW1 writing directly to padded positions */
    for (int oc = 0; oc < half; oc++) {
        for (int oh = 0; oh < in_H; oh++) {
            for (int ow = 0; ow < in_W; ow++) {
                acc_t acc = 0;
                for (int ic = 0; ic < in_C; ic++) {
#pragma HLS PIPELINE
                    acc += (acc_t)b2_in[ic * hw_in + oh * in_W + ow]
                         * (acc_t)b2_pw1_w[oc * in_C + ic];
                }
                data_t val = q_norm(acc, b2_pw1_b[oc]);
                if (val < 0) val = 0;  /* ReLU */
                /* Write to padded position (1-pixel border offset) */
                b2_pw1_pad[oc * in_H_P2 * in_W_P2
                           + (oh + 1) * in_W_P2 + (ow + 1)] = val;
            }
        }
    }

    /* DW stride=2 on branch2 PW1 output */
    static data_t b2_dw_out[116 * 14 * 14]; /* max: 22,736 (stage-3) */
    dw_conv3x3(b2_pw1_pad, b2_dw_out,
               half, in_H_P2, in_W_P2, out_H, out_W, 2,
               b2_dw_w, b2_dw_b);

    /* PW2: half -> half channels */
    static data_t b2_pw2_out[116 * 14 * 14]; /* 22,736 */
    conv1x1(b2_dw_out, b2_pw2_out, half, half, out_H, out_W, b2_pw2_w, b2_pw2_b, 1);

    /* Concatenate: [branch1_out | branch2_out] = [half][out_H][out_W] x2 */
    static data_t concat[116 * 28 * 28]; /* max: stage-2 out_C=116,28x28 = 90,944 */
    for (int c = 0; c < half; c++)
        for (int i = 0; i < hw_out; i++) {
            concat[c * hw_out + i]          = b1_pw_out[c * hw_out + i];
            concat[(half + c) * hw_out + i] = b2_pw2_out[c * hw_out + i];
        }

    /* Channel shuffle */
    channel_shuffle(concat, out_C, out_H, out_W);

    /* Write padded output to sm_out */
    zero_mem(sm_out, out_C * out_H_P * out_W_P);
    for (int c = 0; c < out_C; c++)
        for (int h = 0; h < out_H; h++)
            for (int w_i = 0; w_i < out_W; w_i++)
                sm_out[IDX(c, h + 1, w_i + 1, out_H_P, out_W_P)] =
                    concat[c * hw_out + h * out_W + w_i];
}

/* ================================================================== */
/*  GROUP 3: 1x1 Conv5 + Global Average Pool (merged, Sec 7.2.2)      */
/*                                                                      */
/*  Reads:  sm_in  [464][9][9]  (7x7 spatial + 1-pixel border)        */
/*  Writes: sm_out [1024] (avgpool result, = FC input)                 */
/*                                                                      */
/*  conv5: 464 -> 1024 channels, 1x1, ReLU                            */
/*  avgpool: sum 7x7=49 pixels per channel, multiply by 5, shift >>8  */
/*  (Thesis Sec 5.5, avg_pool_core.v: acc_x5[22:8] = acc*5 >> 8)     */
/*                                                                      */
/*  The 7x7 conv5 output is kept as a local array (50,176 elements)   */
/*  then immediately averaged channel-wise.                            */
/* ================================================================== */
static void conv5_avgpool(data_t sm_in[], data_t sm_out[])
{
    /* conv5 output: [1024][7][7] = 50,176 elements */
    static data_t c5_out[CONV5_OUT_C * CONV5_H * CONV5_W];
    /* Unpadded input: 464*7*7=22,736 elements */
    static data_t c5_in[CONV5_IN_C * CONV5_H * CONV5_W];
    for (int c = 0; c < CONV5_IN_C; c++)
        for (int h = 0; h < CONV5_H; h++)
            for (int w_i = 0; w_i < CONV5_W; w_i++)
                c5_in[c * CONV5_H * CONV5_W + h * CONV5_W + w_i] =
                    sm_in[IDX(c, h + 1, w_i + 1,
                              S4_OUT_H_P, S4_OUT_W_P)];

    /* 1x1 conv: 464 -> 1024 channels, ReLU */
    conv1x1(c5_in, c5_out, CONV5_IN_C, CONV5_OUT_C,
            CONV5_H, CONV5_W, conv5_w, conv5_b, 1);

    /* Global average pool: sum 49 pixels per channel, then *5 >>8  */
    for (int c = 0; c < CONV5_OUT_C; c++) {
        acc_t sum = 0;
        for (int h = 0; h < CONV5_H; h++)
            for (int w_i = 0; w_i < CONV5_W; w_i++) {
#pragma HLS PIPELINE
                sum += (acc_t)c5_out[c * CONV5_H * CONV5_W + h * CONV5_W + w_i];
            }
        /* Thesis avg_pool_core.v line 99: acc_x5[22:8] = (acc*5) >> 8 */
        acc_t sum_x5 = sum * 5;
        data_t avg = q_sat(sum_x5 >> 8);
        if (avg < 0) avg = 0;   /* one-sided quantiser after ReLU */
        sm_out[c] = avg;
    }
}

/* ================================================================== */
/*  GROUP 3: Fully Connected Layer + Argmax Classification            */
/*                                                                      */
/*  Reads:  sm_in [1024]  (avgpool output)                            */
/*  Writes: *class_out    (index of maximum FC output)                 */
/*                                                                      */
/*  fc: 1024 -> 1000, no ReLU (two-sided quantiser)                   */
/*  Classification: argmax (running max, Thesis Sec 5.5.1.4)          */
/* ================================================================== */
static void fc_classify(data_t sm_in[], int* class_out)
{
    data_t max_val   = (data_t)-16384;
    int    max_class = 0;

    for (int oc = 0; oc < FC_OUT; oc++) {
        acc_t acc = 0;
        for (int ic = 0; ic < FC_IN; ic++) {
#pragma HLS PIPELINE
            acc += (acc_t)sm_in[ic] * (acc_t)fc_w[oc * FC_IN + ic];
        }
        data_t val = q_norm(acc, fc_b[oc]);
        if (val > max_val) {
            max_val   = val;
            max_class = oc;
        }
    }
    *class_out = max_class;
}

/* ================================================================== */
/*  TOP-LEVEL FUNCTION  --  Shuffle_Model                             */
/*                                                                      */
/*  Orchestrates all layers following the "Second Model" shared-memory */
/*  architecture (Thesis Sec 7.2.2, Fig 7.8).                         */
/*                                                                      */
/*  Ping-pong between SM1 and SM2 for the 16 shuffle blocks:          */
/*    MaxPool output -> SM1                                            */
/*    Block  0 (s2): SM1  -> SM2  (stride-2)                          */
/*    Block  1 (s2): SM2  -> SM1  (stride-1)                          */
/*    Block  2 (s2): SM1  -> SM2  (stride-1)                          */
/*    Block  3 (s2): SM2  -> SM1  (stride-1)                          */
/*    Block  4 (s3): SM1  -> SM2  (stride-2)                          */
/*    ...                                                              */
/*    Block 15 (s4): SM2  -> SM1  (stride-1)  [odd block index]       */
/*  After 16 blocks result is in SM1 (odd block 15 -> SM1).           */
/*  Conv5+AvgPool: SM1 -> SM4.  FC: SM4 -> class_out.                 */
/* ================================================================== */
void Shuffle_Model(
    data_t sm1[SM1_SIZE],
    data_t sm2[SM2_SIZE],
    data_t sm3[SM3_SIZE],
    data_t sm4[SM4_SIZE],
    int   *class_out)
{
    /* Group 1 */
    conv3x3_group1(sm1, sm2);          /* photo (sm1) -> conv out (sm2) */
    max_pool_group1(sm2, sm1);         /* conv out (sm2) -> pool out (sm1) */

    /* Stage 2, Block 0: stride=2, in=24ch@56x56, out=116ch@28x28 */
    shuffle_block_s2(
        sm1, sm2, sm3,
        S2_IN_C, MP_OUT_H, MP_OUT_W, MP_OUT_H_P, MP_OUT_W_P,
        S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P,
        s2_0_b1_dw_w, s2_0_b1_dw_b,
        s2_0_b1_pw_w, s2_0_b1_pw_b,
        s2_0_b2_pw1_w, s2_0_b2_pw1_b,
        s2_0_b2_dw_w,  s2_0_b2_dw_b,
        s2_0_b2_pw2_w, s2_0_b2_pw2_b);

    /* Stage 2, Blocks 1-3: stride=1, 116ch@28x28 */
    shuffle_block_s1(sm2, sm1, S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P,
        s2_1_b2_pw1_w, s2_1_b2_pw1_b, s2_1_b2_dw_w, s2_1_b2_dw_b,
        s2_1_b2_pw2_w, s2_1_b2_pw2_b);
    shuffle_block_s1(sm1, sm2, S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P,
        s2_2_b2_pw1_w, s2_2_b2_pw1_b, s2_2_b2_dw_w, s2_2_b2_dw_b,
        s2_2_b2_pw2_w, s2_2_b2_pw2_b);
    shuffle_block_s1(sm2, sm1, S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P,
        s2_3_b2_pw1_w, s2_3_b2_pw1_b, s2_3_b2_dw_w, s2_3_b2_dw_b,
        s2_3_b2_pw2_w, s2_3_b2_pw2_b);
    /* After block 3 (index 3, even->odd ping-pong): result in SM1 */

    /* Stage 3, Block 0: stride=2, in=116ch@28x28, out=232ch@14x14 */
    shuffle_block_s2(
        sm1, sm2, sm3,
        S3_IN_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P,
        S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
        s3_0_b1_dw_w, s3_0_b1_dw_b,
        s3_0_b1_pw_w, s3_0_b1_pw_b,
        s3_0_b2_pw1_w, s3_0_b2_pw1_b,
        s3_0_b2_dw_w,  s3_0_b2_dw_b,
        s3_0_b2_pw2_w, s3_0_b2_pw2_b);

    /* Stage 3, Blocks 1-7: stride=1, 232ch@14x14 */
    shuffle_block_s1(sm2, sm1, S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
        s3_1_b2_pw1_w, s3_1_b2_pw1_b, s3_1_b2_dw_w, s3_1_b2_dw_b,
        s3_1_b2_pw2_w, s3_1_b2_pw2_b);
    shuffle_block_s1(sm1, sm2, S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
        s3_2_b2_pw1_w, s3_2_b2_pw1_b, s3_2_b2_dw_w, s3_2_b2_dw_b,
        s3_2_b2_pw2_w, s3_2_b2_pw2_b);
    shuffle_block_s1(sm2, sm1, S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
        s3_3_b2_pw1_w, s3_3_b2_pw1_b, s3_3_b2_dw_w, s3_3_b2_dw_b,
        s3_3_b2_pw2_w, s3_3_b2_pw2_b);
    shuffle_block_s1(sm1, sm2, S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
        s3_4_b2_pw1_w, s3_4_b2_pw1_b, s3_4_b2_dw_w, s3_4_b2_dw_b,
        s3_4_b2_pw2_w, s3_4_b2_pw2_b);
    shuffle_block_s1(sm2, sm1, S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
        s3_5_b2_pw1_w, s3_5_b2_pw1_b, s3_5_b2_dw_w, s3_5_b2_dw_b,
        s3_5_b2_pw2_w, s3_5_b2_pw2_b);
    shuffle_block_s1(sm1, sm2, S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
        s3_6_b2_pw1_w, s3_6_b2_pw1_b, s3_6_b2_dw_w, s3_6_b2_dw_b,
        s3_6_b2_pw2_w, s3_6_b2_pw2_b);
    shuffle_block_s1(sm2, sm1, S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
        s3_7_b2_pw1_w, s3_7_b2_pw1_b, s3_7_b2_dw_w, s3_7_b2_dw_b,
        s3_7_b2_pw2_w, s3_7_b2_pw2_b);
    /* After stage 3 block 7 (7 stride-1 after one stride-2): result in SM1 */

    /* Stage 4, Block 0: stride=2, in=232ch@14x14, out=464ch@7x7 */
    shuffle_block_s2(
        sm1, sm2, sm3,
        S4_IN_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
        S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P,
        s4_0_b1_dw_w, s4_0_b1_dw_b,
        s4_0_b1_pw_w, s4_0_b1_pw_b,
        s4_0_b2_pw1_w, s4_0_b2_pw1_b,
        s4_0_b2_dw_w,  s4_0_b2_dw_b,
        s4_0_b2_pw2_w, s4_0_b2_pw2_b);

    /* Stage 4, Blocks 1-3: stride=1, 464ch@7x7 */
    shuffle_block_s1(sm2, sm1, S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P,
        s4_1_b2_pw1_w, s4_1_b2_pw1_b, s4_1_b2_dw_w, s4_1_b2_dw_b,
        s4_1_b2_pw2_w, s4_1_b2_pw2_b);
    shuffle_block_s1(sm1, sm2, S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P,
        s4_2_b2_pw1_w, s4_2_b2_pw1_b, s4_2_b2_dw_w, s4_2_b2_dw_b,
        s4_2_b2_pw2_w, s4_2_b2_pw2_b);
    shuffle_block_s1(sm2, sm1, S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P,
        s4_3_b2_pw1_w, s4_3_b2_pw1_b, s4_3_b2_dw_w, s4_3_b2_dw_b,
        s4_3_b2_pw2_w, s4_3_b2_pw2_b);
    /* After stage 4 block 3 (3 stride-1 after one stride-2): result in SM1 */

    /* Group 3: conv5 + avgpool -> SM4 */
    conv5_avgpool(sm1, sm4);

    /* FC + classification */
    fc_classify(sm4, class_out);
}
