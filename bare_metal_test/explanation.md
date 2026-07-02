# Bare-Metal Board Test — File Explanations
## ShuffleNet V2 FPGA Accelerator — ZU19EG

All files are in `N:\GP\bare_metal_test\`

---

## How the 4 Files Work Together

```
On your PC:
  gen_test_image_baremetal.py  ──→  image.bin  (150,528 bytes)
                                    image.coe  (37,632 hex words)

On your PC (XSCT debugger window):
  load_image.tcl  ──→  writes image.bin into DDR at 0x10000000 via JTAG

On Vitis IDE (compile and run on board):
  hw_config.h  +  shufflenet_test_baremetal.c  ──→  compiled .elf  ──→  runs on ARM
```

The ARM C program starts, waits for you to load the image via XSCT, then writes it to
the FPGA, triggers inference, and prints the result on the UART terminal.

---

# FILE 1: `gen_test_image_baremetal.py`
## The Image Preprocessor (runs on your PC)

### Where it lives
```
N:\GP\bare_metal_test\gen_test_image_baremetal.py
```

### What it does
Same job as the PetaLinux version (`sw/gen_test_image.py`) — takes any photo and
converts it to the exact format the FPGA hardware expects. The difference is it outputs
TWO files instead of one.

### How to run it
```
pip install pillow numpy
python gen_test_image_baremetal.py --image C:\path\to\photo.jpg --out image
```

This creates:
- `image.bin` — 150,528 raw bytes, used by `load_image.tcl` with `dow -data`
- `image.coe` — 37,632 hex words, alternative format for manual `mwr` loading

### Step-by-step what happens inside

**Step 1 — Resize and crop (same as PetaLinux version)**
- Resize the shortest side to 256 pixels
- Center-crop to exactly 224×224
- Result: 224×224 array with RGB values 0–255

**Step 2 — Convert to planar format**
Normal images have pixels interleaved: `[R,G,B][R,G,B][R,G,B]...`
The FPGA needs planar: all R first, then all G, then all B:
```python
planar = [R0, R1, R2, ..., R50175, G0, G1, ..., G50175, B0, B1, ..., B50175]
```
Total: 50,176 × 3 = 150,528 bytes.

**Step 3 — Write image.bin**
Raw bytes written directly. This is the file XSCT's `dow -data` command will load
into DDR memory — the bytes end up at DDR addresses sequentially.

**Step 4 — Write image.coe**
The same 150,528 bytes, but packed 4 bytes per 32-bit word (little-endian):
```
word[0] = R[0] | (R[1]<<8) | (R[2]<<16) | (R[3]<<24)
word[1] = R[4] | (R[5]<<8) | (R[6]<<16) | (R[7]<<24)
...
```
Written in Xilinx COE format:
```
memory_initialization_radix=16;
memory_initialization_vector=
R3R2R1R0,
R7R6R5R4,
...
```
This format is used by the `mwr` loop in `load_image.tcl` (the slower alternative method).

---

# FILE 2: `load_image.tcl`
## The XSCT Image Loader (runs in the Xilinx debugger)

### Where it lives
```
N:\GP\bare_metal_test\load_image.tcl
```

### What is XSCT?
XSCT (Xilinx Software Command-line Tool) is a TCL-based debugger that comes with Vitis.
It connects to the board over the JTAG cable and can read/write any memory address on
the board directly — bypassing the processor completely.

Think of it like a remote control for the board's memory. You can write data anywhere,
read it back, even run code — all over the USB JTAG cable.

### How to use it

Open XSCT (from Vitis: `Xilinx → XSCT Console`) while the bare-metal program is
paused waiting at the UART prompt, then type:

```tcl
connect
targets -set -filter {name =~ "Cortex-A53 #0"}
source N:/GP/bare_metal_test/load_image.tcl
```

### Step-by-step what happens inside

**Step 1 — Find image.bin**
The script looks for `image.bin` in the same folder as itself.
You can override it: `set ::image_bin "C:/other/path/image.bin"`

**Step 2 — Validate file size**
Checks that `image.bin` is exactly 150,528 bytes. If not, stops with an error.
This prevents accidentally loading the wrong file.

**Step 3 — `dow -data image.bin 0x10000000`**
This is the key command. `dow` (download) with the `-data` flag loads a raw binary
file directly into board memory over JTAG in a single bulk transfer.

After this command, DDR address `0x10000000` contains:
- `0x10000000` → R channel pixel 0
- `0x10000001` → R channel pixel 1
- ...
- `0x1000C3FF` → R channel pixel 50175
- `0x1000C400` → G channel pixel 0
- ...
- `0x100249FF` → B channel pixel 50175

**Step 4 — Verify**
Reads back the first 8 bytes from DDR and prints them so you can confirm the data
arrived correctly.

**Step 5 — Return to UART terminal and press ENTER**
After the script finishes, go back to the serial terminal and press Enter.
The bare-metal program continues.

### Why `dow -data` instead of `mwr`?
The reference repo (`Accelerator-HW-TB-main`) uses individual `mwr` calls (one per
32-bit word) because their stimulus is only 256 words (1 KB). Our image is 37,632 words
(147 KB) — 37,632 individual `mwr` calls over JTAG would take several minutes.

`dow -data` transfers the entire file in one bulk JTAG operation, taking a few seconds.

The `mwr` approach is provided as commented code at the bottom of the script in case
your XSCT version does not support `dow -data`.

---

# FILE 3: `hw_config.h`
## The Hardware Address Header

### Where it lives
```
N:\GP\bare_metal_test\hw_config.h
```

### What it does
Defines all the hardware addresses in one place. Follows the same pattern as the
reference repo's `hw_config.h`.

When you import `shufflenet.xsa` into Vitis and build the BSP, Vitis automatically
generates a file called `xparameters.h` that contains the real address values read
from the hardware description. This header checks for those auto-generated names first
and falls back to hardcoded values if the BSP has not been built yet.

### The addresses defined

| Constant | Value | What it points to |
|---|---|---|
| `SHUFFLENET_AXI_BASE` | `0xA0000000` | Start of FPGA AXI window — pixel writes go here |
| `SHUFFLENET_CSR_ADDR` | `0xA0200000` | Control/Status Register — start inference and read result |
| `DDR_IMAGE_BASE` | `0x10000000` | Where XSCT loads image.bin in DDR |
| `IMG_PIXELS` | 50176 | 224 × 224 |
| `IMG_BYTES` | 150528 | 50176 × 3 channels |
| `INFER_TIMEOUT_MS` | 10000 | Give up after 10 seconds if no result |

---

# FILE 4: `shufflenet_test_baremetal.c`
## The Bare-Metal ARM Program

### Where it lives
```
N:\GP\bare_metal_test\shufflenet_test_baremetal.c
```

### How to build and run it in Vitis

1. `File → New → Platform Project`
   - Import hardware: `N:\GP\shufflenet_v2_fpga\vivado\shufflenet.xsa`
   - Domain: `psu_cortexa53_0` (the Cortex-A53 core)
   - Build the platform

2. `File → New → Application Project`
   - Template: Empty Application
   - Copy `shufflenet_test_baremetal.c` and `hw_config.h` into the `src/` folder

3. Build → produces `shufflenet_test_baremetal.elf`

4. `Xilinx → Program Device` → select the `.bit` file → Program

5. `Run → Debug Configurations → Single Application Debug` → run the `.elf`

6. Open serial terminal (PuTTY, 115200 baud) on the board's UART COM port

### What the program outputs on UART

At startup:
```
ShuffleNet V2 Bare-Metal Test
  FPGA AXI base : 0xA0000000
  FPGA CSR addr : 0xA0200000
  DDR image buf : 0x10000000
  Image size    : 224 x 224 x 3 = 150528 bytes

