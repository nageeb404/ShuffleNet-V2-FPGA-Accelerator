/******************************************************************************
 * ShuffleNet V2 FPGA Accelerator — Bare-Metal Test
 *
 * Target  : Zynq UltraScale+ ZU19EG, Cortex-A53 (standalone / no OS)
 * Toolchain: Vitis / Xilinx SDK (import shufflenet.xsa, domain psu_cortexa53_0)
 *
 * Flow:
 *   1. Program bitstream via Vitis (Xilinx -> Program Device)
 *   2. Run this application in debug mode
 *   3. When UART prints the upload prompt, load image.bin via XSCT:
 *        xsct> source load_image.tcl
 *   4. Press ENTER on the UART terminal
 *   5. Read class_idx and inference time from UART output
 *
 * Hardware map (see hw_config.h):
 *   FPGA AXI base : 0xA0000000   (pixel writes, addressed by bit encoding)
 *   FPGA CSR      : 0xA0200000   (start inference, read result)
 *   DDR image buf : 0x10000000   (image.bin loaded here by XSCT)
 ******************************************************************************/

#include "platform.h"
#include "hw_config.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_types.h"
#include "xtime_l.h"

/* CSR bit masks */
#define CSR_PHOTO_READY_BIT   0x1U
#define CSR_BUSY_BIT          0x2U
#define CSR_DONE_BIT          0x4U
#define CSR_CLASS_MASK        0x1FF8U   /* bits 12:3 */
#define CSR_CLASS_SHIFT       3U

/* -------------------------------------------------------------------------
 * pixel_addr: build AXI byte offset for a pixel write
 *
 *   mem_sel : 0 = ping buffer, 1 = pong buffer        (address bit 20)
 *   ch      : 0 = R, 1 = G, 2 = B                     (address bits 19:18)
 *   px      : pixel index 0 .. IMG_PIXELS-1            (address bits 17:2)
 * ------------------------------------------------------------------------- */
static u32 pixel_addr(u32 ch, u32 px, u32 mem_sel)
{
    return (mem_sel << 20) | (ch << 18) | (px << 2);
}

/* -------------------------------------------------------------------------
 * wait_for_image: pause execution and print XSCT instructions on UART.
 * The user must load image.bin into DDR_IMAGE_BASE before pressing ENTER.
 * ------------------------------------------------------------------------- */
static void wait_for_image(void)
{
    char c;

    xil_printf("\r\n=== Image upload required (XSCT) ===\r\n");
    xil_printf("Load image.bin into DDR memory before continuing.\r\n");
    xil_printf("  Target address : 0x%08X\r\n", DDR_IMAGE_BASE);
    xil_printf("  Size           : %u bytes  (%u channels x %u pixels)\r\n",
               IMG_BYTES, IMG_CHANNELS, IMG_PIXELS);
    xil_printf("\r\n");
    xil_printf("  Steps in XSCT:\r\n");
    xil_printf("    xsct> connect\r\n");
    xil_printf("    xsct> targets -set -filter {name =~ \"Cortex-A53 #0\"}\r\n");
    xil_printf("    xsct> source load_image.tcl\r\n");
    xil_printf("\r\n");
    xil_printf("Press ENTER in this UART window when upload is complete...\r\n");

    do {
        c = inbyte();
    } while (c != '\r' && c != '\n');

    /*
     * Invalidate the D-cache for the image buffer region.
     * dow -data writes via JTAG directly to DDR — the CPU cache
     * may hold stale zeros. Invalidate before we read any pixel.
     */
    Xil_DCacheInvalidateRange(DDR_IMAGE_BASE, IMG_BYTES);

    /* Sanity check: first byte should be non-zero for a real photo */
    u8 first_byte = *(volatile u8 *)DDR_IMAGE_BASE;
    xil_printf("DDR[0] = 0x%02X  (first R-channel pixel)\r\n", first_byte);
    if (first_byte == 0U) {
        xil_printf("WARNING: first byte is 0 -- image may not be loaded.\r\n");
        xil_printf("         Re-run load_image.tcl in XSCT and try again.\r\n");
    }
}

/* -------------------------------------------------------------------------
 * write_image_to_fpga: push all 150,528 pixel bytes into FPGA photo memory
 *   via AXI4-Lite, one 32-bit write per pixel.
 *   Returns elapsed time in microseconds.
 * ------------------------------------------------------------------------- */
