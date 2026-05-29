"""
gen_maxpool_mem_vectors.py
==========================
Generates testbench vectors for maxpool_mem (Module 1.11).

Uses N_CHAN=24, IMG_W=4, IMG_H=4 (DEPTH=16) for a fast test.
Tests write followed by read-back for all 24 channels at all 16 addresses.

Write pattern: value for channel ch at addr = (addr * N_CHAN + ch + 1) & 0x7FFF
This avoids zero and stays in 15-bit signed Q6.8 range.

Vector format (tb/group1/vectors/maxpool_mem_tb_vectors.hex):
  W <addr_4hex> <flat_360bit_90hex>
  R <addr_4hex> <flat_360bit_90hex>
  flat[ch*DATA_W +: DATA_W] = value for channel ch (ch0 at LSB, ch23 at MSB)
  flat is written as 90 uppercase hex digits (360 bits total).

"""

import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT  = os.path.join(SCRIPT_DIR, "..", "..")
VEC_OUT    = os.path.join(PROJ_ROOT, "tb", "group1", "vectors",
                          "maxpool_mem_tb_vectors.hex")

N_CHAN  = 24
IMG_W   = 4
IMG_H   = 4
DEPTH   = IMG_W * IMG_H    # 16
DATA_W  = 15
MASK    = (1 << DATA_W) - 1   # 0x7FFF

FLAT_W  = N_CHAN * DATA_W     # 360 bits
HEX_W   = FLAT_W // 4        # 90 hex chars (360 / 4 = 90)


def ch_val(addr, ch):
    """Deterministic write pattern: unique positive value per (addr, ch)."""
    return (addr * N_CHAN + ch + 1) & MASK


def pack_flat(addr):
    """Pack all 24 channel values at given addr into a 360-bit integer."""
    flat = 0
    for ch in range(N_CHAN):
        flat |= ch_val(addr, ch) << (ch * DATA_W)
    return flat


lines = []
lines.append("// maxpool_mem testbench vectors")
lines.append("//")
lines.append(f"// N_CHAN={N_CHAN} IMG_W={IMG_W} IMG_H={IMG_H} DEPTH={DEPTH} DATA_W={DATA_W}")
lines.append(f"// flat[ch*{DATA_W} +: {DATA_W}] = value for channel ch")
lines.append("// Format: op(W/R)  addr(4hex)  flat_data(90hex)")
lines.append("//")
lines.append("// Phase 1: write all addresses")
for addr in range(DEPTH):
    flat = pack_flat(addr)
    lines.append(f"W {addr:04X} {flat:0{HEX_W}X}")

lines.append("//")
lines.append("// Phase 2: read back and verify")
for addr in range(DEPTH):
    flat = pack_flat(addr)
    lines.append(f"R {addr:04X} {flat:0{HEX_W}X}")

os.makedirs(os.path.dirname(VEC_OUT), exist_ok=True)
with open(VEC_OUT, "w") as f:
    f.write("\n".join(lines) + "\n")

n_w = sum(1 for l in lines if l.startswith("W "))
n_r = sum(1 for l in lines if l.startswith("R "))
print(f"Written to: {VEC_OUT}")
print(f"Write ops: {n_w}  Read ops: {n_r}")
print(f"Each line: op + 4-hex addr + {HEX_W}-hex flat ({FLAT_W}-bit)")
print("Done.")
