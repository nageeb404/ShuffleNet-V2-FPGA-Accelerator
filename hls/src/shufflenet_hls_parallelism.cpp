/*
 * shufflenet_hls_parallelism.cpp
 * Model 3: Parallelism Based Optimization (Thesis Sec 7.4.2.2)
 *
 * Key technique: "Parallelism Inside Filters"
 *   - UNROLL the inner kernel loops so all multiplications for one filter
 *     window happen in parallel (one cycle per filter).
 *   - PIPELINE the outer filter loop.
 *   - DATAFLOW between Read-Input and Core sub-functions (3x3 conv only).
 *   - ARRAY_PARTITION on weight ROMs for parallel access.
 *
 * Result (thesis, Virtex-7 @ 100 MHz):
 *   Estimated: 21,126,394 clk cycles   Real RTL: ~9,066,784 cycles
 *   BRAM=91%, DSP=44%, LUT=61%, FF=21%
 *
 * Same top-level signature as Pipeline Model (Shuffle_Model).
 * C simulation gives the same class output as the Pipeline Model.
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
/*  Helper                                                             */
/* ================================================================== */
static void zero_mem(data_t* mem, int size)
{
    for (int i = 0; i < size; i++) {
#pragma HLS PIPELINE
        mem[i] = 0;
    }
}

/* ================================================================== */
/*  GROUP 1: 3x3 Convolution -- Read-Input sub-function               */
/*  Reads one 3D window (IC=3, KH=3, KW=3 = 27 elements) from SM1.   */
/*  All 3 nested loops UNROLL'd -> 27 parallel reads (2 BRAM ports).  */
/* ================================================================== */
static void g1_read_win(data_t sm_in[], data_t win[27], int oh, int ow)
{
    for (int ic = 0; ic < CONV1_IN_C; ic++) {
#pragma HLS UNROLL
        for (int kh = 0; kh < 3; kh++) {
#pragma HLS UNROLL
            for (int kw = 0; kw < 3; kw++) {
#pragma HLS UNROLL
                int ih = oh * 2 + kh;
                int iw = ow * 2 + kw;
                win[ic * 9 + kh * 3 + kw] =
                    sm_in[IDX(ic, ih, iw, CONV1_IN_H_P, CONV1_IN_W_P)];
            }
        }
    }
}

/* ================================================================== */
/*  GROUP 1: 3x3 Convolution -- Core sub-function                     */
/*  Applies all 24 filters to the window stored in win[27].           */
/*  PIPELINE on filter loop -> 1 filter/cycle after fill.             */
/*  UNROLL on 27-element dot-product -> 27 parallel DSPs.             */
/* ================================================================== */
static void g1_core(const data_t win[27], data_t res[CONV1_OUT_C])
{
    for (int oc = 0; oc < CONV1_OUT_C; oc++) {
#pragma HLS PIPELINE
        acc_t acc = 0;
        for (int f = 0; f < 27; f++) {
#pragma HLS UNROLL
            acc += (acc_t)win[f] * (acc_t)conv1_w[oc * 27 + f];
        }
        res[oc] = q_relu(q_norm(acc, conv1_b[oc]));
    }
}

/* ================================================================== */
/*  GROUP 1: 3x3 Convolution (main function)                          */
/*  DATAFLOW between g1_read_win and g1_core allows next window read  */
/*  to start while current window's filters are still processing.     */
/* ================================================================== */
static void conv3x3_group1(data_t sm_in[], data_t sm_out[])
{
    zero_mem(sm_out, CONV1_OUT_C * CONV1_OUT_H_P * CONV1_OUT_W_P);

    for (int oh = 0; oh < CONV1_OUT_H; oh++) {
        for (int ow = 0; ow < CONV1_OUT_W; ow++) {
            data_t win[27];
            data_t res[CONV1_OUT_C];
#pragma HLS DATAFLOW
            g1_read_win(sm_in, win, oh, ow);
            g1_core(win, res);
            for (int oc = 0; oc < CONV1_OUT_C; oc++) {
                sm_out[IDX(oc, oh + 1, ow + 1,
                           CONV1_OUT_H_P, CONV1_OUT_W_P)] = res[oc];
            }
        }
    }
}