static u64 write_image_to_fpga(void)
{
    volatile u8 *img = (volatile u8 *)DDR_IMAGE_BASE;
    XTime t0, t1;
    u32 ch, px;

    xil_printf("Writing image to FPGA photo memory (ping buffer)...\r\n");
    XTime_GetTime(&t0);

    for (ch = 0U; ch < IMG_CHANNELS; ch++) {
        for (px = 0U; px < IMG_PIXELS; px++) {
            u32 offset = pixel_addr(ch, px, 0U);       /* ping buffer */
            u32 value  = img[ch * IMG_PIXELS + px];    /* 0..255 */
            Xil_Out32(SHUFFLENET_AXI_BASE + offset, value);
        }
    }

    XTime_GetTime(&t1);
    return ((u64)(t1 - t0) * 1000000ULL) / (u64)COUNTS_PER_SECOND;
}

/* -------------------------------------------------------------------------
 * run_inference: write CSR=1 to start, poll bit 2 until done or timeout.
 *   Returns elapsed inference time in microseconds, or 0 on timeout.
 * ------------------------------------------------------------------------- */
static u64 run_inference(u32 *csr_out)
{
    XTime t0, t_now;
    u32 csr_val = 0U;
    u64 timeout_ticks = (u64)INFER_TIMEOUT_MS * (u64)COUNTS_PER_SECOND / 1000ULL;

    /* Assert photo_ready to start the accelerator */
    Xil_Out32(SHUFFLENET_CSR_ADDR, CSR_PHOTO_READY_BIT);
    XTime_GetTime(&t0);

    /* Poll classification_done (bit 2) */
    do {
        csr_val = Xil_In32(SHUFFLENET_CSR_ADDR);
        XTime_GetTime(&t_now);
    } while (!(csr_val & CSR_DONE_BIT) &&
             ((t_now - t0) < timeout_ticks));

    *csr_out = csr_val;

    if (!(csr_val & CSR_DONE_BIT)) {
        return 0ULL;    /* timeout */
    }

    return ((u64)(t_now - t0) * 1000000ULL) / (u64)COUNTS_PER_SECOND;
}

/* -------------------------------------------------------------------------
 * main
 * ------------------------------------------------------------------------- */
int main(void)
{
    u32 csr_val;
    u64 write_us, infer_us;

    init_platform();

    xil_printf("\r\nShuffleNet V2 Bare-Metal Test\r\n");
    xil_printf("  FPGA AXI base : 0x%08X\r\n", SHUFFLENET_AXI_BASE);
    xil_printf("  FPGA CSR addr : 0x%08X\r\n", SHUFFLENET_CSR_ADDR);
    xil_printf("  DDR image buf : 0x%08X\r\n", DDR_IMAGE_BASE);
    xil_printf("  Image size    : %u x %u x %u = %u bytes\r\n",
               IMG_WIDTH, IMG_HEIGHT, IMG_CHANNELS, IMG_BYTES);

    /* Step 1: wait for user to load image via XSCT */
    wait_for_image();

    /* Step 2: write all pixels to FPGA over AXI */
    write_us = write_image_to_fpga();
    xil_printf("Image write done in %llu us  (%llu.%03llu ms)\r\n",
               (unsigned long long)write_us,
               (unsigned long long)(write_us / 1000ULL),
               (unsigned long long)(write_us % 1000ULL));

    /* Step 3: trigger inference and wait for result */
    xil_printf("Triggering inference (photo_ready = 1)...\r\n");
    infer_us = run_inference(&csr_val);

    /* Step 4: print result */
    if (infer_us == 0ULL) {
        xil_printf("ERROR: inference timeout  (CSR = 0x%08X)\r\n", csr_val);
        xil_printf("  Check: DONE LED on board, FPGA programmed correctly?\r\n");
    } else {
        u32 class_idx = (csr_val & CSR_CLASS_MASK) >> CSR_CLASS_SHIFT;

        xil_printf("\r\n=== RESULT ===\r\n");
        xil_printf("  class_idx      : %u\r\n",  class_idx);
        xil_printf("  inference time : %llu us  (%llu.%03llu ms)\r\n",
                   (unsigned long long)infer_us,
                   (unsigned long long)(infer_us / 1000ULL),
                   (unsigned long long)(infer_us % 1000ULL));
        xil_printf("  CSR value      : 0x%08X\r\n", csr_val);
        xil_printf("==============\r\n");
    }

    /* Step 5: clear photo_ready */
    Xil_Out32(SHUFFLENET_CSR_ADDR, 0U);

    cleanup_platform();
    return 0;
}
