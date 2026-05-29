"""
extract_weights_conv1.py
========================
Loads ShuffleNet V2 x1.0, folds BatchNorm into conv1 weights, quantizes to
12-bit Q2.9 (Ch 6.2.5 per-layer weight widths: G1_CONV_WW=12, 9-bit fraction),
then writes the weight init files used by the RTL ROM module.

RUN (from project root N:\\GP\\shufflenet_rtl\\):
 python scripts/group1/extract_weights_conv1.py

OUTPUT FILES:
 rtl/group1/weights_rom_3x3_init.vh -- Verilog localparam init (synthesis)
 tb/group1/vectors/weights_rom_3x3_tb_vectors.hex -- testbench check vectors
 tb/group1/vectors/weights_rom_3x3.hex -- flat hex (used by $readmemh in TB)
 tb/group1/vectors/bias_rom_3x3.hex -- bias hex for TB

QUANTIZATION FORMAT (Ch 6.2.5, shufflenet_pkg.vh G1_CONV_WW=12):
 12-bit signed Q2.9: 1 sign + 2 integer + 9 fractional bits
 Scale = 2^9 = 512
 Range: [-4.0, +3.998] real values -> stored as [-2048, 2047] integers
 Hex: 3 digits (000..FFF in unsigned two's complement)

THESIS REFERENCES
 "Weights Memory" / Figure 5.6
 "Bias Memory" / Figure 5.7
 BN folding
 Sec 6.2.5 Per-layer weight widths (G1_CONV_WW=12 with 9-bit fraction)
"""

import sys
import os
import copy
import numpy as np

try:
 import torch
 import torchvision
 from torchvision import models
except ImportError as e:
 print(f"ERROR: {e}")
 print("Install with: pip install torch torchvision")
 sys.exit(1)

print(f"PyTorch : {torch.__version__}")
print(f"Torchvision : {torchvision.__version__}")
print(f"Device : {'cuda' if torch.cuda.is_available else 'cpu'}\n")

device = torch.device("cuda" if torch.cuda.is_available else "cpu")

# ------------------------------------------------------------------
# Quantization parameters (Ch 6.2.5: G1_CONV_WW=12, 9-bit fraction)
# ------------------------------------------------------------------
N_WORD = 12 # total bits
N_FRAC = 9 # fractional bits (Q2.9)
SCALE = 1 << N_FRAC # 512
MAX_INT = (1 << (N_WORD - 1)) - 1 # 2047
MIN_INT = -(1 << (N_WORD - 1)) # -2048
MASK = (1 << N_WORD) - 1 # 0xFFF

def quantize(x):
 """Quantize float -> N_WORD-bit signed Q2.9 integer (unsigned repr)."""
 v = int(round(float(x) * SCALE))
 v = max(MIN_INT, min(MAX_INT, v)) # saturate
 return v & MASK # unsigned two's-complement

def dequantize(uint_val):
 """Convert unsigned N_WORD-bit int back to float (for error reporting)."""
 v = int(uint_val)
 if v >= (1 << (N_WORD - 1)):
 v -= (1 << N_WORD)
 return v / SCALE

# ------------------------------------------------------------------
# 1. Load pre-trained ShuffleNet V2 x1.0
# ------------------------------------------------------------------
print("Loading ShuffleNet V2 x1.0 ...")
weights_cfg = models.ShuffleNet_V2_X1_0_Weights.DEFAULT
model = models.shufflenet_v2_x1_0(weights=weights_cfg).to(device)
model.eval
print(" Loaded.\n")

# ------------------------------------------------------------------
# 2. Fold BatchNorm into Conv weights
# W_new = W * (gamma / sqrt(var + eps))
# b_new = (gamma/sqrt(var+eps)) * (b - mu) + beta
# ------------------------------------------------------------------
def fold_conv_bn(conv, bn):
 conv = copy.deepcopy(conv)
 gamma = bn.weight.data
 beta = bn.bias.data
 mu = bn.running_mean
 sigma2 = bn.running_var
 eps = bn.eps
 scale = gamma / torch.sqrt(sigma2 + eps)
 conv.weight = torch.nn.Parameter(
 conv.weight.data * scale.view(-1, 1, 1, 1))
 bias = (conv.bias.data if conv.bias is not None
 else torch.zeros(conv.weight.shape[0], device=conv.weight.device))
 conv.bias = torch.nn.Parameter(scale * (bias - mu) + beta)
 return conv

def fold_all_bn(module, path=""):
 for name, child in module.named_children:
 cur = f"{path}.{name}" if path else name
 if isinstance(child, torch.nn.Sequential):
 layers = list(child.children)
 new_layers = []
 i = 0
 while i < len(layers):
 if (isinstance(layers[i], torch.nn.Conv2d) and
 i + 1 < len(layers) and
 isinstance(layers[i + 1], torch.nn.BatchNorm2d)):
 folded = fold_conv_bn(layers[i], layers[i + 1])
 new_layers.append(folded)
 new_layers.append(torch.nn.Identity)
 print(f" Folded {cur} layers [{i},{i+1}]")
 i += 2
 else:
 new_layers.append(layers[i])
 i += 1
 setattr(module, name, torch.nn.Sequential(*new_layers))
 fold_all_bn(getattr(module, name), cur)
 else:
 fold_all_bn(child, cur)

