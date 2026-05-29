"""
gen_photo_mem_vectors.py
========================
Generates testbench vectors for photo_mem (Module 1.10).

The test uses a small image (IMG_W=4, IMG_H=4) to keep the vector file
short, but exercises the full ping-pong protocol:
  Phase A: Write known pattern to bank0 (mem_select=0), read from bank1 (all X)
  Phase B: Toggle mem_select=1, read bank0 -- verify written data
  Phase C: Write known pattern to bank1 (mem_select=1), read from bank0
  Phase D: Toggle mem_select=0, read bank1 -- verify written data

Write pattern:
  ch1: addr * 3 + 1  (range 1..48 for 4x4)
  ch2: addr * 3 + 2
  ch3: addr * 3 + 3
  (kept in range 1..150, fits in 15-bit signed Q6.8)

Vector file format (tb/group1/vectors/photo_mem_tb_vectors.hex):
  Lines starting with '#' are comments.
  Write lines:  W <addr_hex> <data_ch1_hex> <data_ch2_hex> <data_ch3_hex>
  Read lines :  R <addr_hex> <exp_ch1_hex>  <exp_ch2_hex>  <exp_ch3_hex>

"""

import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT  = os.path.join(SCRIPT_DIR, "..", "..")
VEC_OUT    = os.path.join(PROJ_ROOT, "tb", "group1", "vectors",
                          "photo_mem_tb_vectors.hex")

IMG_W   = 4
IMG_H   = 4
DEPTH   = IMG_W * IMG_H   # 16
DATA_W  = 15
DATA_MAX = (1 << (DATA_W - 1)) - 1   # 16383

# Write pattern per channel (simple, deterministic)
def pat(addr, ch):
    return addr * 3 + ch  # ch in {1,2,3}

def hex15(v):
    # 15-bit two's complement hex (4 digits, mask to DATA_W bits)
    return f"{v & 0x7FFF:04X}"

lines = []

lines.append("// photo_mem testbench check vectors")
lines.append("//")
lines.append(f"// IMG_W={IMG_W} IMG_H={IMG_H} DEPTH={DEPTH} DATA_W={DATA_W}")
lines.append("// Format: W addr data_ch1 data_ch2 data_ch3")
lines.append("//         R addr exp_ch1  exp_ch2  exp_ch3")
lines.append("//")
lines.append("// Phase A: write bank0 (mem_select=0)")
lines.append("// -----------------------------------------------------------------------")
lines.append("// BEGIN_PHASE_A")
for addr in range(DEPTH):
    d1 = hex15(pat(addr, 1))
    d2 = hex15(pat(addr, 2))
    d3 = hex15(pat(addr, 3))
    lines.append(f"W {addr:04X} {d1} {d2} {d3}")
lines.append("// END_PHASE_A")

lines.append("//")
lines.append("// Phase B: switch mem_select=1, read bank0, verify")
lines.append("// -----------------------------------------------------------------------")
lines.append("// BEGIN_PHASE_B")
for addr in range(DEPTH):
    e1 = hex15(pat(addr, 1))
    e2 = hex15(pat(addr, 2))
    e3 = hex15(pat(addr, 3))
    lines.append(f"R {addr:04X} {e1} {e2} {e3}")
lines.append("// END_PHASE_B")

lines.append("//")
lines.append("// Phase C: write bank1 (mem_select=1) with different pattern")
lines.append("// -----------------------------------------------------------------------")
lines.append("// BEGIN_PHASE_C")
for addr in range(DEPTH):
    d1 = hex15(pat(addr, 1) + 100)
    d2 = hex15(pat(addr, 2) + 100)
    d3 = hex15(pat(addr, 3) + 100)
    lines.append(f"W {addr:04X} {d1} {d2} {d3}")
lines.append("// END_PHASE_C")

lines.append("//")
lines.append("// Phase D: switch mem_select=0, read bank1, verify")
lines.append("// -----------------------------------------------------------------------")
lines.append("// BEGIN_PHASE_D")
for addr in range(DEPTH):
    e1 = hex15(pat(addr, 1) + 100)
    e2 = hex15(pat(addr, 2) + 100)
    e3 = hex15(pat(addr, 3) + 100)
    lines.append(f"R {addr:04X} {e1} {e2} {e3}")
lines.append("// END_PHASE_D")

os.makedirs(os.path.dirname(VEC_OUT), exist_ok=True)
with open(VEC_OUT, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"Written {len([l for l in lines if not l.startswith('//')])} vector lines")
print(f"Output: {VEC_OUT}")

# Summary statistics
n_write = sum(1 for l in lines if l.startswith("W "))
n_read  = sum(1 for l in lines if l.startswith("R "))
print(f"Write ops: {n_write}  Read ops: {n_read}")
print("Done.")
