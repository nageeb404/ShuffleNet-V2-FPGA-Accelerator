/*
 * shufflenet_hls.h -- ShuffleNet V2 x1.0 Vitis HLS implementation header
 *
 * Thesis Chapter 7: High Level Synthesis (HLS)
 * Tool:    Vitis HLS 2024.2
 * Target:  Xilinx Virtex-7 XC7VX690T-2FFG1761C (VC709)
 * Clock:   100 MHz
 *
 * Data type: short int (16-bit, represents Q6.8 fixed-point)
 *   - Stored integer = real_value * 2^8 = real_value * 256
 *   - Range: [-16384, 16383] = [-64.0, 63.996]
 *
 * Architecture (full PW->DW->PW, matching the Python software model):
 *   SM1 (photo/feature map) -> conv3x3 -> SM2 -> maxpool -> SM1
 *   -> 16 shuffle blocks (alternating SM1/SM2) -> conv5 -> SM3
 *   -> avgpool -> SM4 -> FC -> class_out
 *
 * Memory layout: channel-major [C][H_PAD][W_PAD], flattened to 1D.
 * Padding convention: output of each function is stored in SM with
 * a 1-pixel zero border so the next layer reads a pre-padded input.
 * (Thesis Sec 7.2.3.2: "padding is coded to be done on the output")
 */
#pragma once
#include <stdint.h>

/* ------------------------------------------------------------------ */
/*  Data types                                                         */
/* ------------------------------------------------------------------ */
typedef short int  data_t;   /* Q6.8 stored value (16-bit signed)    */
typedef long long  acc_t;    /* Accumulator -- 64-bit to avoid OVF   */
                             /* over 1024 MACs of 16-bit * 16-bit     */

/* ------------------------------------------------------------------ */
/*  Q6.8 arithmetic helpers                                            */
/* ------------------------------------------------------------------ */
/* Saturating clamp to 15-bit signed range [-16384, 16383] */
static inline data_t q_sat(acc_t x)
{
    if (x >  16383LL) return  16383;
    if (x < -16384LL) return (data_t)-16384;
    return (data_t)x;
}

/*
 * After accumulating N products of (Q6.8 * Q6.8) as 64-bit integers,
 * the sum is in Q12.16 scale (16 fraction bits).  Shift right 8 to
 * convert to Q6.8, then add the Q6.8 bias.
 * This matches the Python model's (acc >> 8) + bias approach.
 */
static inline data_t q_norm(acc_t acc, data_t bias)
{
    acc_t result = (acc >> 8) + (acc_t)bias;
    return q_sat(result);
}

/* ReLU applied to a Q6.8 value */
static inline data_t q_relu(data_t x) { return (x < 0) ? 0 : x; }

/* ------------------------------------------------------------------ */
/*  Memory index helper: channel-major [ch][row][col] -> flat index   */
/* ------------------------------------------------------------------ */
#define IDX(ch, row, col, H_P, W_P) \
    ((int)(ch) * (int)(H_P) * (int)(W_P) + (int)(row) * (int)(W_P) + (int)(col))

/* ------------------------------------------------------------------ */
/*  Shared-memory (SM) sizes (Thesis Sec 7.2.2 "Second Model")        */
/*                                                                     */
/*  SM1: photo padded (226*226*3=153,468) OR later feature maps       */
/*       max reuse: maxpool-out padded (58*58*24=81,096)              */
/*       and Group-2 stride-1 outputs (30*30*116=104,400)             */
/*  SM2: conv1 output padded (114*114*24=311,904) OR Group-2 outputs  */
/*  SM3: scratch for stride-2 block PW1 padded intermediate           */
/*       Written as padded layout: half * (in_H+2) * (in_W+2)        */
/*       Max: stage-2 b0: 58*58*58=195,284                            */
/*       Reused (sequential) for conv5 output (7*7*1024=50,176)       */
/*  SM4: avgpool output / FC input (1024 values)                      */
/* ------------------------------------------------------------------ */
#define SM1_SIZE  160000
#define SM2_SIZE  320000
#define SM3_SIZE  200000
#define SM4_SIZE  1024

/* ------------------------------------------------------------------ */
/*  Architecture constants                                             */
/* ------------------------------------------------------------------ */
/* Group 1 */
#define CONV1_IN_C    3
#define CONV1_IN_H    224
#define CONV1_IN_W    224
#define CONV1_IN_H_P  226    /* padded input (1 pixel border) */
#define CONV1_IN_W_P  226
#define CONV1_OUT_C   24
#define CONV1_OUT_H   112
#define CONV1_OUT_W   112
#define CONV1_OUT_H_P 114    /* padded output */
#define CONV1_OUT_W_P 114

#define MP_OUT_H   56
#define MP_OUT_W   56
#define MP_OUT_H_P 58
#define MP_OUT_W_P 58

/* Stage 2 (stride-2 block: in=24ch -> out=116ch -> 28x28) */
#define S2_IN_C    24
#define S2_OUT_C   116
#define S2_HALF    58        /* 116/2 per branch */
#define S2_OUT_H   28
#define S2_OUT_W   28
#define S2_OUT_H_P 30        /* padded stage-2 output */
#define S2_OUT_W_P 30

/* Stage 3 (stride-2 block: in=116ch -> out=232ch -> 14x14) */
#define S3_IN_C    116
#define S3_OUT_C   232
#define S3_HALF    116
#define S3_OUT_H   14
#define S3_OUT_W   14
#define S3_OUT_H_P 16
#define S3_OUT_W_P 16

/* Stage 4 (stride-2 block: in=232ch -> out=464ch -> 7x7) */
#define S4_IN_C    232
#define S4_OUT_C   464
#define S4_HALF    232
#define S4_OUT_H   7
#define S4_OUT_W   7
#define S4_OUT_H_P 9
#define S4_OUT_W_P 9

/* Group 3 */
#define CONV5_IN_C  464
#define CONV5_OUT_C 1024
#define CONV5_H     7
#define CONV5_W     7

#define FC_IN    1024
#define FC_OUT   1000
#define AVG_WIN  49          /* 7*7 pixels per channel for avg pool */

/* ------------------------------------------------------------------ */
/*  Top-level function declaration (synthesised by Vitis HLS)         */
/* ------------------------------------------------------------------ */
void Shuffle_Model(
    data_t sm1[SM1_SIZE],   /* photo in / feature-map ping-pong buffer A */
    data_t sm2[SM2_SIZE],   /* feature-map ping-pong buffer B            */
    data_t sm3[SM3_SIZE],   /* scratch / conv5 output                    */
    data_t sm4[SM4_SIZE],   /* avgpool output / FC input                 */
    int   *class_out         /* predicted ImageNet class index            */
);