=== Image upload required (XSCT) ===
Load image.bin into DDR memory before continuing.
  Target address : 0x10000000
  ...
Press ENTER in this UART window when upload is complete...
```

After ENTER is pressed:
```
DDR[0] = 0x80  (first R-channel pixel)
Writing image to FPGA photo memory (ping buffer)...
Image write done in 3200 us  (3.200 ms)
Triggering inference (photo_ready = 1)...

=== RESULT ===
  class_idx      : 207
  inference time : 1023 us  (1.023 ms)
  CSR value      : 0x000041C
==============
```

### Step-by-step walkthrough of the code

**Step 1 — `init_platform()` (Xilinx BSP)**
Initializes the UART, cache, and other BSP peripherals. Must be called first.

---

**Step 2 — `wait_for_image()` (lines ~52–85)**

Prints the XSCT instructions on the UART terminal, then blocks waiting for the user
to press Enter:
```c
do {
    c = inbyte();   /* inbyte() reads one character from UART */
} while (c != '\r' && c != '\n');
```

After Enter is pressed, the critical step happens:
```c
Xil_DCacheInvalidateRange(DDR_IMAGE_BASE, IMG_BYTES);
```

**Why is this needed?** The ARM processor has a data cache. When XSCT's `dow -data`
writes `image.bin` into DDR, it writes directly via JTAG — bypassing the CPU cache.
The cache still holds zeros (its old state). If we read from DDR now, the CPU would
read from cache and get zeros — not the image. `Xil_DCacheInvalidateRange` tells the
cache "forget everything you think you know about this memory region, force a fresh read
from DDR." After this, the pixel reads will return the real image data.

---

**Step 3 — `write_image_to_fpga()` (lines ~88–113)**

Loops over all 150,528 pixels and writes each to the FPGA:

```c
for (ch = 0; ch < 3; ch++) {
    for (px = 0; px < 50176; px++) {
        u32 offset = pixel_addr(ch, px, 0);
        u32 value  = img[ch * 50176 + px];
        Xil_Out32(SHUFFLENET_AXI_BASE + offset, value);
    }
}
```

`Xil_Out32(address, value)` is the bare-metal equivalent of writing to a memory address.
In PetaLinux we used `base[offset/4] = value`. Both do exactly the same thing — a
32-bit write to a physical address. The AXI bus carries it to the FPGA.

`pixel_addr(ch, px, 0)` builds the byte offset where bits encode:
- bit 20 = 0 (ping buffer)
- bits 19:18 = ch (00=R, 01=G, 10=B)
- bits 17:2 = px (pixel index)

Timing is measured using `XTime_GetTime()` — the ARM's internal hardware timer.
`COUNTS_PER_SECOND` is defined by the BSP (how many timer ticks per second).

---

**Step 4 — `run_inference()` (lines ~116–143)**

Writes 1 to the CSR to start the accelerator:
```c
Xil_Out32(SHUFFLENET_CSR_ADDR, CSR_PHOTO_READY_BIT);  /* CSR = 1 */
```

Then polls bit 2 (classification_done) in a tight loop:
```c
do {
    csr_val = Xil_In32(SHUFFLENET_CSR_ADDR);
    XTime_GetTime(&t_now);
} while (!(csr_val & CSR_DONE_BIT) && not_timed_out);
```

`Xil_In32(address)` reads a 32-bit value from the physical address — the FPGA's CSR
register value comes back here. Bit 2 = 1 means the accelerator finished.

Unlike the PetaLinux version which sleeps 1 ms between polls, this bare-metal version
polls as fast as possible — no OS sleep functions. This is why the bare-metal timing
measurement is more precise.

---

**Step 5 — Print result (lines ~146–163)**

```c
u32 class_idx = (csr_val & CSR_CLASS_MASK) >> CSR_CLASS_SHIFT;
```

Extracts bits 12:3 from the CSR — the 10-bit class index (0 to 999).

`CSR_CLASS_MASK = 0x1FF8` = binary `0001 1111 1111 1000` — masks bits 12:3.
`>> 3` shifts right to move the class index into bits 9:0.

---

**Step 6 — Cleanup**
Writes 0 to CSR to clear `photo_ready`, then calls `cleanup_platform()`.

---

## Differences from the PetaLinux Version

| | PetaLinux (`shufflenet_test.c`) | Bare-Metal (`shufflenet_test_baremetal.c`) |
|---|---|---|
| Access to FPGA | `/dev/mem` + `mmap()` | `Xil_Out32()` / `Xil_In32()` direct |
| Image loading | `fopen("image.bin")` from SD card | XSCT `dow -data` into DDR |
| Read image from | SD card file | DDR at `0x10000000` |
| Cache management | Linux handles it | Manual `Xil_DCacheInvalidateRange` |
| Timing | `clock_gettime()` (Linux) | `XTime_GetTime()` (BSP timer) |
| Poll delay | `usleep(1000)` — 1 ms sleep | Tight loop — polls as fast as possible |
| Print | `printf()` | `xil_printf()` |
| OS | Linux | None |

The pixel write loop, the CSR trigger, and the result extraction are identical in logic.
Only the system calls that wrap them change.

---

## Full Flow Summary

```
PC side:
  1. python gen_test_image_baremetal.py --image photo.jpg --out image
     → creates image.bin (150,528 bytes)

Vitis IDE:
  2. Import shufflenet.xsa → build BSP + application
  3. Program bitstream (.bit) onto FPGA → wait for DONE LED
  4. Run shufflenet_test_baremetal.elf in debug mode

UART terminal (PuTTY, 115200 baud):
  5. See startup banner and upload prompt

XSCT console (in Vitis):
  6. connect
     targets -set -filter {name =~ "Cortex-A53 #0"}
     source N:/GP/bare_metal_test/load_image.tcl
     → image.bin written to DDR 0x10000000 in a few seconds

UART terminal:
  7. Press ENTER
  8. Watch image write (~3 ms) and inference (~1 ms)
  9. Read class_idx result
```
