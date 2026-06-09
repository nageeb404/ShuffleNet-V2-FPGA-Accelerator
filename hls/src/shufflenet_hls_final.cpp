/*
 * shufflenet_hls_final.cpp
 * Model 4: Final Model -- Speed Optimization + Dynamic Quantization
 * (Thesis Sec 7.4.3 "Speed Optimization" + Sec 7.4.4 "Final Model")
 *
 * Additions over Model 3 (Parallelism):
 *   Sec 7.4.3.2  Dual-window DW conv: 2 adjacent output cols per iteration,
 *                sharing 9-tap weight load (6 cycles for 2 vs 5 each)
 *   Sec 7.4.3.2  Quad-window maxpool: 4 channels x 2 cols = 8 outputs/iter
 *   Sec 7.4.3.3  avgpool: sum >> 2 instead of sum*5>>8; FC weights /49,
 *                FC biases /4 to compensate the scale change
 *   Sec 7.4.4    Dynamic per-layer saturation (Table 7.1):
 *                  Photo=8b, conv1=10b, maxpool=10b, Shuffle PW=12b,
 *                  Shuffle DW=9b, conv5=9b, FC=9b
 *   Sec 7.4.3.2  FC UNROLL reduced from 256 to 32 (fewer DSPs)
 *   Clock: 7 ns (Vitis HLS target) -> 80 MHz after Vivado implementation
 *
 * Result (thesis, Virtex-7 after Vivado place-and-route @ 80 MHz):
 *   Estimated HLS: ~10,932,000 cycles   Real RTL: ~3,200,000 cycles
 *   LUT=199,427(46%), BRAM=1182(80%), DSP=1940(54%), FF=98,246(11%)
 *   WNS=+0.007 ns, 24.84 fps, 3.828 W, 0.154 J/frame
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
/*  Dynamic quantization helpers (Thesis Table 7.1 / 7.2)             */
/*  Each layer uses a narrower bit width than the Q6.8 baseline.      */
/*  Saturation clamps to the per-layer signed range; the normalization */
/*  shift (>>8) remains consistent with the Q6.8 accumulation format. */
/* ================================================================== */
static inline data_t q_sat8(acc_t x)
{
    if (x >   127LL) return   127;
    if (x <  -128LL) return (data_t)-128;
    return (data_t)x;
}

static inline data_t q_sat10(acc_t x)   /* conv1 / maxpool: 10-bit Q6 */
{
    if (x >   511LL) return   511;
    if (x <  -512LL) return (data_t)-512;
    return (data_t)x;
}

static inline data_t q_sat12(acc_t x)   /* shuffle-group PW: 12-bit Q8 */
{
    if (x >  2047LL) return  2047;
    if (x < -2048LL) return (data_t)-2048;
    return (data_t)x;
}

static inline data_t q_sat9(acc_t x)    /* DW / conv5 / FC: 9-bit Q5 */
{
    if (x >   255LL) return   255;
    if (x <  -256LL) return (data_t)-256;
    return (data_t)x;
}

/* Normalize (>>8 + bias) then saturate to the per-layer width */
static inline data_t q_norm10(acc_t acc, data_t bias)
{
    return q_sat10((acc >> 8) + (acc_t)bias);
}
static inline data_t q_norm12(acc_t acc, data_t bias)
{
    return q_sat12((acc >> 8) + (acc_t)bias);
}
static inline data_t q_norm9(acc_t acc, data_t bias)
{
    return q_sat9((acc >> 8) + (acc_t)bias);
}

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
/*  Same structure as Model 3; unchanged by final-model optimizations. */
/* ================================================================== */
static void g1_read_win_fin(data_t sm_in[], data_t win[27], int oh, int ow)
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
/*  Final model: output saturated to 10-bit (Table 7.1: G1=10b Q6).  */
/* ================================================================== */
static void g1_core_fin(const data_t win[27], data_t res[CONV1_OUT_C])
{
    for (int oc = 0; oc < CONV1_OUT_C; oc++) {
#pragma HLS PIPELINE
        acc_t acc = 0;
        for (int f = 0; f < 27; f++) {
#pragma HLS UNROLL
            acc += (acc_t)win[f] * (acc_t)conv1_w[oc * 27 + f];
        }
        data_t v = q_norm10(acc, conv1_b[oc]);   /* 10-bit saturate + add bias */
        res[oc]  = (v < 0) ? 0 : v;             /* ReLU */
    }
}

