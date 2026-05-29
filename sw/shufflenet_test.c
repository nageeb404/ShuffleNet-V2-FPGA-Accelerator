/*
 * shufflenet_test.c  --  PS bare-metal / Linux test for ShuffleNet FPGA accelerator
 *
 * Runs on the ARM Cortex-A53 of the iWave ZU19EG.
 * Maps the AXI slave at 0xA0000000 via /dev/mem (Linux) or direct pointer (bare-metal).
 *
 * AXI memory map (byte offsets from 0xA0000000):
 *   Pixel write region  (AWADDR[21]=0):
 *     AWADDR[20]    = pm_mem_select  (0=ping, 1=pong)
 *     AWADDR[19:18] = channel        (0=R, 1=G, 2=B)
 *     AWADDR[17:2]  = pixel index    (0..50175 = 224*224-1)
 *     WDATA[7:0]    = pixel value    (0..255)
 *
 *   CSR register        (AWADDR[21]=1, i.e. byte offset 0x200000):
 *     Write WDATA[0]=1  -> assert photo_ready (trigger inference)
 *     Write WDATA[0]=0  -> clear  photo_ready
 *     Read  RDATA[0]    = photo_ready
 *     Read  RDATA[1]    = busy (1 while inference running)
 *     Read  RDATA[2]    = classification_done (latched until read)
 *     Read  RDATA[12:3] = class_idx[9:0]  (top-1 class, 0..999)
 *
 * USAGE (Linux, run as root):
 *   gcc -O2 -o shufflenet_test shufflenet_test.c
 *   ./shufflenet_test <image.bin>
 *
 * image.bin format: 224*224*3 bytes, R-plane then G-plane then B-plane,
 *   values 0..255.  Generate with:
 *     python scripts/gen_test_image.py --image /path/img.jpg --out image.bin
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <time.h>

#define BASE_ADDR    0xA0000000UL
#define MAP_SIZE     (32 * 1024 * 1024)   /* 32 MB */
#define IMG_PIXELS   (224 * 224)
#define IMG_CHANNELS 3

/* CSR byte offset from base */
#define CSR_OFFSET   0x200000

/* Pixel write address: AWADDR bits [20:2] encode (mem_select, channel, pixel) */
static inline uint32_t pixel_addr(int chan, int pix, int mem_sel)
{
    /* AWADDR[17:2] = pix, [19:18] = chan, [20] = mem_sel, [21] = 0 (pixel region) */
    return (uint32_t)(((mem_sel & 1) << 20) | ((chan & 3) << 18) | ((pix & 0x3FFF) << 2));
}

int main(int argc, char *argv[])
{
    const char *imgfile = (argc > 1) ? argv[1] : "image.bin";

    /* ----- Load image ----- */
    FILE *f = fopen(imgfile, "rb");
    if (!f) { perror("fopen image"); return 1; }
    uint8_t *img = malloc(IMG_PIXELS * IMG_CHANNELS);
    if (!img) { perror("malloc"); return 1; }
    size_t n = fread(img, 1, IMG_PIXELS * IMG_CHANNELS, f);
    fclose(f);
    if (n != IMG_PIXELS * IMG_CHANNELS) {
        fprintf(stderr, "ERROR: expected %d bytes, got %zu\n",
                IMG_PIXELS * IMG_CHANNELS, n);
        return 1;
    }
    printf("Image loaded: %s (%d pixels x 3 channels)\n", imgfile, IMG_PIXELS);

    /* ----- Map AXI slave via /dev/mem ----- */
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open /dev/mem"); return 1; }

    volatile uint32_t *base = mmap(NULL, MAP_SIZE,
                                   PROT_READ | PROT_WRITE,
                                   MAP_SHARED, fd, BASE_ADDR);
    if (base == MAP_FAILED) { perror("mmap"); return 1; }

    volatile uint32_t *csr = (volatile uint32_t *)((uint8_t *)base + CSR_OFFSET);

    /* ----- Write image pixels via AXI ----- */
    printf("Writing image to photo memory (ping buffer, mem_select=0)...\n");
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    for (int c = 0; c < IMG_CHANNELS; c++) {
        for (int p = 0; p < IMG_PIXELS; p++) {
            uint32_t addr_offset = pixel_addr(c, p, 0) / 4; /* word index */
            base[addr_offset] = (uint32_t)img[c * IMG_PIXELS + p];
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double load_ms = (t1.tv_sec - t0.tv_sec) * 1e3 +
                     (t1.tv_nsec - t0.tv_nsec) * 1e-6;
    printf("Image write done in %.1f ms\n", load_ms);

    /* ----- Trigger inference ----- */
    printf("Triggering inference (photo_ready=1)...\n");
    clock_gettime(CLOCK_MONOTONIC, &t0);
    *csr = 1;  /* photo_ready = 1 */

    /* ----- Poll until done ----- */
    uint32_t csr_val;
    int timeout = 10000;  /* 10 seconds at 1ms poll */
    do {
        usleep(1000);
        csr_val = *csr;
        timeout--;
    } while (!(csr_val & 0x4) && timeout > 0);  /* wait for classification_done bit */

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double infer_ms = (t1.tv_sec - t0.tv_sec) * 1e3 +
                      (t1.tv_nsec - t0.tv_nsec) * 1e-6;

    if (timeout == 0) {
        fprintf(stderr, "ERROR: inference timeout (CSR=0x%08X)\n", csr_val);
        *csr = 0;
        return 1;
    }

    /* ----- Read result ----- */
    uint32_t class_idx = (csr_val >> 3) & 0x3FF;
    printf("\n=== RESULT ===\n");
    printf("  class_idx       : %u\n", class_idx);
    printf("  inference time  : %.1f ms\n", infer_ms);
    printf("  CSR value       : 0x%08X\n", csr_val);
    printf("==============\n");

    /* ----- Clear photo_ready ----- */
    *csr = 0;

    munmap((void *)base, MAP_SIZE);
    close(fd);
    free(img);
    return 0;
}