print("Folding BatchNorm into Conv weights...")
model_bn = copy.deepcopy(model)
model_bn.eval
fold_all_bn(model_bn)
print

# Sanity check: BN-folded model must match original
with torch.no_grad:
 x_test = torch.randn(1, 3, 224, 224).to(device)
 out_orig = model(x_test)
 out_bn = model_bn(x_test)
max_diff = (out_orig - out_bn).abs.max.item
print(f"BN-fold sanity check: max output diff = {max_diff:.2e} "
 f"({'OK' if max_diff < 1e-2 else 'WARNING: large diff'})\n")

# ------------------------------------------------------------------
# 3. Extract conv1 weights and biases
# PyTorch layout: [out_filt=24, in_ch=3, h=3, w=3]
# ------------------------------------------------------------------
print("Extracting conv1 weights and biases...")
sd = model_bn.state_dict
W_float = sd["conv1.0.weight"].cpu.numpy # [24, 3, 3, 3]
b_float = sd["conv1.0.bias"].cpu.numpy # [24]

print(f" Weight shape : {W_float.shape}")
print(f" Weight range : [{W_float.min:.4f}, {W_float.max:.4f}]")
print(f" Bias range : [{b_float.min:.4f}, {b_float.max:.4f}]\n")

# ------------------------------------------------------------------
# 4. Quantize to 12-bit Q2.9
# ------------------------------------------------------------------
print(f"Quantizing to {N_WORD}-bit Q{N_WORD-N_FRAC-1}.{N_FRAC} (scale={SCALE})...")

saturated_w = np.sum(np.abs(W_float) > (MAX_INT / SCALE))
saturated_b = np.sum(np.abs(b_float) > (MAX_INT / SCALE))
print(f" Saturated weights : {saturated_w} / {W_float.size} "
 f"(max representable = {MAX_INT/SCALE:.4f})")
print(f" Saturated biases : {saturated_b} / {b_float.size}")

# Build flat lists in ROM order:
# for filter in 0..23: for channel in 0..2: for row in 0..2: for col in 0..2
weight_uint = [] # unsigned 12-bit ints (0..4095)
weight_hex = [] # 3-digit hex strings

for f in range(24):
 for c in range(3):
 for r in range(3):
 for col in range(3):
 u = quantize(W_float[f, c, r, col])
 weight_uint.append(u)
 weight_hex.append(f"{u:03X}")

bias_uint = []
bias_hex = []
for f in range(24):
 u = quantize(b_float[f])
 bias_uint.append(u)
 bias_hex.append(f"{u:03X}")

assert len(weight_hex) == 648
assert len(bias_hex) == 24

# Quantization error report
w_errs = []
for i, (w, u) in enumerate(zip(W_float.flatten, weight_uint)):
 w_errs.append(abs(w - dequantize(u)))
max_w_err = max(w_errs)
print(f" Max weight quant error : {max_w_err:.6f} "
 f"(1 LSB = {1/SCALE:.6f})\n")

# ------------------------------------------------------------------
# 5. Determine output paths (run from project root or script dir)
# ------------------------------------------------------------------
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(script_dir, "..", ".."))

paths = {
 "init_vh" : os.path.join(project_root, "rtl", "group1", "weights_rom_3x3_init.vh"),
 "tb_vec" : os.path.join(project_root, "tb", "group1", "vectors", "weights_rom_3x3_tb_vectors.hex"),
 "w_hex" : os.path.join(project_root, "tb", "group1", "vectors", "weights_rom_3x3.hex"),
 "b_hex" : os.path.join(project_root, "tb", "group1", "vectors", "bias_rom_3x3.hex"),
 "verify_txt": os.path.join(project_root, "tb", "group1", "vectors", "weights_rom_3x3_verify.txt"),
}

# Create directories if missing
for p in paths.values:
 os.makedirs(os.path.dirname(p), exist_ok=True)

# ------------------------------------------------------------------
# 6. Write weights_rom_3x3_init.vh (Verilog synthesis init file)
# Three column-packed localparam buses: COL0, COL1, COL2.
# Each bus = 216 weights x 12 bits = 2592 bits.
# MSB-first ordering: {weights[215], weights[214], ..., weights[0]}
# ------------------------------------------------------------------
N_TAPS = 24 * 3 * 3 # 216 taps per column
TOTAL_BITS = N_TAPS * N_WORD # 2592

col_vals = [[], [], []] # col_vals[addr][tap] = unsigned 12-bit int
for f in range(24):
 for c in range(3):
 for r in range(3):
 for col in range(3):
 idx = f * 27 + c * 9 + r * 3 + col
 col_vals[col].append(weight_uint[idx])

def build_packed_bus(vals):
 """Build Verilog concatenation string, MSB first."""
 parts = [f"{N_WORD}'h{v:03X}" for v in reversed(vals)]
 return ",\n ".join(parts)

