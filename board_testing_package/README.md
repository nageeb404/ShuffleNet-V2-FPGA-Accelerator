# ShuffleNet V2 FPGA — Board Testing Package (Bare-Metal)

Everything needed to program the iWave ZU19EG board and run one inference test,
in this one folder. No PetaLinux, no SD card OS — this runs directly on the
Cortex-A53 with no operating system (bare-metal).

## What's in this folder

| File | Role |
|---|---|
| `shufflenet.bit` | Bitstream — programs the FPGA fabric |
| `shufflenet.xsa` | Hardware platform — import into Vitis to build software against this exact hardware |
| `src/shufflenet_test_baremetal.c` | The ARM program: uploads a test image, triggers inference, prints the result |
| `src/hw_config.h` | Hardware addresses (AXI base, CSR register, DDR buffer location) |
| `src/platform.c` / `src/platform.h` | Standard Vitis boilerplate (cache init) — required, Vitis's "Empty Application" template doesn't generate these on its own |
| `gen_test_image_baremetal.py` | Run on your PC: turns any photo into the exact byte format the FPGA expects |
| `load_image.tcl` | Run inside Vitis's XSCT console: loads the test image into board DDR memory over JTAG |

## Full procedure

### 1. Prepare a test image (on your PC)
```
pip install pillow numpy
python gen_test_image_baremetal.py --image C:\path\to\photo.jpg --out image
```
This creates `image.bin` (150,528 bytes) in the same folder — keep it next to
`load_image.tcl`, since the script looks for it there by default.

### 2. Build the Vitis project
1. `File → New → Platform Project` — import hardware: **this folder's `shufflenet.xsa`**. Domain: `psu_cortexa53_0` (the 64-bit Cortex-A53 core — not the Cortex-R5). Build the platform.
2. `File → New → Application Project` — template: **Empty Application (C)**.
3. Copy all 4 files from this folder's `src/` into the application project's own `src/` folder: `shufflenet_test_baremetal.c`, `hw_config.h`, `platform.c`, `platform.h`. (All 4 — missing `platform.c`/`.h` causes a `platform.h: No such file or directory` build error.)
4. Build → produces a `.elf` file.

### 3. Program the board
1. Connect JTAG and UART (USB) to the board, power it on.
2. In Vitis: `Xilinx → Program Device` → select **this folder's `shufflenet.bit`** → Program. Wait for the board's DONE LED.
3. Open a serial terminal (PuTTY or similar) on the board's UART COM port, **115200 baud**.

### 4. Run the test
1. `Run → Debug Configurations → Single Application Debug` → run the `.elf` on hardware.
2. The UART terminal will print a startup banner and then wait for you to load the image.
3. Open Vitis's **XSCT Console** (`Xilinx → XSCT Console`) and run:
   ```tcl
   connect
   targets -set -filter {name =~ "Cortex-A53 #0"}
   source /path/to/this/board_testing_package/load_image.tcl
   ```
   (Adjust the path to wherever this folder actually is on the machine running Vitis.)
4. Wait for `Image loaded successfully.` in XSCT, then switch back to the **UART terminal** and press **Enter**.
5. Read the result:
   ```
   === RESULT ===
     class_idx      : 207
     inference time : 1023 us  (1.023 ms)
     CSR value      : 0x000041C
   ==============
   ```

## Key numbers to expect
- Image write time: a few ms (~3.2 ms typical)
- Inference time: roughly 1 ms
- `class_idx` is an ImageNet class index (0–999)

## If something goes wrong
- **Board doesn't respond / no UART output**: confirm the DONE LED is lit after programming the `.bit` — if not, the bitstream didn't program correctly, retry step 3.
- **XSCT `dow -data` fails or is unavailable**: `load_image.tcl` has a commented-out fallback at the bottom using `mwr` (slower, word-by-word) — uncomment and use if needed.
- **Build error `platform.h: No such file or directory`**: you copied only `shufflenet_test_baremetal.c` + `hw_config.h` — go back and copy all 4 files from `src/`.
- **Wrong/garbage result**: check `image.bin` is exactly 150,528 bytes (`load_image.tcl` checks this automatically and will error if not) — regenerate it with `gen_test_image_baremetal.py` if in doubt.

## Note on accuracy
The hardware implements a simplified version of ShuffleNet V2's branch 2 (parallel
DW3×3 ‖ PW1×1 instead of the full PW1×1 → DW3×3 → PW1×1 sequence) — an intentional
design simplification. Expect the hardware's classification result to sometimes
differ from what a full-precision software model would predict for the same image;
this is expected, not a bug.