/* ================================================================== */
/*  GROUP 1: 3x3 Convolution (main function)                          */
/*  DATAFLOW between g1_read_win_fin and g1_core_fin.                 */
/* ================================================================== */
static void conv3x3_group1_fin(data_t sm_in[], data_t sm_out[])
{
    zero_mem(sm_out, CONV1_OUT_C * CONV1_OUT_H_P * CONV1_OUT_W_P);

    for (int oh = 0; oh < CONV1_OUT_H; oh++) {
        for (int ow = 0; ow < CONV1_OUT_W; ow++) {
            data_t win[27];
            data_t res[CONV1_OUT_C];
#pragma HLS DATAFLOW
            g1_read_win_fin(sm_in, win, oh, ow);
            g1_core_fin(win, res);
            for (int oc = 0; oc < CONV1_OUT_C; oc++) {
                sm_out[IDX(oc, oh + 1, ow + 1,
                           CONV1_OUT_H_P, CONV1_OUT_W_P)] = res[oc];
            }
        }
    }
}

/* ================================================================== */
/*  GROUP 1: Max Pooling -- Quad Window (Thesis Sec 7.4.3.2)          */
/*  Processes 4 channels x 2 output columns = 8 outputs per iteration */
/*  UNROLL dc (4 channels) and dw (2 columns) fully -> 8 parallel.   */
/*  Output saturated to 10-bit (Table 7.1: maxpool=10b Q6).           */
/*  CONV1_OUT_C=24 (divisible by 4), MP_OUT_W=56 (divisible by 2).   */
/* ================================================================== */
static void max_pool_group1_quad(data_t sm_in[], data_t sm_out[])
{
    zero_mem(sm_out, CONV1_OUT_C * MP_OUT_H_P * MP_OUT_W_P);

    for (int c = 0; c < CONV1_OUT_C; c += 4) {      /* 6 outer iterations */
        for (int oh = 0; oh < MP_OUT_H; oh++) {
            for (int ow = 0; ow < MP_OUT_W; ow += 2) { /* 28 inner iters */
                for (int dc = 0; dc < 4; dc++) {     /* UNROLL 4 channels */
#pragma HLS UNROLL
                    for (int dw = 0; dw < 2; dw++) { /* UNROLL 2 columns  */
#pragma HLS UNROLL
                        int cc   = c + dc;
                        int ow2  = ow + dw;
                        data_t mx = sm_in[IDX(cc, oh*2, ow2*2,
                                               CONV1_OUT_H_P, CONV1_OUT_W_P)];
                        for (int kh = 0; kh < 3; kh++) {
#pragma HLS UNROLL
                            for (int kw = 0; kw < 3; kw++) {
#pragma HLS UNROLL
                                data_t v = sm_in[IDX(cc, oh*2 + kh, ow2*2 + kw,
                                                      CONV1_OUT_H_P, CONV1_OUT_W_P)];
                                if (v > mx) mx = v;
                            }
                        }
                        sm_out[IDX(cc, oh + 1, ow2 + 1, MP_OUT_H_P, MP_OUT_W_P)] =
                            q_sat10((acc_t)mx);    /* clamp to 10-bit range */
                    }
                }
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 3x3 Depthwise Conv -- Dual Window (Thesis Sec 7.4.3.2)   */
/*  Computes 2 adjacent output columns per inner iteration.           */
/*  Both columns share the 9-tap weight load for this channel ->      */
/*  saves memory accesses (6 cycles for 2 outputs vs 5 each).         */
/*  Output saturated to 9-bit (Table 7.1: DW intermediate = 9b Q5).  */
/*  Handles odd W_out: ow+1 guard prevents out-of-bounds write.       */
/* ================================================================== */
static void dw_conv3x3_dual(
    const data_t* in_flat, data_t* out_flat,
    int C, int H_P, int W_P, int H_out, int W_out, int stride,
    const data_t* w, const data_t* b)
{
    for (int c = 0; c < C; c++) {
        for (int oh = 0; oh < H_out; oh++) {
            for (int ow = 0; ow < W_out; ow += 2) {  /* step 2: dual window */
                /* Load 9 weights for channel c once, shared by both outputs */
                data_t wt[9];
                for (int f = 0; f < 9; f++) {
#pragma HLS UNROLL
                    wt[f] = w[c * 9 + f];
                }
                data_t bias_c = b[c];

                /* Output column 0 */
                data_t win0[9];
                for (int kh = 0; kh < 3; kh++) {
#pragma HLS UNROLL
                    for (int kw = 0; kw < 3; kw++) {
#pragma HLS UNROLL
                        win0[kh * 3 + kw] =
                            in_flat[c * H_P * W_P +
                                    (oh * stride + kh) * W_P +
                                    (ow * stride + kw)];
                    }
                }
                acc_t acc0 = 0;
                for (int f = 0; f < 9; f++) {
#pragma HLS UNROLL
                    acc0 += (acc_t)win0[f] * (acc_t)wt[f];
                }
                out_flat[c * H_out * W_out + oh * W_out + ow] =
                    q_sat9((acc0 >> 8) + (acc_t)bias_c);

                /* Output column 1 -- guard for odd W_out (e.g. W=7) */
                if (ow + 1 < W_out) {
                    data_t win1[9];
                    for (int kh = 0; kh < 3; kh++) {
#pragma HLS UNROLL
                        for (int kw = 0; kw < 3; kw++) {
#pragma HLS UNROLL
                            win1[kh * 3 + kw] =
                                in_flat[c * H_P * W_P +
                                        (oh * stride + kh) * W_P +
                                        ((ow + 1) * stride + kw)];
                        }
                    }
                    acc_t acc1 = 0;
                    for (int f = 0; f < 9; f++) {
#pragma HLS UNROLL
                        acc1 += (acc_t)win1[f] * (acc_t)wt[f];
                    }
                    out_flat[c * H_out * W_out + oh * W_out + ow + 1] =
                        q_sat9((acc1 >> 8) + (acc_t)bias_c);
                }
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 1x1 PW Conv -- 24->58 channels (12-bit output)           */
/*  Same structure as Model 3 but output saturated to 12-bit          */
/*  (Table 7.1: shuffle-group PW = 12b Q8).                          */
/* ================================================================== */
static void conv1x1_f24_to_58_fin(
    const data_t* in_flat, data_t* out_flat,
    int H, int W, const data_t* w, const data_t* b, int relu)
{
    for (int oh = 0; oh < H; oh++) {
        for (int ow = 0; ow < W; ow++) {
            data_t in_pix[24];
            for (int ic = 0; ic < 24; ic++) {
#pragma HLS UNROLL
                in_pix[ic] = in_flat[ic * H * W + oh * W + ow];
            }
            for (int oc = 0; oc < 58; oc++) {
#pragma HLS PIPELINE
                acc_t acc = 0;
                for (int ic = 0; ic < 24; ic++) {
#pragma HLS UNROLL
                    acc += (acc_t)in_pix[ic] * (acc_t)w[oc * 24 + ic];
                }
                data_t val = q_norm12(acc, b[oc]);
                if (relu && val < 0) val = 0;
                out_flat[oc * H * W + oh * W + ow] = val;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 1x1 PW Conv -- 58->58 channels (12-bit output)           */
/* ================================================================== */
static void conv1x1_f58_fin(
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
                data_t val = q_norm12(acc, b[oc]);
                if (relu && val < 0) val = 0;
                out_flat[oc * H * W + oh * W + ow] = val;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 1x1 PW Conv -- 116->116 channels (12-bit output)         */
/* ================================================================== */
static void conv1x1_f116_fin(
    const data_t* in_flat, data_t* out_flat,
    int H, int W, const data_t* w, const data_t* b, int relu)
{
    for (int oh = 0; oh < H; oh++) {
        for (int ow = 0; ow < W; ow++) {
            data_t in_pix[116];
            for (int ic = 0; ic < 116; ic++) {
#pragma HLS UNROLL factor=4
                in_pix[ic] = in_flat[ic * H * W + oh * W + ow];
            }
            for (int oc = 0; oc < 116; oc++) {
#pragma HLS PIPELINE
                acc_t acc = 0;
                for (int ic = 0; ic < 116; ic++) {
#pragma HLS UNROLL factor=4
                    acc += (acc_t)in_pix[ic] * (acc_t)w[oc * 116 + ic];
                }
                data_t val = q_norm12(acc, b[oc]);
                if (relu && val < 0) val = 0;
                out_flat[oc * H * W + oh * W + ow] = val;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: 1x1 PW Conv -- 232->232 channels (12-bit output)         */
/* ================================================================== */
static void conv1x1_f232_fin(
    const data_t* in_flat, data_t* out_flat,
    int H, int W, const data_t* w, const data_t* b, int relu)
{
    for (int oh = 0; oh < H; oh++) {
        for (int ow = 0; ow < W; ow++) {
            data_t in_pix[232];
            for (int ic = 0; ic < 232; ic++) {
#pragma HLS UNROLL factor=4
                in_pix[ic] = in_flat[ic * H * W + oh * W + ow];
            }
            for (int oc = 0; oc < 232; oc++) {
#pragma HLS PIPELINE
                acc_t acc = 0;
                for (int ic = 0; ic < 232; ic++) {
#pragma HLS UNROLL factor=4
                    acc += (acc_t)in_pix[ic] * (acc_t)w[oc * 232 + ic];
                }
                data_t val = q_norm12(acc, b[oc]);
                if (relu && val < 0) val = 0;
                out_flat[oc * H * W + oh * W + ow] = val;
            }
        }
    }
}

/* ================================================================== */
/*  HELPER: Channel Shuffle (unchanged from Model 3)                  */
/* ================================================================== */
static void channel_shuffle_fin(data_t* fm, int C, int H, int W)
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
/*  SHUFFLE BLOCK -- STRIDE 1, Final Model (template)                  */
/*  Uses dw_conv3x3_dual (dual window) and 12-bit PW functions.       */
/* ================================================================== */
template<int C, int H, int W, int H_P, int W_P>
static void shuffle_block_s1_fin(
    data_t* sm_in, data_t* sm_out,
    const data_t* b2_pw1_w, const data_t* b2_pw1_b,
    const data_t* b2_dw_w,  const data_t* b2_dw_b,
    const data_t* b2_pw2_w, const data_t* b2_pw2_b)
{
    static const int half = C / 2;
    static const int hw   = H * W;
    static const int hw_p = H_P * W_P;

    static data_t temp_pw1   [C/2 * H * W];
    static data_t temp_dw_in [C/2 * H_P * W_P];
    static data_t temp_dw_out[C/2 * H * W];
    static data_t temp_pw2   [C/2 * H * W];
    static data_t concat      [C * H * W];
    static data_t b2_in       [C/2 * H * W];

    /* Branch A: passthrough */
    for (int c = 0; c < half; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                concat[c * hw + h * W + w_i] =
                    sm_in[IDX(c, h + 1, w_i + 1, H_P, W_P)];

    /* Branch B: collect second half */
    for (int c = 0; c < half; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                b2_in[c * hw + h * W + w_i] =
                    sm_in[IDX(half + c, h + 1, w_i + 1, H_P, W_P)];

    /* PW1: 12-bit saturation */
    if (half == 58)
        conv1x1_f58_fin(b2_in, temp_pw1, H, W, b2_pw1_w, b2_pw1_b, 1);
    else if (half == 116)
        conv1x1_f116_fin(b2_in, temp_pw1, H, W, b2_pw1_w, b2_pw1_b, 1);
    else
        conv1x1_f232_fin(b2_in, temp_pw1, H, W, b2_pw1_w, b2_pw1_b, 1);

    /* Pad PW1 output for DW input */
    for (int i = 0; i < half * H_P * W_P; i++) temp_dw_in[i] = 0;
    for (int c = 0; c < half; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                temp_dw_in[c * hw_p + (h + 1) * W_P + (w_i + 1)] =
                    temp_pw1[c * hw + h * W + w_i];

    /* DW conv: dual window, 9-bit saturation output */
    dw_conv3x3_dual(temp_dw_in, temp_dw_out, half, H_P, W_P, H, W, 1,
                    b2_dw_w, b2_dw_b);

    /* PW2: 12-bit saturation */
    if (half == 58)
        conv1x1_f58_fin(temp_dw_out, temp_pw2, H, W, b2_pw2_w, b2_pw2_b, 1);
    else if (half == 116)
        conv1x1_f116_fin(temp_dw_out, temp_pw2, H, W, b2_pw2_w, b2_pw2_b, 1);
    else
        conv1x1_f232_fin(temp_dw_out, temp_pw2, H, W, b2_pw2_w, b2_pw2_b, 1);

    /* Concatenate */
    for (int c = 0; c < half; c++)
        for (int i = 0; i < hw; i++)
            concat[(half + c) * hw + i] = temp_pw2[c * hw + i];

    channel_shuffle_fin(concat, C, H, W);

    zero_mem(sm_out, C * H_P * W_P);
    for (int c = 0; c < C; c++)
        for (int h = 0; h < H; h++)
            for (int w_i = 0; w_i < W; w_i++)
                sm_out[IDX(c, h + 1, w_i + 1, H_P, W_P)] =
                    concat[c * hw + h * W + w_i];
}

/* ================================================================== */
/*  SHUFFLE BLOCK -- STRIDE 2, Final Model (template)                  */
/*  Uses dw_conv3x3_dual and 12-bit PW functions.                     */
/* ================================================================== */
template<int IN_C, int IN_H, int IN_W, int IN_H_P, int IN_W_P,
         int OUT_C, int OUT_H, int OUT_W, int OUT_H_P, int OUT_W_P>
static void shuffle_block_s2_fin(
    data_t* sm_in, data_t* sm_out, data_t* sm_scratch,
    const data_t* b1_dw_w, const data_t* b1_dw_b,
    const data_t* b1_pw_w, const data_t* b1_pw_b,
    const data_t* b2_pw1_w, const data_t* b2_pw1_b,
    const data_t* b2_dw_w,  const data_t* b2_dw_b,
    const data_t* b2_pw2_w, const data_t* b2_pw2_b)
{
    static const int half    = OUT_C / 2;
    static const int hw_in   = IN_H  * IN_W;
    static const int hw_out  = OUT_H * OUT_W;
    static const int hw_inp  = IN_H_P * IN_W_P;
    static const int hw_op   = OUT_H_P * OUT_W_P;
    static const int in_H_P2 = IN_H + 2;
    static const int in_W_P2 = IN_W + 2;

    static data_t b1_dw_out [OUT_C/2 * OUT_H * OUT_W];
    static data_t b1_pw_out [OUT_C/2 * OUT_H * OUT_W];
    static data_t b2_in     [IN_C * IN_H * IN_W];
    static data_t b2_dw_out [OUT_C/2 * OUT_H * OUT_W];
    static data_t b2_pw2_out[OUT_C/2 * OUT_H * OUT_W];
    static data_t concat    [OUT_C * OUT_H * OUT_W];

    /* Branch 1: DW stride=2 (dual window) */
    dw_conv3x3_dual(sm_in, b1_dw_out,
                    IN_C, IN_H_P, IN_W_P, OUT_H, OUT_W, 2,
                    b1_dw_w, b1_dw_b);

    /* Branch 1: PW -> 12-bit */
    if (IN_C == 24)
        conv1x1_f24_to_58_fin(b1_dw_out, b1_pw_out, OUT_H, OUT_W, b1_pw_w, b1_pw_b, 1);
    else if (IN_C == 116)
        conv1x1_f116_fin(b1_dw_out, b1_pw_out, OUT_H, OUT_W, b1_pw_w, b1_pw_b, 1);
    else
        conv1x1_f232_fin(b1_dw_out, b1_pw_out, OUT_H, OUT_W, b1_pw_w, b1_pw_b, 1);

    /* Branch 2: extract unpadded input */
    for (int c = 0; c < IN_C; c++)
        for (int h = 0; h < IN_H; h++)
            for (int w_i = 0; w_i < IN_W; w_i++)
                b2_in[c * hw_in + h * IN_W + w_i] =
                    sm_in[IDX(c, h + 1, w_i + 1, IN_H_P, IN_W_P)];

    /* Branch 2: PW1 inlined (no DATAFLOW -- shared-memory 1P-1C violation) */
    data_t* b2_pw1_pad = sm_scratch;
    for (int i = 0; i < half * in_H_P2 * in_W_P2; i++) b2_pw1_pad[i] = 0;

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
                    data_t val = q_norm12(acc, b2_pw1_b[oc]);
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
#pragma HLS UNROLL factor=4
                        in_pix[ic] = b2_in[ic * hw_in + oh * IN_W + ow];
                    }
                    acc_t acc = 0;
                    for (int ic = 0; ic < 116; ic++) {
#pragma HLS UNROLL factor=4
                        acc += (acc_t)in_pix[ic] * (acc_t)b2_pw1_w[oc * 116 + ic];
                    }
                    data_t val = q_norm12(acc, b2_pw1_b[oc]);
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
#pragma HLS UNROLL factor=4
                        in_pix[ic] = b2_in[ic * hw_in + oh * IN_W + ow];
                    }
                    acc_t acc = 0;
                    for (int ic = 0; ic < 232; ic++) {
#pragma HLS UNROLL factor=4
                        acc += (acc_t)in_pix[ic] * (acc_t)b2_pw1_w[oc * 232 + ic];
                    }
                    data_t val = q_norm12(acc, b2_pw1_b[oc]);
                    if (val < 0) val = 0;
                    b2_pw1_pad[oc * in_H_P2 * in_W_P2
                               + (oh + 1) * in_W_P2 + (ow + 1)] = val;
                }
            }
        }
    }

    /* Branch 2: DW stride=2 (dual window) */
    dw_conv3x3_dual(b2_pw1_pad, b2_dw_out,
                    half, in_H_P2, in_W_P2, OUT_H, OUT_W, 2,
                    b2_dw_w, b2_dw_b);

    /* Branch 2: PW2 -> 12-bit */
    if (half == 58)
        conv1x1_f58_fin(b2_dw_out, b2_pw2_out, OUT_H, OUT_W, b2_pw2_w, b2_pw2_b, 1);
    else if (half == 116)
        conv1x1_f116_fin(b2_dw_out, b2_pw2_out, OUT_H, OUT_W, b2_pw2_w, b2_pw2_b, 1);
    else
        conv1x1_f232_fin(b2_dw_out, b2_pw2_out, OUT_H, OUT_W, b2_pw2_w, b2_pw2_b, 1);

    /* Concat + shuffle + write padded output */
    for (int c = 0; c < half; c++)
        for (int i = 0; i < hw_out; i++) {
            concat[c * hw_out + i]          = b1_pw_out[c * hw_out + i];
            concat[(half + c) * hw_out + i] = b2_pw2_out[c * hw_out + i];
        }
    channel_shuffle_fin(concat, OUT_C, OUT_H, OUT_W);

    zero_mem(sm_out, OUT_C * OUT_H_P * OUT_W_P);
    for (int c = 0; c < OUT_C; c++)
        for (int h = 0; h < OUT_H; h++)
            for (int w_i = 0; w_i < OUT_W; w_i++)
                sm_out[IDX(c, h + 1, w_i + 1, OUT_H_P, OUT_W_P)] =
                    concat[c * hw_out + h * OUT_W + w_i];
}

/* ================================================================== */
/*  GROUP 3: 1x1 Conv5 + Global Average Pool -- Final Model           */
/*  conv5: 464->1024, PIPELINE oc, UNROLL 464 ic, 9-bit output.       */
/*  avgpool: sum >> 2  (Sec 7.4.3.3; replaces sum*5>>8 of ~1/49).     */
/*  Output scale change compensated by FC weights/biases (see FC).    */
/* ================================================================== */
static void conv5_avgpool_final(data_t sm_in[], data_t sm_out[])
{
    static data_t c5_out[CONV5_OUT_C * CONV5_H * CONV5_W]; /* 1024*7*7 */
    static data_t c5_in [CONV5_IN_C  * CONV5_H * CONV5_W]; /* 464*7*7  */

    /* Unpad input */
    for (int c = 0; c < CONV5_IN_C; c++)
        for (int h = 0; h < CONV5_H; h++)
            for (int w_i = 0; w_i < CONV5_W; w_i++)
                c5_in[c * CONV5_H * CONV5_W + h * CONV5_W + w_i] =
                    sm_in[IDX(c, h + 1, w_i + 1, S4_OUT_H_P, S4_OUT_W_P)];

    /* 1x1 conv5: 464->1024, 9-bit output (Table 7.1: conv5=9b Q5) */
    for (int oh = 0; oh < CONV5_H; oh++) {
        for (int ow = 0; ow < CONV5_W; ow++) {
            data_t in_pix[CONV5_IN_C];
            for (int ic = 0; ic < CONV5_IN_C; ic++) {
#pragma HLS UNROLL factor=4
                in_pix[ic] = c5_in[ic * CONV5_H * CONV5_W + oh * CONV5_W + ow];
            }
            for (int oc = 0; oc < CONV5_OUT_C; oc++) {
#pragma HLS PIPELINE
                acc_t acc = 0;
                for (int ic = 0; ic < CONV5_IN_C; ic++) {
#pragma HLS UNROLL factor=4
                    acc += (acc_t)in_pix[ic] * (acc_t)conv5_w[oc * CONV5_IN_C + ic];
                }
                data_t val = q_norm9(acc, conv5_b[oc]);
                if (val < 0) val = 0;
                c5_out[oc * CONV5_H * CONV5_W + oh * CONV5_W + ow] = val;
            }
        }
    }

    /* Global avgpool: sum >> 2  (Sec 7.4.3.3)                         */
    /* Original was sum*5>>8 ~= sum/49. New: sum/4.                    */
    /* FC weights stored /49, biases /4 to compensate (see fc layer).  */
    for (int c = 0; c < CONV5_OUT_C; c++) {
        acc_t sum = 0;
        for (int h = 0; h < CONV5_H; h++)
            for (int w_i = 0; w_i < CONV5_W; w_i++) {
#pragma HLS PIPELINE
                sum += (acc_t)c5_out[c * CONV5_H * CONV5_W + h * CONV5_W + w_i];
            }
        data_t avg = q_sat9(sum >> 2);  /* divide by 4, clamp to 9-bit */
        if (avg < 0) avg = 0;
        sm_out[c] = avg;
    }
}

/* ================================================================== */
/*  GROUP 3: Fully Connected Layer + Argmax -- Final Model            */
/*  PIPELINE on neuron loop, UNROLL factor=32 (reduced from 256).    */
/*  FC weights /49, biases /4: compensate for avgpool sum>>2 change   */
/*  (original scale was sum/49, new is sum/4 -> FC sees ~12x larger   */
/*  inputs; dividing weights/49 and biases/4 re-normalises scale).    */
/*  9-bit output saturation (Table 7.1: FC=9b Q5).                    */
/* ================================================================== */
static void fc_classify_final(data_t sm4[SM4_SIZE], int* class_out)
{
#pragma HLS ARRAY_PARTITION variable=sm4 complete dim=1

    data_t max_val   = (data_t)-256;
    int    max_class = 0;

    for (int oc = 0; oc < FC_OUT; oc++) {
#pragma HLS PIPELINE
        acc_t acc = 0;
        for (int ic = 0; ic < FC_IN; ic++) {
#pragma HLS UNROLL factor=8    /* reduced from 256->32->8 -- scheduler memory ceiling on this machine */
            /* Apply /49 scale on weight to compensate avgpool scale change */
            data_t w_scaled = fc_w[oc * FC_IN + ic] / 49;
            acc += (acc_t)w_scaled * (acc_t)sm4[ic];
        }
        /* Apply /4 scale on bias (Sec 7.4.3.3) */
        data_t val = q_sat9((acc >> 8) + (acc_t)(fc_b[oc] / 4));
        if (val > max_val) {
            max_val   = val;
            max_class = oc;
        }
    }
    *class_out = max_class;
}

/* ================================================================== */
/*  TOP-LEVEL FUNCTION -- Shuffle_Model                               */
/*  Same interface as Pipeline / Parallelism Models.                  */
/*  Uses final-model optimized sub-functions throughout.              */
/* ================================================================== */
void Shuffle_Model(
    data_t sm1[SM1_SIZE],
    data_t sm2[SM2_SIZE],
    data_t sm3[SM3_SIZE],
    data_t sm4[SM4_SIZE],
    int   *class_out)
{
    /* Group 1 -- conv3x3 + quad-window maxpool */
    conv3x3_group1_fin(sm1, sm2);
    max_pool_group1_quad(sm2, sm1);

    /* Stage 2, Block 0: stride=2, 24ch@56x56 -> 116ch@28x28 */
    shuffle_block_s2_fin<S2_IN_C, MP_OUT_H, MP_OUT_W, MP_OUT_H_P, MP_OUT_W_P,
                         S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P>(
        sm1, sm2, sm3,
        s2_0_b1_dw_w, s2_0_b1_dw_b,
        s2_0_b1_pw_w, s2_0_b1_pw_b,
        s2_0_b2_pw1_w, s2_0_b2_pw1_b,
        s2_0_b2_dw_w,  s2_0_b2_dw_b,
        s2_0_b2_pw2_w, s2_0_b2_pw2_b);

    /* Stage 2, Blocks 1-3: stride=1, 116ch@28x28 */
    shuffle_block_s1_fin<S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P>(
        sm2, sm1,
        s2_1_b2_pw1_w, s2_1_b2_pw1_b, s2_1_b2_dw_w, s2_1_b2_dw_b,
        s2_1_b2_pw2_w, s2_1_b2_pw2_b);
    shuffle_block_s1_fin<S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P>(
        sm1, sm2,
        s2_2_b2_pw1_w, s2_2_b2_pw1_b, s2_2_b2_dw_w, s2_2_b2_dw_b,
        s2_2_b2_pw2_w, s2_2_b2_pw2_b);
    shuffle_block_s1_fin<S2_OUT_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P>(
        sm2, sm1,
        s2_3_b2_pw1_w, s2_3_b2_pw1_b, s2_3_b2_dw_w, s2_3_b2_dw_b,
        s2_3_b2_pw2_w, s2_3_b2_pw2_b);

    /* Stage 3, Block 0: stride=2, 116ch@28x28 -> 232ch@14x14 */
    shuffle_block_s2_fin<S3_IN_C, S2_OUT_H, S2_OUT_W, S2_OUT_H_P, S2_OUT_W_P,
                         S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm1, sm2, sm3,
        s3_0_b1_dw_w, s3_0_b1_dw_b,
        s3_0_b1_pw_w, s3_0_b1_pw_b,
        s3_0_b2_pw1_w, s3_0_b2_pw1_b,
        s3_0_b2_dw_w,  s3_0_b2_dw_b,
        s3_0_b2_pw2_w, s3_0_b2_pw2_b);

    /* Stage 3, Blocks 1-7: stride=1, 232ch@14x14 */
    shuffle_block_s1_fin<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm2, sm1,
        s3_1_b2_pw1_w, s3_1_b2_pw1_b, s3_1_b2_dw_w, s3_1_b2_dw_b,
        s3_1_b2_pw2_w, s3_1_b2_pw2_b);
    shuffle_block_s1_fin<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm1, sm2,
        s3_2_b2_pw1_w, s3_2_b2_pw1_b, s3_2_b2_dw_w, s3_2_b2_dw_b,
        s3_2_b2_pw2_w, s3_2_b2_pw2_b);
    shuffle_block_s1_fin<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm2, sm1,
        s3_3_b2_pw1_w, s3_3_b2_pw1_b, s3_3_b2_dw_w, s3_3_b2_dw_b,
        s3_3_b2_pw2_w, s3_3_b2_pw2_b);
    shuffle_block_s1_fin<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm1, sm2,
        s3_4_b2_pw1_w, s3_4_b2_pw1_b, s3_4_b2_dw_w, s3_4_b2_dw_b,
        s3_4_b2_pw2_w, s3_4_b2_pw2_b);
    shuffle_block_s1_fin<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm2, sm1,
        s3_5_b2_pw1_w, s3_5_b2_pw1_b, s3_5_b2_dw_w, s3_5_b2_dw_b,
        s3_5_b2_pw2_w, s3_5_b2_pw2_b);
    shuffle_block_s1_fin<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm1, sm2,
        s3_6_b2_pw1_w, s3_6_b2_pw1_b, s3_6_b2_dw_w, s3_6_b2_dw_b,
        s3_6_b2_pw2_w, s3_6_b2_pw2_b);
    shuffle_block_s1_fin<S3_OUT_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P>(
        sm2, sm1,
        s3_7_b2_pw1_w, s3_7_b2_pw1_b, s3_7_b2_dw_w, s3_7_b2_dw_b,
        s3_7_b2_pw2_w, s3_7_b2_pw2_b);

    /* Stage 4, Block 0: stride=2, 232ch@14x14 -> 464ch@7x7 */
    shuffle_block_s2_fin<S4_IN_C, S3_OUT_H, S3_OUT_W, S3_OUT_H_P, S3_OUT_W_P,
                         S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P>(
        sm1, sm2, sm3,
        s4_0_b1_dw_w, s4_0_b1_dw_b,
        s4_0_b1_pw_w, s4_0_b1_pw_b,
        s4_0_b2_pw1_w, s4_0_b2_pw1_b,
        s4_0_b2_dw_w,  s4_0_b2_dw_b,
        s4_0_b2_pw2_w, s4_0_b2_pw2_b);

    /* Stage 4, Blocks 1-3: stride=1, 464ch@7x7 */
    shuffle_block_s1_fin<S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P>(
        sm2, sm1,
        s4_1_b2_pw1_w, s4_1_b2_pw1_b, s4_1_b2_dw_w, s4_1_b2_dw_b,
        s4_1_b2_pw2_w, s4_1_b2_pw2_b);
    shuffle_block_s1_fin<S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P>(
        sm1, sm2,
        s4_2_b2_pw1_w, s4_2_b2_pw1_b, s4_2_b2_dw_w, s4_2_b2_dw_b,
        s4_2_b2_pw2_w, s4_2_b2_pw2_b);
    shuffle_block_s1_fin<S4_OUT_C, S4_OUT_H, S4_OUT_W, S4_OUT_H_P, S4_OUT_W_P>(
        sm2, sm1,
        s4_3_b2_pw1_w, s4_3_b2_pw1_b, s4_3_b2_dw_w, s4_3_b2_dw_b,
        s4_3_b2_pw2_w, s4_3_b2_pw2_b);

    /* Group 3 */
    conv5_avgpool_final(sm1, sm4);
    fc_classify_final(sm4, class_out);
}
