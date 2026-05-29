"""
gen_weights_rom_3x3_vectors.py
===============================
Generates PLACEHOLDER weight and bias hex files for weights_rom_3x3.v and
bias_rom_3x3.v. These allow the testbench to run before the real Colab
weights are available.

Placeholder values:
 weight[f][c][r][col] = (f*27 + c*9 + r*3 + col) (unique index 0..647)
 bias[f] = f + 1 (unique index 1..24)

Values are stored as 15-bit Q6.8 integers in 4-hex-digit unsigned format.
Since all indices are small positive integers (< 648), there is no saturation.

When the real weights are available (from scripts/extract_weights_conv1.py run
on Colab), replace these files with the real ones in tb/group1/vectors/.

Output files:
 tb/group1/vectors/weights_rom_3x3.hex -- 648 entries (placeholder)
 tb/group1/vectors/bias_rom_3x3.hex -- 24 entries (placeholder)
 tb/group1/vectors/weights_rom_3x3_tb_vectors.hex -- testbench check vectors
"""

import os
import sys

# -----------------------------------------------------------------------
# Helper: convert signed 15-bit integer to 4-hex-digit unsigned string
# -----------------------------------------------------------------------
def to_hex15(v):
 """Integer (signed) -> 4-hex-digit unsigned 15-bit representation."""
 v = int(v) & 0x7FFF
 return f"{v:04X}"

N_FILT = 24
N_CHAN = 3
N_WIN = 3 # rows
N_COL = 3 # columns = number of ROM address values
DATA_W = 15

out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
 "..", "tb", "group1", "vectors")
os.makedirs(out_dir, exist_ok=True)

# -----------------------------------------------------------------------
# Placeholder weight values: index 0..647, stored as 15-bit signed int
# For Q6.8 representation: integer k maps to float k/256 in hardware.
# But the ROM just outputs raw bits -- the testbench checks bits, not floats.
# -----------------------------------------------------------------------
weight_hex = []
for f in range(N_FILT):
 for c in range(N_CHAN):
 for r in range(N_WIN):
 for col in range(N_COL):
 idx = f * 27 + c * 9 + r * 3 + col # 0..647
 # Store as 15-bit unsigned (all < 32768, positive, no sign)
 weight_hex.append(f"{idx:04X}")

assert len(weight_hex) == 648

# -----------------------------------------------------------------------
# Placeholder bias values: 1..24
# -----------------------------------------------------------------------
bias_hex = [f"{f+1:04X}" for f in range(N_FILT)]
assert len(bias_hex) == 24

# -----------------------------------------------------------------------
# Write weight hex file
# -----------------------------------------------------------------------
w_path = os.path.join(out_dir, "weights_rom_3x3.hex")
with open(w_path, "w") as f:
 f.write("// weights_rom_3x3.hex -- PLACEHOLDER (see extract_weights_conv1.py)\n")
 f.write("// /\n")
 f.write("// Index = filter*27 + channel*9 + row*3 + col (648 entries)\n")
 for h in weight_hex:
 f.write(h + "\n")
print(f"Written: {w_path} ({len(weight_hex)} placeholder weight entries)")

# -----------------------------------------------------------------------
# Write bias hex file
# -----------------------------------------------------------------------
b_path = os.path.join(out_dir, "bias_rom_3x3.hex")
with open(b_path, "w") as f:
 f.write("// bias_rom_3x3.hex -- PLACEHOLDER (see extract_weights_conv1.py)\n")
 f.write("// /\n")
 f.write("// 24 bias values, one per filter\n")
 for h in bias_hex:
 f.write(h + "\n")
print(f"Written: {b_path} ({len(bias_hex)} placeholder bias entries)")

# -----------------------------------------------------------------------
# Write testbench check vectors
# Format: for each addr (0,1,2):
# one line per (filter, channel, row) = 216 lines
# each line: addr filter channel row expected_weight_hex
# Total: 3 * 216 = 648 lines
# -----------------------------------------------------------------------
tb_path = os.path.join(out_dir, "weights_rom_3x3_tb_vectors.hex")
with open(tb_path, "w") as f:
 f.write("// weights_rom_3x3 testbench check vectors\n")
 f.write("// Format: addr filter channel row expected_weight_hex\n")
 f.write("// One line per (addr, filter, channel, row) combination\n")
 f.write("// Total: 3 addr x 24 filters x 3 channels x 3 rows = 648 checks\n")
 for addr in range(N_COL):
 for fi in range(N_FILT):
 for ci in range(N_CHAN):
 for ri in range(N_WIN):
 idx = fi * 27 + ci * 9 + ri * 3 + addr
 f.write(f"{addr} {fi} {ci} {ri} {weight_hex[idx]}\n")