with open(paths["init_vh"], "w") as f:
 f.write("// =============================================================\n")
 f.write("// weights_rom_3x3_init.vh -- AUTO-GENERATED\n")
 f.write("// / Figure 5.6 / Ch 6.2.5\n")
 f.write(f"// {N_WORD}-bit Q{N_WORD-N_FRAC-1}.{N_FRAC}, BN-folded conv1 weights\n")
 f.write("// Source: ShuffleNet V2 x1.0 (torchvision pretrained)\n")
 f.write("// Generated by: scripts/group1/extract_weights_conv1.py\n")
 f.write("// =============================================================\n")
 f.write("`ifndef WEIGHTS_ROM_3X3_INIT_VH\n")
 f.write("`define WEIGHTS_ROM_3X3_INIT_VH\n\n")
 for col in range(3):
 packed = build_packed_bus(col_vals[col])
 f.write(f"localparam [{TOTAL_BITS}-1:0] COL{col}_WEIGHTS = {{\n")
 f.write(f" {packed}\n}};\n\n")
 f.write("`endif\n")

print(f"Written: {paths['init_vh']}")

# ------------------------------------------------------------------
# 7. Write weights_rom_3x3.hex (flat hex, used by $readmemh in TB)
# ------------------------------------------------------------------
with open(paths["w_hex"], "w") as f:
 for h in weight_hex:
 f.write(h + "\n")
print(f"Written: {paths['w_hex']} ({len(weight_hex)} entries)")

# ------------------------------------------------------------------
# 8. Write bias_rom_3x3.hex
# ------------------------------------------------------------------
with open(paths["b_hex"], "w") as f:
 for h in bias_hex:
 f.write(h + "\n")
print(f"Written: {paths['b_hex']} ({len(bias_hex)} entries)")

# ------------------------------------------------------------------
# 9. Write testbench check vectors
# Format: addr filter channel row expected_hex (3 digits)
# ------------------------------------------------------------------
with open(paths["tb_vec"], "w") as f:
 f.write("// weights_rom_3x3 testbench check vectors\n")
 f.write(f"// {N_WORD}-bit Q{N_WORD-N_FRAC-1}.{N_FRAC} BN-folded weights\n")
 f.write("// Format: addr filter channel row expected_hex\n")
 f.write("// Generated by: scripts/group1/extract_weights_conv1.py\n")
 for addr in range(3):
 for fi in range(24):
 for ci in range(3):
 for ri in range(3):
 idx = fi * 27 + ci * 9 + ri * 3 + addr
 f.write(f"{addr} {fi} {ci} {ri} {weight_hex[idx]}\n")
print(f"Written: {paths['tb_vec']} (648 check vectors)")

# ------------------------------------------------------------------
# 10. Write human-readable verification dump
# ------------------------------------------------------------------
with open(paths["verify_txt"], "w") as f:
 f.write(f"weights_rom_3x3 -- {N_WORD}-bit Q{N_WORD-N_FRAC-1}.{N_FRAC} BN-folded conv1 weights\n")
 f.write(f"{'idx':>4} {'f':>3} {'c':>2} {'r':>2} {'col':>3} "
 f"{'hex':>4} {'float_orig':>11} {'float_quant':>11} {'err':>8}\n")
 f.write("-" * 65 + "\n")
 idx = 0
 for fi in range(24):
 for ci in range(3):
 for ri in range(3):
 for co in range(3):
 orig = W_float[fi, ci, ri, co]
 quant = dequantize(weight_uint[idx])
 f.write(f"{idx:4d} {fi:3d} {ci:2d} {ri:2d} {co:3d} "
 f"{weight_hex[idx]:>4} {orig:11.6f} "
 f"{quant:11.6f} {abs(orig-quant):8.6f}\n")
 idx += 1
 f.write("\nBIASES\n")
 f.write(f"{'f':>3} {'hex':>4} {'float_orig':>11} {'float_quant':>11}\n")
 f.write("-" * 35 + "\n")
 for fi in range(24):
 orig = b_float[fi]
 quant = dequantize(bias_uint[fi])
 f.write(f"{fi:3d} {bias_hex[fi]:>4} {orig:11.6f} {quant:11.6f}\n")
print(f"Written: {paths['verify_txt']}")

# ------------------------------------------------------------------
# 11. Summary
# ------------------------------------------------------------------
print
print("=" * 60)
print("EXTRACTION COMPLETE")
print("=" * 60)
print(f" Format : {N_WORD}-bit signed Q{N_WORD-N_FRAC-1}.{N_FRAC} (scale={SCALE})")
print(f" Weight entries : {len(weight_hex)} (24 filters x 3 ch x 3 rows x 3 cols)")
print(f" Bias entries : {len(bias_hex)} (24 filters)")
print(f" Max weight error : {max_w_err:.6f} (1 LSB = {1/SCALE:.6f})")
print(f" Saturated : {saturated_w} weights, {saturated_b} biases")
print
print("Output files:")
for k, p in paths.items:
 print(f" {p}")