/* ================================================================== */
/*  GROUP 1: Max Pooling                                               */
/*  INLINE structure (no separate sub-functions, no DATAFLOW).        */
/*  UNROLL all kernel loops -> 9 parallel comparisons.                */
/*  Thesis: 2.3x speedup over Pipeline Model.                         */
/* ================================================================== */
static void max_pool_group1(data_t sm_in[], data_t sm_out[])
{
    zero_mem(sm_out, CONV1_OUT_C * MP_OUT_H_P * MP_OUT_W_P);

    for (int c = 0; c < CONV1_OUT_C; c++) {
        for (int oh = 0; oh < MP_OUT_H; oh++) {
            for (int ow = 0; ow < MP_OUT_W; ow++) {
                /* Inline read: 9-element 3x3 window */
                data_t win[9];
                for (int kh = 0; kh < 3; kh++) {
#pragma HLS UNROLL
                    for (int kw = 0; kw < 3; kw++) {
#pragma HLS UNROLL
                        win[kh * 3 + kw] =
                            sm_in[IDX(c, oh * 2 + kh, ow * 2 + kw,
                                      CONV1_OUT_H_P, CONV1_OUT_W_P)];
                    }
                }
                /* Inline core: max reduction (all UNROLL) */
                data_t mx = win[0];
                for (int f = 1; f < 9; f++) {
#pragma HLS UNROLL
                    if (win[f] > mx) mx = win[f];
                }
                sm_out[IDX(c, oh + 1, ow + 1, MP_OUT_H_P, MP_OUT_W_P)] = mx;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 3x3 Depthwise Convolution -- Parallelism Version          */
/*  INLINE sub-functions (no DATAFLOW).                               */
/*  ARRAY_PARTITION cyclic 9 on weights -> all 9 kernel weights       */
/*  of one channel read in parallel.                                   */
/*  UNROLL both kernel loops -> 9 parallel DSPs per channel.          */
/*  Thesis: 1.32x speedup (filter size small = inherent limitation).  */
/* ================================================================== */
static void dw_conv3x3_par(
    const data_t* in_flat, data_t* out_flat,
    int C, int H_P, int W_P, int H_out, int W_out, int stride,
    const data_t* w, const data_t* b)
{
    /* ARRAY_PARTITION cyclic 9 on w allows all 9 weights for one
       channel to be read in the same cycle.
       NOTE: applied to global weight arrays at call site via pragma or TCL. */
    for (int c = 0; c < C; c++) {
        for (int oh = 0; oh < H_out; oh++) {
            for (int ow = 0; ow < W_out; ow++) {
                /* Inline read: 9-element 3x3 window for channel c */
                data_t win[9];
                for (int kh = 0; kh < 3; kh++) {
#pragma HLS UNROLL
                    for (int kw = 0; kw < 3; kw++) {
#pragma HLS UNROLL
                        int ih = oh * stride + kh;
                        int iw = ow * stride + kw;
                        win[kh * 3 + kw] =
                            in_flat[c * H_P * W_P + ih * W_P + iw];
                    }
                }
                /* Inline core: 9-element dot product (UNROLL) */
                acc_t acc = 0;
                for (int f = 0; f < 9; f++) {
#pragma HLS UNROLL
                    acc += (acc_t)win[f] * (acc_t)w[c * 9 + f];
                }
                out_flat[c * H_out * W_out + oh * W_out + ow] =
                    q_sat((acc >> 8) + (acc_t)b[c]);
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 1x1 Pointwise Conv -- Specialized for 24-in -> 58-out     */
/*  Used in stage-2 stride-2 block (b1_pw and b2_pw1: in_C=24).       */
/*  PIPELINE on output-channel loop -> 1 filter/cycle after fill.     */
/*  UNROLL inner input-channel loop (24) -> 24 parallel DSPs.         */
/*  ARRAY_PARTITION variable=w cyclic factor=24 needed for synthesis. */
/* ================================================================== */
static void conv1x1_f24_to_58(
    const data_t* in_flat, data_t* out_flat,
    int H, int W, const data_t* w, const data_t* b, int relu)
{
    for (int oh = 0; oh < H; oh++) {
        for (int ow = 0; ow < W; ow++) {
            /* Load pixel vector: 24 input channels at this (oh, ow) */
            data_t in_pix[24];
            for (int ic = 0; ic < 24; ic++) {
#pragma HLS UNROLL
                in_pix[ic] = in_flat[ic * H * W + oh * W + ow];
            }
            /* Apply all 58 filters (PIPELINE) with 24 MACs each (UNROLL) */
            for (int oc = 0; oc < 58; oc++) {
#pragma HLS PIPELINE
                acc_t acc = 0;
                for (int ic = 0; ic < 24; ic++) {
#pragma HLS UNROLL
                    acc += (acc_t)in_pix[ic] * (acc_t)w[oc * 24 + ic];
                }
                data_t val = q_norm(acc, b[oc]);
                if (relu && val < 0) val = 0;
                out_flat[oc * H * W + oh * W + ow] = val;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 1x1 Pointwise Conv -- Specialized for 58-in -> 58-out     */
/*  Used in stage-2 stride-1 blocks (all PW layers: in_C=out_C=58).  */
/*  PIPELINE on oc, UNROLL on ic (58 DSPs).                           */
/*  ARRAY_PARTITION cyclic 58 needed on weight arrays for synthesis.  */
/*  Thesis: 27.7x speedup on average for 1x1 conv.                   */
/* ================================================================== */
static void conv1x1_f58(
    const data_t* in_flat, data_t* out_flat,
    int H, int W, const data_t* w, const data_t* b, int relu)
{
    for (int oh = 0; oh < H; oh++) {
        for (int ow = 0; ow < W; ow++) {
            data_t in_pix[58];
            for (int ic = 0; ic < 58; ic++) {
#pragma HLS UNROLL
                in_pix[ic] = in_flat[ic * H * W + oh * W + ow];
            }
            for (int oc = 0; oc < 58; oc++) {
#pragma HLS PIPELINE
                acc_t acc = 0;
                for (int ic = 0; ic < 58; ic++) {
#pragma HLS UNROLL
                    acc += (acc_t)in_pix[ic] * (acc_t)w[oc * 58 + ic];
                }
                data_t val = q_norm(acc, b[oc]);
                if (relu && val < 0) val = 0;
                out_flat[oc * H * W + oh * W + ow] = val;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 1x1 Pointwise Conv -- Specialized for 116-in -> 116-out  */
/*  Used in stage-3 blocks. PIPELINE oc, UNROLL ic (116 DSPs).       */
/*  ARRAY_PARTITION cyclic 116 needed for synthesis.                  */
/* ================================================================== */
static void conv1x1_f116(
    const data_t* in_flat, data_t* out_flat,
    int H, int W, const data_t* w, const data_t* b, int relu)
{
    for (int oh = 0; oh < H; oh++) {
        for (int ow = 0; ow < W; ow++) {
            data_t in_pix[116];
            for (int ic = 0; ic < 116; ic++) {
#pragma HLS UNROLL
                in_pix[ic] = in_flat[ic * H * W + oh * W + ow];
            }
            for (int oc = 0; oc < 116; oc++) {
#pragma HLS PIPELINE
                acc_t acc = 0;
                for (int ic = 0; ic < 116; ic++) {
#pragma HLS UNROLL
                    acc += (acc_t)in_pix[ic] * (acc_t)w[oc * 116 + ic];
                }
                data_t val = q_norm(acc, b[oc]);
                if (relu && val < 0) val = 0;
                out_flat[oc * H * W + oh * W + ow] = val;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 1x1 Pointwise Conv -- Specialized for 232-in -> 232-out  */
/*  Used in stage-4 blocks. PIPELINE oc, UNROLL ic (232 DSPs).       */
/*  ARRAY_PARTITION cyclic 232 needed for synthesis.                  */
/* ================================================================== */
static void conv1x1_f232(
    const data_t* in_flat, data_t* out_flat,
    int H, int W, const data_t* w, const data_t* b, int relu)
{
    for (int oh = 0; oh < H; oh++) {
        for (int ow = 0; ow < W; ow++) {
            data_t in_pix[232];
            for (int ic = 0; ic < 232; ic++) {
#pragma HLS UNROLL
                in_pix[ic] = in_flat[ic * H * W + oh * W + ow];
            }
            for (int oc = 0; oc < 232; oc++) {
#pragma HLS PIPELINE
                acc_t acc = 0;
                for (int ic = 0; ic < 232; ic++) {
#pragma HLS UNROLL
                    acc += (acc_t)in_pix[ic] * (acc_t)w[oc * 232 + ic];
                }
                data_t val = q_norm(acc, b[oc]);
                if (relu && val < 0) val = 0;
                out_flat[oc * H * W + oh * W + ow] = val;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: Channel Shuffle (same as Pipeline Model)                  */
/* ================================================================== */
static void channel_shuffle(data_t* fm, int C, int H, int W)
{
    int half = C / 2;
    int hw   = H * W;
    static data_t tmp[116 * 28 * 28];
    int sz = C * hw;
    for (int i = 0; i < sz; i++) tmp[i] = fm[i];

    for (int ch = 0; ch < C; ch++) {
        int src = (ch & 1) * half + (ch >> 1);
        for (int i = 0; i < hw; i++) {
#pragma HLS PIPELINE
            fm[ch * hw + i] = tmp[src * hw + i];
        }
    }
}

/* ================================================================== */
/*  SHUFFLE BLOCK -- STRIDE 1, Parallelism Version (template)         */
/*                                                                      */
/*  Template parameters give Vivado HLS the fixed loop bounds needed  */
/*  by UNROLL directives inside conv1x1_fN functions.                 */
/*  C=116 -> half=58  -> conv1x1_f58                                  */
/*  C=232 -> half=116 -> conv1x1_f116                                 */
/*  C=464 -> half=232 -> conv1x1_f232                                 */
/* ================================================================== */
template<int C, int H, int W, int H_P, int W_P>
static void shuffle_block_s1_par(
    data_t* sm_in, data_t* sm_out,
    const data_t* b2_pw1_w, const data_t* b2_pw1_b,
    const data_t* b2_dw_w,  const data_t* b2_dw_b,
    const data_t* b2_pw2_w, const data_t* b2_pw2_b)
{
    static const int half = C / 2;
    static const int hw   = H * W;
    static const int hw_p = H_P * W_P;

    /* Local intermediate arrays -- template params size them correctly */
    static data_t temp_pw1   [C/2 * H * W];
    static data_t temp_dw_in [C/2 * H_P * W_P];
    static data_t temp_dw_out[C/2 * H * W];
    static data_t temp_pw2   [C/2 * H * W];
    static data_t concat      [C * H * W];
    static data_t b2_in       [C/2 * H * W];

    /* Branch A: passthrough (unpadded) into concat first half */
    for (int c = 0; c < half; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                concat[c * hw + h * W + w_i] =
                    sm_in[IDX(c, h + 1, w_i + 1, H_P, W_P)];

    /* Branch B: collect second half channels */
    for (int c = 0; c < half; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                b2_in[c * hw + h * W + w_i] =
                    sm_in[IDX(half + c, h + 1, w_i + 1, H_P, W_P)];

    /* PW1: dispatch to specialized function */
    if (half == 58)
        conv1x1_f58(b2_in, temp_pw1, H, W, b2_pw1_w, b2_pw1_b, 1);
    else if (half == 116)
        conv1x1_f116(b2_in, temp_pw1, H, W, b2_pw1_w, b2_pw1_b, 1);
    else
        conv1x1_f232(b2_in, temp_pw1, H, W, b2_pw1_w, b2_pw1_b, 1);

    /* Pad PW1 output for DW input */
    for (int i = 0; i < half * H_P * W_P; i++) temp_dw_in[i] = 0;
    for (int c = 0; c < half; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                temp_dw_in[c * hw_p + (h + 1) * W_P + (w_i + 1)] =
                    temp_pw1[c * hw + h * W + w_i];

    /* DW conv stride=1 */
    dw_conv3x3_par(temp_dw_in, temp_dw_out, half, H_P, W_P, H, W, 1,
                   b2_dw_w, b2_dw_b);

    /* PW2 */
    if (half == 58)
        conv1x1_f58(temp_dw_out, temp_pw2, H, W, b2_pw2_w, b2_pw2_b, 1);
    else if (half == 116)
        conv1x1_f116(temp_dw_out, temp_pw2, H, W, b2_pw2_w, b2_pw2_b, 1);
    else
        conv1x1_f232(temp_dw_out, temp_pw2, H, W, b2_pw2_w, b2_pw2_b, 1);

    /* Concatenate */
    for (int c = 0; c < half; c++)
        for (int i = 0; i < hw; i++)
            concat[(half + c) * hw + i] = temp_pw2[c * hw + i];

    channel_shuffle(concat, C, H, W);

    zero_mem(sm_out, C * H_P * W_P);
    for (int c = 0; c < C; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                sm_out[IDX(c, h + 1, w_i + 1, H_P, W_P)] =
                    concat[c * hw + h * W + w_i];
}

/* ================================================================== */
/*  SHUFFLE BLOCK -- STRIDE 2, Parallelism Version (template)         */
/*                                                                      */
/*  IN_C: input channels (24 for stage-2, 116 for stage-3, 232 s4)   */
/*  OUT_C: output channels (116, 232, 464)                            */
/*  Stage-2 uses conv1x1_f24_to_58 for b2_pw1 and b1_pw.             */
/* ================================================================== */
template<int IN_C, int IN_H, int IN_W, int IN_H_P, int IN_W_P,
         int OUT_C, int OUT_H, int OUT_W, int OUT_H_P, int OUT_W_P>
static void shuffle_block_s2_par(
    data_t* sm_in, data_t* sm_out, data_t* sm_scratch,
    const data_t* b1_dw_w, const data_t* b1_dw_b,
    const data_t* b1_pw_w, const data_t* b1_pw_b,
    const data_t* b2_pw1_w, const data_t* b2_pw1_b,
    const data_t* b2_dw_w,  const data_t* b2_dw_b,
    const data_t* b2_pw2_w, const data_t* b2_pw2_b)
{
    static const int half   = OUT_C / 2;
    static const int hw_in  = IN_H  * IN_W;
    static const int hw_out = OUT_H * OUT_W;
    static const int hw_inp = IN_H_P * IN_W_P;
    static const int hw_op  = OUT_H_P * OUT_W_P;
    static const int in_H_P2 = IN_H + 2;
    static const int in_W_P2 = IN_W + 2;

    static data_t b1_dw_out [OUT_C/2 * OUT_H * OUT_W]; /* max: 116*14*14=22736 */
    static data_t b1_pw_out [OUT_C/2 * OUT_H * OUT_W];
    static data_t b2_in     [IN_C * IN_H * IN_W];       /* max: 116*28*28=90944 */
    static data_t b2_dw_out [OUT_C/2 * OUT_H * OUT_W];
    static data_t b2_pw2_out[OUT_C/2 * OUT_H * OUT_W];
    static data_t concat    [OUT_C * OUT_H * OUT_W];

    /* Branch 1: DW stride=2 on all IN_C channels */
    dw_conv3x3_par(sm_in, b1_dw_out,
                   IN_C, IN_H_P, IN_W_P, OUT_H, OUT_W, 2,
                   b1_dw_w, b1_dw_b);

    /* Branch 1: PW in_C=IN_C -> half */
    if (IN_C == 24)
        conv1x1_f24_to_58(b1_dw_out, b1_pw_out, OUT_H, OUT_W, b1_pw_w, b1_pw_b, 1);
    else if (IN_C == 116)
        conv1x1_f116(b1_dw_out, b1_pw_out, OUT_H, OUT_W, b1_pw_w, b1_pw_b, 1);
    else
        conv1x1_f232(b1_dw_out, b1_pw_out, OUT_H, OUT_W, b1_pw_w, b1_pw_b, 1);

    /* Branch 2: extract unpadded input */
    for (int c = 0; c < IN_C; c++)
        for (int h = 0; h < IN_H; h++)
            for (int w_i = 0; w_i < IN_W; w_i++)
                b2_in[c * hw_in + h * IN_W + w_i] =
                    sm_in[IDX(c, h + 1, w_i + 1, IN_H_P, IN_W_P)];

    /* Branch 2: PW1 -> written directly to padded layout in sm_scratch */
    data_t* b2_pw1_pad = sm_scratch;
    for (int i = 0; i < half * in_H_P2 * in_W_P2; i++) b2_pw1_pad[i] = 0;

    /* Inline PW1 (can't use DATAFLOW -- shared memory violates 1P-1C rule) */
    if (IN_C == 24) {
        for (int oc = 0; oc < half; oc++) {
            for (int oh = 0; oh < IN_H; oh++) {
                for (int ow = 0; ow < IN_W; ow++) {
                    data_t in_pix[24];
                    for (int ic = 0; ic < 24; ic++) {
#pragma HLS UNROLL
                        in_pix[ic] = b2_in[ic * hw_in + oh * IN_W + ow];
                    }
                    acc_t acc = 0;
                    for (int ic = 0; ic < 24; ic++) {
#pragma HLS UNROLL
                        acc += (acc_t)in_pix[ic] * (acc_t)b2_pw1_w[oc * 24 + ic];
                    }
                    data_t val = q_norm(acc, b2_pw1_b[oc]);
                    if (val < 0) val = 0;
                    b2_pw1_pad[oc * in_H_P2 * in_W_P2
                               + (oh + 1) * in_W_P2 + (ow + 1)] = val;
                }
            }
        }
    } else if (IN_C == 116) {
        for (int oc = 0; oc < half; oc++) {
            for (int oh = 0; oh < IN_H; oh++) {
                for (int ow = 0; ow < IN_W; ow++) {
                    data_t in_pix[116];
                    for (int ic = 0; ic < 116; ic++) {
#pragma HLS UNROLL
                        in_pix[ic] = b2_in[ic * hw_in + oh * IN_W + ow];
                    }
                    acc_t acc = 0;
                    for (int ic = 0; ic < 116; ic++) {
#pragma HLS UNROLL
                        acc += (acc_t)in_pix[ic] * (acc_t)b2_pw1_w[oc * 116 + ic];
                    }
                    data_t val = q_norm(acc, b2_pw1_b[oc]);
                    if (val < 0) val = 0;
                    b2_pw1_pad[oc * in_H_P2 * in_W_P2
                               + (oh + 1) * in_W_P2 + (ow + 1)] = val;
                }
            }
        }
    } else { /* IN_C == 232 */
        for (int oc = 0; oc < half; oc++) {
            for (int oh = 0; oh < IN_H; oh++) {
                for (int ow = 0; ow < IN_W; ow++) {
                    data_t in_pix[232];
                    for (int ic = 0; ic < 232; ic++) {
#pragma HLS UNROLL
                        in_pix[ic] = b2_in[ic * hw_in + oh * IN_W + ow];
                    }
                    acc_t acc = 0;
                    for (int ic = 0; ic < 232; ic++) {
#pragma HLS UNROLL
                        acc += (acc_t)in_pix[ic] * (acc_t)b2_pw1_w[oc * 232 + ic];
                    }
                    data_t val = q_norm(acc, b2_pw1_b[oc]);
                    if (val < 0) val = 0;
                    b2_pw1_pad[oc * in_H_P2 * in_W_P2
                               + (oh + 1) * in_W_P2 + (ow + 1)] = val;
                }
            }
        }
    }

    /* Branch 2: DW stride=2 on half channels */
    dw_conv3x3_par(b2_pw1_pad, b2_dw_out,
                   half, in_H_P2, in_W_P2, OUT_H, OUT_W, 2,
                   b2_dw_w, b2_dw_b);

    /* Branch 2: PW2 half->half */
    if (half == 58)
        conv1x1_f58(b2_dw_out, b2_pw2_out, OUT_H, OUT_W, b2_pw2_w, b2_pw2_b, 1);
    else if (half == 116)
        conv1x1_f116(b2_dw_out, b2_pw2_out, OUT_H, OUT_W, b2_pw2_w, b2_pw2_b, 1);
    else
        conv1x1_f232(b2_dw_out, b2_pw2_out, OUT_H, OUT_W, b2_pw2_w, b2_pw2_b, 1);

    /* Concat + shuffle + write padded output */
    for (int c = 0; c < half; c++)
        for (int i = 0; i < hw_out; i++) {
            concat[c * hw_out + i]          = b1_pw_out[c * hw_out + i];
            concat[(half + c) * hw_out + i] = b2_pw2_out[c * hw_out + i];
        }
    channel_shuffle(concat, OUT_C, OUT_H, OUT_W);

    zero_mem(sm_out, OUT_C * OUT_H_P * OUT_W_P);
    for (int c = 0; c < OUT_C; c++)
        for (int h = 0; h < OUT_H; h++)
            for (int w_i = 0; w_i < OUT_W; w_i++)
                sm_out[IDX(c, h + 1, w_i + 1, OUT_H_P, OUT_W_P)] =
                    concat[c * hw_out + h * OUT_W + w_i];
}

/* ================================================================== */
/*  GROUP 3: 1x1 Conv5 + Global Average Pool                          */
/*  conv5: 464->1024 channels, 1x1, PIPELINE oc, UNROLL 464 ic.      */
/*  avgpool: same as Pipeline Model (sum*5 >> 8).                     */
/*  ARRAY_PARTITION cyclic 464 on conv5_w for parallel weight access. */
/*  Thesis: 365x speedup (filter size 464 is large).                  */
/* ================================================================== */
static void conv5_avgpool_par(data_t sm_in[], data_t sm_out[])
{
    static data_t c5_out[CONV5_OUT_C * CONV5_H * CONV5_W]; /* 1024*7*7=50176 */
    static data_t c5_in [CONV5_IN_C  * CONV5_H * CONV5_W]; /* 464*7*7=22736  */

    /* Unpad input */
    for (int c = 0; c < CONV5_IN_C; c++)
        for (int h = 0; h < CONV5_H; h++)
            for (int w_i = 0; w_i < CONV5_W; w_i++)
                c5_in[c * CONV5_H * CONV5_W + h * CONV5_W + w_i] =
                    sm_in[IDX(c, h + 1, w_i + 1, S4_OUT_H_P, S4_OUT_W_P)];

    /* 1x1 conv: 464->1024, PIPELINE on oc, UNROLL on 464 ic */
    for (int oh = 0; oh < CONV5_H; oh++) {
        for (int ow = 0; ow < CONV5_W; ow++) {
            data_t in_pix[CONV5_IN_C];
            for (int ic = 0; ic < CONV5_IN_C; ic++) {
#pragma HLS UNROLL
                in_pix[ic] = c5_in[ic * CONV5_H * CONV5_W + oh * CONV5_W + ow];
            }
            for (int oc = 0; oc < CONV5_OUT_C; oc++) {
#pragma HLS PIPELINE
                acc_t acc = 0;
                for (int ic = 0; ic < CONV5_IN_C; ic++) {
#pragma HLS UNROLL
                    acc += (acc_t)in_pix[ic] * (acc_t)conv5_w[oc * CONV5_IN_C + ic];
                }
                data_t val = q_norm(acc, conv5_b[oc]);
                if (val < 0) val = 0;
                c5_out[oc * CONV5_H * CONV5_W + oh * CONV5_W + ow] = val;
            }
        }
    }

    /* Global average pool: sum 49 pixels, multiply *5 >>8 (same as RTL) */
    for (int c = 0; c < CONV5_OUT_C; c++) {
        acc_t sum = 0;
        for (int h = 0; h < CONV5_H; h++)
            for (int w_i = 0; w_i < CONV5_W; w_i++) {
#pragma HLS PIPELINE
                sum += (acc_t)c5_out[c * CONV5_H * CONV5_W + h * CONV5_W + w_i];
            }
        acc_t sum_x5 = sum * 5;
        data_t avg   = q_sat(sum_x5 >> 8);
        if (avg < 0) avg = 0;
        sm_out[c] = avg;
    }
}

/* ================================================================== */
/*  GROUP 3: Fully Connected Layer + Argmax                           */
/*  PIPELINE on neuron loop, UNROLL(256) on multiply, UNROLL on acc. */
/*  ARRAY_PARTITION complete on sm4 (1024 registers for parallel      */
/*  reads), cyclic 256 on fc_w.                                       */
/*  Thesis: 114.2x speedup.                                           */
/* ================================================================== */
static void fc_classify_par(data_t sm4[SM4_SIZE], int* class_out)
{
    /* ARRAY_PARTITION complete on sm4 -> 1024 registers */
#pragma HLS ARRAY_PARTITION variable=sm4 complete dim=1

    data_t max_val   = (data_t)-16384;
    int    max_class = 0;

    for (int oc = 0; oc < FC_OUT; oc++) {
#pragma HLS PIPELINE
        /* Multiply: UNROLL factor 256 -> 256 DSPs, 4 iterations */
        acc_t prods[FC_IN];
        for (int ic = 0; ic < FC_IN; ic++) {
#pragma HLS UNROLL factor=256
            prods[ic] = (acc_t)sm4[ic] * (acc_t)fc_w[oc * FC_IN + ic];
        }
        /* Accumulate: fully UNROLL -> reduction tree in 1 cycle */
        acc_t acc = 0;
        for (int ic = 0; ic < FC_IN; ic++) {
#pragma HLS UNROLL
            acc += prods[ic];
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
/*  TOP-LEVEL FUNCTION -- Shuffle_Model                               */
/*  Same interface as Pipeline Model.                                  */
/*  Uses parallelism-optimized sub-functions throughout.              */
/* ================================================================== */
void Shuffle_Model(
    data_t sm1[SM1_SIZE],
    data_t sm2[SM2_SIZE],
    data_t sm3[SM3_SIZE],
    data_t sm4[SM4_SIZE],
    int   *class_out)
{
    /* Group 1 */
    conv3x3_group1(sm1, sm2);
    max_pool_group1(sm2, sm1);

    /* Stage 2, Block 0: stride=2, in=24ch@56x56, out=116ch@28x28 */
    shuffle_block_s2_par<S2_IN_C, MP_OUT_H, MP_OUT_W, MP_OUT_H_P, MP_OUT_W_P,
                         S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P>(
        sm1, sm2, sm3,
        s2_0_b1_dw_w, s2_0_b1_dw_b,
        s2_0_b1_pw_w, s2_0_b1_pw_b,
        s2_0_b2_pw1_w, s2_0_b2_pw1_b,
        s2_0_b2_dw_w,  s2_0_b2_dw_b,
        s2_0_b2_pw2_w, s2_0_b2_pw2_b);

    /* Stage 2, Blocks 1-3: stride=1, 116ch@28x28 */
    shuffle_block_s1_par<S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P>(
        sm2, sm1,
        s2_1_b2_pw1_w, s2_1_b2_pw1_b, s2_1_b2_dw_w, s2_1_b2_dw_b,
        s2_1_b2_pw2_w, s2_1_b2_pw2_b);
    shuffle_block_s1_par<S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P>(
        sm1, sm2,
        s2_2_b2_pw1_w, s2_2_b2_pw1_b, s2_2_b2_dw_w, s2_2_b2_dw_b,
        s2_2_b2_pw2_w, s2_2_b2_pw2_b);
    shuffle_block_s1_par<S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P>(
        sm2, sm1,
        s2_3_b2_pw1_w, s2_3_b2_pw1_b, s2_3_b2_dw_w, s2_3_b2_dw_b,
        s2_3_b2_pw2_w, s2_3_b2_pw2_b);

    /* Stage 3, Block 0: stride=2, 116ch@28x28 -> 232ch@14x14 */
    shuffle_block_s2_par<S3_IN_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P,
                         S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm1, sm2, sm3,
        s3_0_b1_dw_w, s3_0_b1_dw_b,
        s3_0_b1_pw_w, s3_0_b1_pw_b,
        s3_0_b2_pw1_w, s3_0_b2_pw1_b,
        s3_0_b2_dw_w,  s3_0_b2_dw_b,
        s3_0_b2_pw2_w, s3_0_b2_pw2_b);

    /* Stage 3, Blocks 1-7: stride=1, 232ch@14x14 */
    shuffle_block_s1_par<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm2, sm1,
        s3_1_b2_pw1_w, s3_1_b2_pw1_b, s3_1_b2_dw_w, s3_1_b2_dw_b,
        s3_1_b2_pw2_w, s3_1_b2_pw2_b);
    shuffle_block_s1_par<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm1, sm2,
        s3_2_b2_pw1_w, s3_2_b2_pw1_b, s3_2_b2_dw_w, s3_2_b2_dw_b,
        s3_2_b2_pw2_w, s3_2_b2_pw2_b);
    shuffle_block_s1_par<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm2, sm1,
        s3_3_b2_pw1_w, s3_3_b2_pw1_b, s3_3_b2_dw_w, s3_3_b2_dw_b,
        s3_3_b2_pw2_w, s3_3_b2_pw2_b);
    shuffle_block_s1_par<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm1, sm2,
        s3_4_b2_pw1_w, s3_4_b2_pw1_b, s3_4_b2_dw_w, s3_4_b2_dw_b,
        s3_4_b2_pw2_w, s3_4_b2_pw2_b);
    shuffle_block_s1_par<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm2, sm1,
        s3_5_b2_pw1_w, s3_5_b2_pw1_b, s3_5_b2_dw_w, s3_5_b2_dw_b,
        s3_5_b2_pw2_w, s3_5_b2_pw2_b);
    shuffle_block_s1_par<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm1, sm2,
        s3_6_b2_pw1_w, s3_6_b2_pw1_b, s3_6_b2_dw_w, s3_6_b2_dw_b,
        s3_6_b2_pw2_w, s3_6_b2_pw2_b);
    shuffle_block_s1_par<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm2, sm1,
        s3_7_b2_pw1_w, s3_7_b2_pw1_b, s3_7_b2_dw_w, s3_7_b2_dw_b,
        s3_7_b2_pw2_w, s3_7_b2_pw2_b);

    /* Stage 4, Block 0: stride=2, 232ch@14x14 -> 464ch@7x7 */
    shuffle_block_s2_par<S4_IN_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
                         S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P>(
        sm1, sm2, sm3,
        s4_0_b1_dw_w, s4_0_b1_dw_b,
        s4_0_b1_pw_w, s4_0_b1_pw_b,
        s4_0_b2_pw1_w, s4_0_b2_pw1_b,
        s4_0_b2_dw_w,  s4_0_b2_dw_b,
        s4_0_b2_pw2_w, s4_0_b2_pw2_b);

    /* Stage 4, Blocks 1-3: stride=1, 464ch@7x7 */
    shuffle_block_s1_par<S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P>(
        sm2, sm1,
        s4_1_b2_pw1_w, s4_1_b2_pw1_b, s4_1_b2_dw_w, s4_1_b2_dw_b,
        s4_1_b2_pw2_w, s4_1_b2_pw2_b);
    shuffle_block_s1_par<S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P>(
        sm1, sm2,
        s4_2_b2_pw1_w, s4_2_b2_pw1_b, s4_2_b2_dw_w, s4_2_b2_dw_b,
        s4_2_b2_pw2_w, s4_2_b2_pw2_b);
    shuffle_block_s1_par<S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P>(
        sm2, sm1,
        s4_3_b2_pw1_w, s4_3_b2_pw1_b, s4_3_b2_dw_w, s4_3_b2_dw_b,
        s4_3_b2_pw2_w, s4_3_b2_pw2_b);

    /* Group 3 */
    conv5_avgpool_par(sm1, sm4);
    fc_classify_par(sm4, class_out);
}
