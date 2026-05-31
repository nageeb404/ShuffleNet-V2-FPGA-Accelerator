# ShuffleNet V2 FPGA Accelerator

A fully custom RTL implementation of the ShuffleNet V2 image classification network, synthesized for the **iWave ZU19EG Development Kit** (Zynq UltraScale+ MPSoC). The design uses a fixed-point Q6.8 datapath, pipelined group execution, and on-chip weight ROMs to perform real-time ImageNet classification entirely within FPGA fabric, with the ARM Processing System loading images and reading results over AXI4-Lite.

---

## Team

| Name                                     |
|------------------------------------------|
| Ahmed Ahmed Nageeb Ahmed Elbermawy       |
| Yousef Abdulrahman Abdulnabi Abdulrahman |
| Mohamed Ahmed Roshdy Saad                |
| Basmala Hatem Abdullah Mostafa           |

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Network Architecture](#network-architecture)
3. [Fixed-Point Datapath](#fixed-point-datapath)
4. [Design Specifications](#design-specifications)
5. [Repository Structure](#repository-structure)
6. [Requirements](#requirements)
7. [Setup](#setup)
8. [Building the Vivado Project](#building-the-vivado-project)
9. [Synthesis and Implementation](#synthesis-and-implementation)
10. [Running Simulation](#running-simulation)
11. [Hardware Deployment](#hardware-deployment)
12. [RTL Module Reference](#rtl-module-reference)
13. [HLS Reference Models](#hls-reference-models)
14. [Design Optimizations](#design-optimizations)
15. [Results](#results)

---

## System Overview

The accelerator is implemented as a programmable logic (PL) module that communicates with the ARM Cortex-A53 processing system (PS) via a 32 MB AXI4-Lite window. The PS loads a 224×224 RGB image, triggers inference, and polls a status register until the top-1 class index is available. No external DDR access is required during inference — all weights are stored in on-chip BRAMs.

```
  ┌────────────────────────────────────────┐
  │  ARM Cortex-A53 (Processing System)    │
  │  Runs Linux; controls inference        │
  └──────────────────────┬─────────────────┘
                         │
                         │  AXI4-Lite  (base: 0xA000_0000, 32 MB)
                         │
  ┌──────────────────────┴────────────────┐
  │  shufflenet_board_top  (PL Fabric)    │
  │  MMCM: PS pl_clk0 → 100 MHz           │
  │  4-stage reset synchronizer           │
  │  AXI4-Lite slave + inference CSR      │
  └──────────────────────┬────────────────┘
                         │  100 MHz
  ┌──────────────────────┴────────────────┐
  │           accelerator_top             │
  │                                       │
  │  photo_mem  (224×224×3, ping-pong)    │
  │       │                               │
  │  Group 1 : 3×3 Conv + MaxPool         │
  │       │  56×56×24                     │
  │  Group 2 : 16 Shuffle Blocks          │
  │       │  7×7×464                      │
  │  Group 3 : PW + AvgPool + FC          │
  │       │                               │
  │  class_idx [9:0]                      │
  └───────────────────────────────────────┘
```

---

## Network Architecture

ShuffleNet V2 × 1.0 is mapped to three sequential hardware groups. Groups execute in a pipelined fashion: Group 1 starts processing the next image while Group 3 classifies the previous one.

### Data Flow

| Stage   | Layer                           | Input      | Output     |
|---------|---------------------------------|------------|------------|
| Group 1 | Conv 3×3 (24 filters, stride 2) | 224×224×3  | 112×112×24 |
| Group 1 | Max Pool (3×3, stride 2)        | 112×112×24 | 56×56×24   |
| Group 2 | Stage 2 — 4 Shuffle Blocks      | 56×56×24   | 28×28×116  |
| Group 2 | Stage 3 — 8 Shuffle Blocks      | 28×28×116  | 14×14×232  |
| Group 2 | Stage 4 — 4 Shuffle Blocks      | 14×14×232  | 7×7×464    |
| Group 3 | Conv 1×1 (1024 filters)         | 7×7×464    | 7×7×1024   |
| Group 3 | Global Average Pool (7×7)       | 7×7×1024   | 1×1024     |
| Group 3 | Fully Connected (1000 neurons)  | 1024       | 1000       |

### Parallelism Factors

| Group   | Operation | Parallel Filters | Parallel Channels | Parallel Window |
|---------|-----------|------------------|-------------------|-----------------|
| Group 1 | 3×3 Conv  | 24               | 3                 | 3               |
| Group 1 | Max Pool  | 24               | —                 | 9 (full 3×3)    |
| Group 2 | DW 3×3    | 58               | —                 | 9 (full 3×3)    |
| Group 2 | PW 1×1    | 58               | 12                | —               |
| Group 3 | PW 1×1    | 16               | 29                | —               |
| Group 3 | Avg Pool  | 16               | —                 | —               |
| Group 3 | FC        | —                | 32                | —               |

---

## Fixed-Point Datapath

All arithmetic uses signed fixed-point representation. The baseline format is **Q6.8** (15-bit: 1 sign + 6 integer + 8 fractional bits). Per-layer width optimization is applied across the full pipeline.

### Multiplier Pipeline

```
  A (15-bit)  ×  W (15-bit)
          │
          ▼  30-bit product  (Q12.16)
    drop 7 LSBs
          │
          ▼  23-bit MAC value
    N-input adder tree
          │
    accumulator (extended width)
          │
    saturating quantizer
          │
          ▼  layer output width
```

### Per-Layer Feature Map Widths

| Layer                             | Width  | Fractional Bits |
|-----------------------------------|--------|-----------------|
| Photo memory (input pixels)       | 8-bit  | 5               |
| Group 1 output (Conv3×3, MaxPool) | 10-bit | 6               |
| Group 2 output (DW, PW)           | 12-bit | 8               |
| Group 3 / FC                      | 9-bit  | 5               |

### Per-Layer Weight Widths

| Layer              | Width  |
|--------------------|--------|
| Group 1 — 3×3 Conv | 12-bit |
| Group 2 — DW 3×3   | 15-bit |
| Group 2 — PW 1×1   | 11-bit |
| Group 3 — PW 1×1   | 9-bit  |
| Group 3 — FC       | 9-bit  |

---

## Design Specifications

### Target Device

| Parameter     | Value                                    |
|---------------|------------------------------------------|
| Device        | Xilinx Zynq UltraScale+ ZU19EG           |
| Part number   | xczu19eg-ffvc1760-1-i                    |
| Board         | iWave ZU19EG Development Kit             |
| PL clock      | 100 MHz (MMCM-generated from PS pl_clk0) |
| Reset         | Active-low, synchronized to PL clock     |
| AXI interface | AXI4-Lite, 32-bit data, 32-bit address   |

### DSP Budget (Calculated from Parallelism Parameters)

| Block              | DSP Count |
|--------------------|-----------|
| Group 1 — 3×3 Conv | 216       |
| Group 2 — DW 3×3   | 522       |
| Group 2 — PW 1×1   | 696       |
| Group 3 — PW 1×1   | 464       |
| Group 3 — FC       | 32        |
| **Total**          | **1,930** |
| ZU19EG available   | 1,968     |
| Headroom           | 38        |

### On-Chip Memory

| Buffer      | Purpose                                | Size                |
|-------------|----------------------------------------|---------------------|
| photo_mem   | Input image buffer (ping-pong, 3 ch)   | 3 × 50,176 × 8-bit  |
| maxpool_mem | Group 1 to Group 2 feature map link    | 24 × 3,136 × 10-bit |
| extra_mem   | Group 2 to Group 3 feature map link    | 29 × 1,024 × 12-bit |
| Weight ROMs | All layer weights and biases (on-chip) | See RTL reference   |

---

## Repository Structure

```
shufflenet_v2_fpga/
│
├── README.md
├── .gitignore
│
├── docs/
│   ├── system_diagram.png                 System-level block diagram (PS + PL)
│   └── accelerator_diagram.png            Accelerator internal dataflow
│
├── rtl/                                   RTL Verilog source
│   ├── common/
│   │   ├── shufflenet_pkg.vh              Central parameter file
│   │   ├── mac_unit.v                     Pipelined signed multiplier-accumulator
│   │   ├── Adder3.v                       3-input carry-save adder cell
│   │   ├── adder_tree_9.v                 9-input adder tree  (Group 1)
│   │   ├── adder_tree_12.v                12-input adder tree (Group 2 PW)
│   │   ├── adder_tree_29.v                29-input adder tree (Group 3 PW)
│   │   ├── adder_tree_32.v                32-input adder tree (Group 3 FC)
│   │   ├── quantizer.v                    Saturating fixed-point quantizer
│   │   ├── fifo_3x3.v                     3-row sliding window FIFO
│   │   └── fifo_ctrl.v                    FIFO controller FSM
│   │
│   ├── group1/                            3×3 Conv + MaxPool
│   │   ├── photo_mem.v                    Ping-pong image BRAM (224×224×3, 8-bit)
│   │   ├── conv3x3_core.v                 24-filter parallel 3×3 conv core
│   │   ├── conv3x3_filter_unit.v          Single 3×3 filter (9 MACs)
│   │   ├── weights_rom_3x3.v              3×3 weight ROM (distributed LUT)
│   │   ├── weights_rom_3x3_init.vh        Weight initialisation header
│   │   ├── bias_rom_3x3.v                 Conv bias ROM
│   │   ├── bias_rom_3x3_init.vh           Bias initialisation header
│   │   ├── maxpool_core.v                 3×3 max-of-9, 24 channels parallel
│   │   ├── maxpool_mem.v                  56×56×24 output feature map BRAM
│   │   ├── fifo_pool.v                    MaxPool sliding window FIFO
│   │   ├── group1_ctrl.v                  Group 1 sequencer FSM
│   │   ├── group1_top.v                   Group 1 top-level integration
│   │   └── group1_top_bb.v                Black-box stub (split synthesis flow)
│   │
│   ├── group2/                            16 Shuffle Blocks (DW 3×3 + PW 1×1)
│   │   ├── dw_conv3x3_core.v              58-filter depthwise 3×3 conv core
│   │   ├── dw_conv3x3_filter_unit.v       Single DW filter (9 MACs)
│   │   ├── dw_conv3x3_ctrl.v              Depthwise sequencer FSM
│   │   ├── conv1x1_core.v                 58-filter pointwise conv (12-ch parallel)
│   │   ├── conv1x1_filter_unit.v          Single PW filter (12 MACs)
│   │   ├── conv1x1_ctrl.v                 Pointwise accumulation sequencer
│   │   ├── group2_fifo.v                  Variable-width 3×3 sliding window FIFO
│   │   ├── group2_fifo_ctrl.v             FIFO controller (5-state FSM)
│   │   ├── g2_dw_weight_rom.v             DW weight ROM (distributed)
│   │   ├── g2_dw_bias_rom.v               DW bias ROM (packed, all 58 biases/entry)
│   │   ├── g2_pw_weight_rom.v             PW weight ROM (distributed)
│   │   ├── g2_pw_bias_rom.v               PW bias ROM (packed format)
│   │   ├── group2_ctrl.v                  Group 2 top-level sequencer
│   │   ├── group2_top.v                   Group 2 integration (DW+PW+ROMs+buffer)
│   │   ├── group2_top_bb.v                Black-box stub (split synthesis flow)
│   │   └── weights/                       BN-folded hex weight files
│   │       ├── g2_dw_weights.hex
│   │       ├── g2_dw_biases.hex
│   │       ├── g2_pw_weights.hex
│   │       └── g2_pw_biases.hex
│   │
│   ├── group3/                            PW Conv + AvgPool + FC + Argmax
│   │   ├── conv1x1_g3_core.v              16-filter G3 PW conv (29-ch, 27-bit out)
│   │   ├── conv1x1_g3_filter_unit.v       Single G3 PW filter unit
│   │   ├── avg_pool_core.v                7×7 global average pooling (16-ch)
│   │   ├── fc_core.v                      FC layer: 1024 in, 1000 out, 32-ch parallel
│   │   ├── fc_filter_unit.v               Single FC neuron (32 MACs + >>2 shift)
│   │   ├── fc_core_stub.v                 Synthesis stub (excluded from build)
│   │   ├── g3_pw_weight_rom.v             G3 PW weight ROM (BRAM)
│   │   ├── g3_pw_bias_rom.v               G3 PW bias ROM (packed)
│   │   ├── g3_fc_weight_rom.v             FC weight ROM (BRAM, 32K entries)
│   │   ├── g3_fc_bias_rom.v               FC bias ROM (1000 entries)
│   │   ├── group3_ctrl.v                  Group 3 sequencer (10-counter FSM)
│   │   ├── group3_top.v                   Group 3 integration
│   │   ├── group3_top_bb.v                Black-box stub (split synthesis flow)
│   │   └── weights/                       BN-folded hex weight files
│   │       ├── g3_pw_weights.hex
│   │       ├── g3_pw_biases.hex
│   │       ├── g3_fc_weights.hex
│   │       └── g3_fc_biases.hex
│   │
│   ├── memories/
│   │   ├── extra_mem.v                    G2→G3 feature buffer (29-ch × 1024 × 12-bit)
│   │   ├── xleft_mem.v                    (superseded — not instantiated)
│   │   └── xright_mem.v                   (superseded — not instantiated)
│   │
│   ├── axi/
│   │   └── axi_photo_mem_slave.v          AXI4-Lite slave: pixel write + CSR
│   │
│   ├── accelerator_ctrl.v                 5-state pipelined FSM (G1/G2/G3 flow)
│   ├── accelerator_top.v                  Full accelerator integration
│   └── shufflenet_board_top.v             Board wrapper: MMCM, reset sync, AXI
│
├── tb/                                    Self-contained Verilog testbenches (48 total, all pass)
│   ├── common/                            Common primitive testbenches + vectors
│   │   ├── tb_Adder3.v
│   │   ├── tb_adder_tree_9/12/29/32.v
│   │   ├── tb_mac_unit.v
│   │   ├── tb_quantizer.v
│   │   ├── tb_fifo_3x3.v
│   │   ├── tb_fifo_ctrl.v
│   │   └── vectors/  (reference .hex test vectors)
│   │
│   ├── group1/                            Group 1 testbenches + vectors
│   │   ├── tb_conv3x3_filter_unit.v
│   │   ├── tb_conv3x3_core.v
│   │   ├── tb_maxpool_core.v
│   │   ├── tb_photo_mem.v
│   │   ├── tb_weights_rom_3x3.v
│   │   ├── tb_bias_rom_3x3.v
│   │   ├── tb_maxpool_mem.v
│   │   ├── tb_fifo_pool.v
│   │   ├── tb_group1_ctrl.v
│   │   ├── tb_group1_top.v
│   │   └── vectors/
│   │
│   ├── group2/                            Group 2 testbenches + vectors
│   │   ├── tb_conv1x1_ctrl/core/filter_unit.v
│   │   ├── tb_dw_conv3x3_ctrl/core/filter_unit.v
│   │   ├── tb_g2_dw/pw_weight/bias_rom.v
│   │   ├── tb_group2_ctrl/fifo/fifo_ctrl/top.v
│   │   └── vectors/
│   │
│   ├── group3/                            Group 3 testbenches + vectors
│   │   ├── tb_avg_pool_core.v
│   │   ├── tb_conv1x1_g3_core/filter_unit.v
│   │   ├── tb_fc_core/filter_unit.v
│   │   ├── tb_g3_pw/fc_weight/bias_rom.v
│   │   ├── tb_group3_ctrl/top.v
│   │   └── vectors/
│   │
│   ├── memories/
│   │   └── tb_extra_mem.v
│   │
│   ├── axi/
│   │   └── tb_axi_photo_mem_slave.v
│   │
│   ├── tb_accelerator_ctrl.v
│   └── tb_accelerator_top.v
│
├── scripts/                               Python model utilities
│   ├── shufflenet_q68.py                  Bit-accurate Q6.8 forward-pass model
│   ├── verify_accuracy.py                 BN-folding + accuracy verification
│   ├── common/                            Vector generators for common primitives
│   ├── group1/                            G1 weight extractor + vector generators
│   ├── group2/
│   │   └── extract_weights_g2_g3.py       BN-folded weights → hex ROM files
│   └── group3/                            G3 vector generators
│
├── hls/                                   Vitis HLS C++ reference models (ZU19EG target)
│   ├── src/
│   │   ├── shufflenet_hls.h               Shared header
│   │   ├── shufflenet_hls.cpp             Model 2: pipelined baseline
│   │   ├── shufflenet_hls_parallelism.cpp Model 3: loop unrolling + partition
│   │   └── shufflenet_hls_final.cpp       Model 4: combined optimizations
│   ├── tb/
│   │   └── tb_shufflenet.cpp              C-simulation testbench
│   ├── weights/                           Weight headers (block_s*.h, conv*.h, fc*.h)
│   └── scripts/
│       ├── create_hls_project.tcl         Model 2 project
│       ├── create_parallelism_project.tcl Model 3 project
│       ├── create_final_project.tcl       Model 4 project
│       └── run_csynth.tcl                 C synthesis runner
│
├── vivado/                                Vivado project and scripts
│   ├── constraints/
│   │   └── shufflenet.xdc                 Timing constraints (100 MHz clock)
│   │
│   ├── reports/
│   │   ├── impl_timing.rpt                Post-impl timing (WNS = +0.125 ns)
│   │   └── impl_utilization.rpt           Post-impl resource usage
│   │
│   ├── scripts/                           Simulation and build scripts
│   │   ├── sim_common.tcl                 Shared XSim helper proc
│   │   ├── build_project.tcl              Block design + project creation
│   │   ├── run_synth_impl.tcl             Full synth+impl+bitstream (alternative flow)
│   │   ├── sim_tb_accelerator_ctrl.tcl
│   │   ├── sim_tb_accelerator_top.tcl
│   │   ├── common/   sim_tb_*.tcl         Common primitive simulations (9 scripts)
│   │   ├── group1/   sim_tb_*.tcl         Group 1 simulations (10 scripts)
│   │   ├── group2/   sim_tb_*.tcl         Group 2 simulations (14 scripts)
│   │   ├── group3/   sim_tb_*.tcl         Group 3 simulations (11 scripts)
│   │   ├── memories/ sim_tb_extra_mem.tcl
│   │   └── axi/      sim_tb_axi_photo_mem_slave.tcl
│   │
│   └── work/                              Split synthesis scripts (run in sequence)
│       ├── part0_synth_g1_ooc.tcl         G1 OOC synthesis  → dcp/group1_top.dcp
│       ├── part1_synth_g2_ooc.tcl         G2 OOC synthesis  → dcp/group2_top.dcp
│       ├── part2_synth_g3_ooc.tcl         G3 OOC synthesis  → dcp/group3_top.dcp
│       └── part3_synth_and_impl.tcl       Project synth + fill DCPs + P&R + bitstream
│
└── sw/                                    PS-side Linux software
    ├── shufflenet_test.c                  Test app: load image → AXI → poll → result
    └── gen_test_image.py                  Converts JPEG/PNG → 224×224×3 raw binary
```

---

## Requirements

### EDA Tools

| Tool                          | Version                       |
|-------------------------------|-------------------------------|
| Vivado (with board files)     | 2024.2                        |
| Vitis HLS *(HLS models only)* | 2024.2                        |
| iWave ZU19EG board file       | iw-g35m-19eg-4e004g-e008g-lia |

### Python

Python 3.10 or later with the following packages:

```
pip install numpy torch torchvision Pillow
```

### Board Software (PS-side)

GCC is required on the ZU19EG Linux image to compile the test application:

```bash
gcc -O2 -o shufflenet_test sw/shufflenet_test.c
```

---

## Setup

### 1. Extract and Verify Weights

Fold batch normalization into layer weights and generate hex initialization files for all on-chip ROMs:

```bash
python scripts/group2/extract_weights_g2_g3.py
```

Verify numerical accuracy of the BN-folded weights (expected maximum difference < 1e-5):

```bash
python scripts/verify_accuracy.py
```

### 2. Run the Software Model (Optional)

Run a bit-accurate Q6.8 forward pass in Python to confirm the software baseline before hardware synthesis:

```bash
python scripts/shufflenet_q68.py
```

---

## Building the Vivado Project

The block design (PS configuration, AXI interconnect, and RTL wrapper instantiation) is created from a single TCL script:

```bash
vivado -mode batch -source vivado/scripts/build_project.tcl \
       -log vivado/work/build_project.log
```

This script:
- Creates a Vivado project targeting `xczu19eg-ffvc1760-1-i`
- Configures the Zynq UltraScale+ PS with M_AXI_HPM0_FPD at 100 MHz
- Instantiates SmartConnect and `shufflenet_board_top` as a Module Reference
- Assigns the AXI slave to `0xA000_0000` with a 32 MB address range
- Validates the block design and generates the system wrapper

---

## Synthesis and Implementation

The design uses a **split synthesis flow** to fit within 16 GB RAM. Each group is synthesized as a separate out-of-context checkpoint, then merged at implementation. Run each step from the project root **in your own terminal** (not through Claude Code):

```bash
# Step 1 — rebuild project (fast, ~2 min)
vivado.bat -mode batch -source scripts/build_project.tcl -log vivado/work/build.log -journal vivado/work/build.jou

# Step 2 — Group 1 OOC synthesis (~3 min, ~4 GB RAM)
vivado.bat -mode batch -source scripts/part0_synth_g1_ooc.tcl -log vivado/work/log_g1.log -journal vivado/work/log_g1.jou

# Step 3 — Group 2 OOC synthesis (~9 min, ~8 GB RAM)
vivado.bat -mode batch -source scripts/part1_synth_g2_ooc.tcl -log vivado/work/log_g2.log -journal vivado/work/log_g2.jou

# Step 4 — Group 3 OOC synthesis (~11 min, ~6 GB RAM)
vivado.bat -mode batch -source scripts/part2_synth_g3_ooc.tcl -log vivado/work/log_g3.log -journal vivado/work/log_g3.jou

# Step 5 — top-level synthesis + implementation + bitstream (~1-3 hrs)
vivado.bat -mode batch -source scripts/part3_synth_and_impl.tcl -log vivado/work/log_impl.log -journal vivado/work/log_impl.jou
```

Output files written on completion:

| File                                   | Description                        |
|----------------------------------------|------------------------------------|
| `vivado/shufflenet.bit`                | Bitstream for device programming   |
| `vivado/reports/impl_utilization.rpt`  | Post-implementation resource usage |
| `vivado/reports/impl_timing.rpt`       | Timing summary (WNS, WHS)          |

---

## Running Simulation

All 48 RTL modules have self-contained Verilog testbenches (no external vector files required). Each module has a dedicated simulation script under `vivado/scripts/`.

### Run a Single Module Simulation

```bash
# Example: mac_unit
vivado -mode batch -source vivado/scripts/common/sim_tb_mac_unit.tcl

# Example: Group 2 PW convolution core
vivado -mode batch -source vivado/scripts/group2/sim_tb_conv1x1_core.tcl
```

### Simulation Script Locations

| Group    | Script directory                        |
|----------|-----------------------------------------|
| Common   | `vivado/scripts/common/sim_tb_*.tcl`    |
| Group 1  | `vivado/scripts/group1/sim_tb_*.tcl`    |
| Group 2  | `vivado/scripts/group2/sim_tb_*.tcl`    |
| Group 3  | `vivado/scripts/group3/sim_tb_*.tcl`    |
| Memories | `vivado/scripts/memories/sim_tb_*.tcl`  |
| AXI      | `vivado/scripts/axi/sim_tb_*.tcl`       |
| Top      | `vivado/scripts/sim_tb_accelerator_*.tcl` |

All testbenches report `RESULT: *** ALL TESTS PASSED ***` on success.

---

## Hardware Deployment

### Programming the Device

Connect to the ZU19EG via JTAG and program the bitstream using Vivado Hardware Manager:

```tcl
open_hw_manager
connect_hw_server
open_hw_target
program_hw_devices [get_hw_devices xczu19eg_0] \
    -bitfile {vivado/work/shufflenet_zu19eg.bit}
close_hw_manager
```

### AXI Memory Map

Base address: `0xA000_0000`

| Address Region                  | Access     | Description                      |
|---------------------------------|------------|----------------------------------|
| `BASE + [offset, AWADDR[21]=0]` | Write      | Pixel data (224×224×3 image)     |
| `BASE + [offset, AWADDR[21]=1]` | Read/Write | Control and status register (CSR)|

### CSR Layout (32-bit register)

| Bits   | Field                 | Direction | Description                                  |
|--------|-----------------------|-----------|----------------------------------------------|
| [0]    | `photo_ready`         | R/W       | Write 1 to start inference; write 0 to clear |
| [1]    | `busy`                | R         | High while Groups 1–2 are active             |
| [2]    | `classification_done` | R         | High when top-1 result is valid              |
| [12:3] | `class_idx`           | R         | ImageNet class index (0–999)                 |

### Inference Sequence

```
1. Write all 224×224×3 pixels through the AXI pixel-write region.

2. Write CSR = 0x1  →  assert photo_ready, start inference.

3. Poll CSR until:  busy == 0  AND  classification_done == 1.

4. Read class_idx from CSR[12:3].

5. Write CSR = 0x0  →  clear photo_ready before the next image.
```

### PS Test Application

On the host machine, convert an image to the raw binary format expected by the test application:

```bash
python sw/gen_test_image.py --image photo.jpg --out image.bin
```

Transfer `image.bin` to the board (SCP, USB, or SD card), then compile and run on the ZU19EG:

```bash
gcc -O2 -o shufflenet_test sw/shufflenet_test.c
./shufflenet_test image.bin
```

Expected output:

```
Class index : 281
Inference   : <time> ms
```

---

## RTL Module Reference

### Common Primitives

| Module               | Description                                                  |
|----------------------|--------------------------------------------------------------|
| `shufflenet_pkg.vh`  | Global parameter file: widths, parallelism, memory sizes     |
| `mac_unit.v`         | Pipelined 15×15 multiplier; drops 7 LSBs post-multiply       |
| `adder_tree_9.v`     | 9-input carry-save tree for 3×3 window MAC reduction         |
| `adder_tree_12.v`    | 12-input adder tree for Group 2 PW channel reduction         |
| `adder_tree_29.v`    | 29-input adder tree for Group 3 PW channel reduction         |
| `adder_tree_32.v`    | 32-input adder tree for FC layer channel reduction           |
| `quantizer.v`        | Saturating fixed-point right-shift quantizer                 |
| `fifo_3x3.v`         | Three-row sliding window FIFO for 3×3 convolution data reuse |
| `fifo_ctrl.v`        | FIFO FSM: IDLE → LDROW → LDWIN → PROCESS → LASTPAD           |

### Group 1

| Module                  | Description                                                  |
|-------------------------|--------------------------------------------------------------|
| `photo_mem.v`           | Ping-pong BRAM image buffer, 224×224 pixels per channel      |
| `conv3x3_core.v`        | 24 filter units in parallel; 3 channels × 3 window positions |
| `conv3x3_filter_unit.v` | Single 3×3 filter: 9 MACs, adder tree, accumulator           |
| `weights_rom_3x3.v`     | 3×3 weight ROM (distributed)                                 |
| `bias_rom_3x3.v`        | Convolution bias ROM                                         |
| `maxpool_core.v`        | 3×3 max pooling, full window comparison, 24 ch in parallel   |
| `maxpool_mem.v`         | 56×56×24 output feature map BRAM                             |
| `fifo_pool.v`           | FIFO bank for the max pooling sliding window                 |
| `group1_ctrl.v`         | Sequencer FSM: conv scan, pool scan, done handshake          |
| `group1_top.v`          | Top-level integration of all Group 1 modules                 |

### Group 2

| Module                     | Description                                                  |
|----------------------------|--------------------------------------------------------------|
| `dw_conv3x3_core.v`        | 58 depthwise filter units; 9 MACs per filter (full 3×3)      |
| `dw_conv3x3_filter_unit.v` | Single DW filter: MAC array, adder tree, quantizer           |
| `dw_conv3x3_ctrl.v`        | Depthwise sequencer; controls FIFO and ROM addressing        |
| `conv1x1_core.v`           | 58 pointwise filter units; 12 input channels per unit        |
| `conv1x1_filter_unit.v`    | Single PW filter: 12 MACs, adder tree, accumulator           |
| `conv1x1_ctrl.v`           | Pointwise sequencer; configurable accumulation depth         |
| `group2_fifo.v`            | FIFO bank supporting all feature map widths (56/28/14/7)     |
| `group2_fifo_ctrl.v`       | FIFO controller FSM for the DW sliding window                |
| `g2_dw_weight_rom.v`       | DW weight ROM (distributed, combinational read)              |
| `g2_dw_bias_rom.v`         | DW bias ROM, packed: all 58 biases per address               |
| `g2_pw_weight_rom.v`       | PW weight ROM (distributed, combinational read)              |
| `g2_pw_bias_rom.v`         | PW bias ROM, packed format                                   |
| `group2_ctrl.v`            | Top-level G2 sequencer: DW then PW phases, 16 blocks         |
| `group2_top.v`             | Integration of DW, PW, FIFOs, ROMs, and internal DW buffer   |

### Group 3

| Module                     | Description                                                  |
|----------------------------|--------------------------------------------------------------|
| `conv1x1_g3_core.v`        | 16 filter groups × 29 channels; full-precision output        |
| `conv1x1_g3_filter_unit.v` | Single G3 PW filter unit with 29-input adder tree            |
| `avg_pool_core.v`          | 7×7 global average pooling; 16 channels parallel             |
| `fc_core.v`                | Fully connected: 1024 inputs, 1000 outputs, 32 ch parallel   |
| `fc_filter_unit.v`         | Single FC neuron: 32 MACs, 32-input adder tree               |
| `g3_pw_weight_rom.v`       | Group 3 PW weight ROM (BRAM)                                 |
| `g3_pw_bias_rom.v`         | Group 3 PW bias ROM, packed format                           |
| `g3_fc_weight_rom.v`       | FC weight ROM (BRAM)                                         |
| `g3_fc_bias_rom.v`         | FC bias ROM                                                  |
| `group3_ctrl.v`            | G3 sequencer; manages filter-group and extra_mem addressing  |
| `group3_top.v`             | Top-level integration of all Group 3 modules                 |

### Top Level

| Module                   | Description                                                  |
|--------------------------|--------------------------------------------------------------|
| `extra_mem.v`            | G2 → G3 buffer: 29 channels × 1024 words × 12-bit BRAM       |
| `accelerator_top.v`      | Full integration: G1, G2, G3, extra_mem, accelerator_ctrl    |
| `axi_photo_mem_slave.v`  | AXI4-Lite slave: pixel writes to photo_mem and CSR access    |
| `shufflenet_board_top.v` | Board wrapper: MMCM, 4-stage reset sync, AXI pass-through    |

---

## HLS Reference Models

Four progressively optimized Vitis HLS C++ models are provided to benchmark RTL efficiency against high-level synthesis. All models target the iWave ZU19EG (`xczu19eg-ffvc1760-1-i`) for a direct same-silicon comparison with the RTL implementation.

| Model           | Source File                      | Strategy                        |
|-----------------|----------------------------------|---------------------------------|
| 1 - Baseline    | `shufflenet_hls.cpp`             | Sequential, no directives       |
| 2 - Pipeline    | `shufflenet_hls.cpp`             | `#pragma HLS PIPELINE` on loops |
| 3 - Parallelism | `shufflenet_hls_parallelism.cpp` | Loop unrolling + partitioning   |
| 4 - Combined    | `shufflenet_hls_final.cpp`       | Pipeline + parallelism          |

### Running HLS Models

```bash
# Model 2 (Pipelined)
vitis_hls -f hls/scripts/create_hls_project.tcl

# Model 3 (Parallelism)
vitis_hls -f hls/scripts/create_parallelism_project.tcl

# Model 4 (Combined)
vitis_hls -f hls/scripts/create_final_project.tcl
```

---

## Design Optimizations

Eight RTL optimizations were applied over the baseline 15-bit uniform datapath to improve throughput, reduce resource usage, and meet timing at 100 MHz.

| Optimization                 | Description                                   |
|------------------------------|-----------------------------------------------|
| Vivado directives            | PerformanceOptimized synth + ExplorePostRoute |
| Async reset removal          | High-fanout async resets removed              |
| Average pool simplification  | Division by 49 replaced with right shift      |
| FC output scaling            | Pre-quantizer shift prevents overflow         |
| Per-layer weight widths      | Weight widths reduced from 15 to 9-15 bits    |
| 8-bit photo memory           | photo_mem reduced from 15-bit to 8-bit        |
| G3 output quantizer removal  | G3 conv output bypasses quantizer             |
| Per-layer feature map widths | FM widths reduced to 8/10/12/9-bit per layer  |

---

## Results

### Resource Utilization (Post-Implementation)

| Resource  | Used   | Available | Utilization |
|-----------|--------|-----------|-------------|
| DSP       | 1,550  | 1,968     | 78.76%      |
| LUT       | 68,299 | 522,720   | 13.07%      |
| FF        | 15,285 | 1,045,440 | 1.46%       |
| BRAM Tile | 550.5  | 984       | 55.95%      |

### Timing

| Metric         | Value        |
|----------------|--------------|
| Target clock   | 100 MHz      |
| WNS            | +0.125 ns ✓  |
| WHS            | +0.011 ns ✓  |
| Timing closure | **Met** (0 failing endpoints) |

### Performance

| Metric            | Value       |
|-------------------|-------------|
| Frame rate        | TBD fps     |
| Inference latency | TBD ms      |
| Power             | TBD W       |
| Energy per frame  | TBD J/frame |

### RTL vs HLS Comparison

| Metric         | RTL (this work) | HLS Model 2 — Pipelined |
|----------------|-----------------|-------------------------|
| Target clock   | 100 MHz         | 100 MHz                 |
| Frame rate     | TBD             | TBD                     |
| Power          | TBD             | TBD                     |
| Energy / frame | TBD             | TBD                     |