print(f"Written: {tb_path} (648 testbench check vectors)")

# -----------------------------------------------------------------------
# Generate Verilog parameter include file
# weights_rom_3x3_init.vh -- hardcoded column-packed weight buses
# Three localparams: COL0_WEIGHTS, COL1_WEIGHTS, COL2_WEIGHTS
# Each is N_FILT*N_CHAN*N_WIN*DATA_W = 216*15 = 3240 bits, packed as:
# bits [(f*9+c*3+r+1)*15-1 : (f*9+c*3+r)*15] = weight[f][c][r][col]
# -----------------------------------------------------------------------
vh_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
 "..", "rtl", "group1", "weights_rom_3x3_init.vh")

# Build per-column packed buses
# Packing order: MSB first = tap (N_FILT*N_CHAN*N_WIN - 1) down to 0
# weights_flat[(f*9+t)*DATA_W +: DATA_W] where t=c*3+r
# So index in packed constant (from MSB): (N_FILT*N_CHAN*N_WIN - 1 - (f*9+c*3+r))
DATA_W = 15
N_TAPS = N_FILT * N_CHAN * N_WIN # 216

col_vals = [[], [], []] # one list per column, index = f*9+c*3+r
for fi in range(N_FILT):
 for ci in range(N_CHAN):
 for ri in range(N_WIN):
 for col in range(N_COL):
 idx = fi * 27 + ci * 9 + ri * 3 + col
 col_vals[col].append(int(weight_hex[idx], 16))

def build_packed(vals):
 """Build a packed Verilog constant from list of 15-bit values.
 vals[0] = tap 0 (LSBs), vals[-1] = tap N_TAPS-1 (MSBs).
 Verilog concatenation is MSB-first: {vals[215], vals[214], ..., vals[0]}."""
 parts = [f"15'h{v:04X}" for v in reversed(vals)]
 return ",\n ".join(parts)

with open(vh_path, "w") as f:
 f.write("// =============================================================\n")
 f.write("// weights_rom_3x3_init.vh -- AUTO-GENERATED weight constants\n")
 f.write("// / Figure 5.6\n")
 f.write("// PLACEHOLDER -- replace with extract_weights_conv1.py output\n")
 f.write("// Generated by: scripts/gen_weights_rom_3x3_vectors.py\n")
 f.write("// =============================================================\n")
 f.write("//\n")
 f.write("// Three column-packed buses, each 216*15 = 3240 bits:\n")
 f.write("// COL{k}_WEIGHTS[(f*9+c*3+r+1)*15-1 : (f*9+c*3+r)*15]\n")
 f.write("// = weight[filter=f][channel=c][row=r][col=k]\n")
 f.write("//\n")
 f.write(f"`ifndef WEIGHTS_ROM_3X3_INIT_VH\n")
 f.write(f"`define WEIGHTS_ROM_3X3_INIT_VH\n\n")

 for col in range(N_COL):
 name = f"COL{col}_WEIGHTS"
 total_bits = N_TAPS * DATA_W
 packed = build_packed(col_vals[col])
 f.write(f"localparam [{total_bits}-1:0] {name} = {{\n")
 f.write(f" {packed}\n")
 f.write(f"}};\n\n")

 f.write("`endif\n")

print(f"Written: {vh_path} (Verilog init file with hardcoded weight constants)")

print("\nTo replace with real Colab weights:")
print(" 1. Run scripts/extract_weights_conv1.py on Colab")
print(" 2. It will produce: weights_rom_3x3_init.vh, weights_rom_3x3.hex, bias_rom_3x3.hex")
print(" 3. Place weights_rom_3x3_init.vh in rtl/common/")
print(" 4. Place hex files in tb/group1/vectors/")
print(" 5. Re-run: vivado -mode batch -source vivado/scripts/sim_tb_weights_rom_3x3.tcl")
