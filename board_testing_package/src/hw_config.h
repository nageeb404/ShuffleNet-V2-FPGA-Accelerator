/******************************************************************************
 * Hardware address map for ShuffleNet V2 bare-metal test.
 *
 * After importing shufflenet.xsa into Vitis and building the BSP,
 * xparameters.h is generated automatically with the correct values.
 * The fallbacks below match the block design address assignment and keep
 * the application buildable before the BSP is regenerated.
 ******************************************************************************/

#ifndef HW_CONFIG_H
#define HW_CONFIG_H

#include "xparameters.h"

/*
 * ShuffleNet AXI4-Lite slave base address (from block design address editor).
 * Pixel writes : base + pixel_addr(ch, px, mem_sel)
 * CSR          : base + 0x200000
 */
#ifdef XPAR_SHUFFLENET_BOARD_TOP_0_BASEADDR
#define SHUFFLENET_AXI_BASE   XPAR_SHUFFLENET_BOARD_TOP_0_BASEADDR
#else
#define SHUFFLENET_AXI_BASE   0xA0000000UL
#endif

/* CSR offset: AWADDR bit 21 = 1  ->  offset 0x200000 */
#define SHUFFLENET_CSR_ADDR   (SHUFFLENET_AXI_BASE + 0x200000UL)

/* DDR buffer where XSCT loads image.bin (must be in PS DDR, cache-line aligned) */
#define DDR_IMAGE_BASE        0x10000000UL

/* Image dimensions */
#define IMG_WIDTH             224U
#define IMG_HEIGHT            224U
#define IMG_CHANNELS          3U
#define IMG_PIXELS            (IMG_WIDTH * IMG_HEIGHT)      /* 50176 */
#define IMG_BYTES             (IMG_PIXELS * IMG_CHANNELS)   /* 150528 */

/* Inference timeout in milliseconds */
#define INFER_TIMEOUT_MS      10000U

#endif /* HW_CONFIG_H */
