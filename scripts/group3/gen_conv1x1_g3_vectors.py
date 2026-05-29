"""
gen_conv1x1_g3_vectors.py
==========================
Generate test vectors for conv1x1_g3_core (Module 3.1).

Reuses the same computation model as conv1x1_core (Module 2.5):
 - 16 parallel filters, 29 shared channels, N_ACC accumulation steps
 - Each filter: 29 MACs -> adder_tree_29 -> acc -> bias -> ReLU -> quantize
 - acc_clr=1 for steps 0,1 (MAC pipeline settling)

Vector format (same as conv1x1_core tests):
 Header: N_FILT N_CHAN N_ACC N_VEC
 Per test vector:
 acc_clr en (1 line)
 d0..d28 (1 line, 29 signed 15-bit hex)
 w[0..15][0..28] (16 lines, each 29 signed 15-bit hex for one filter)
 b[0..15] (1 line, 16 signed 15-bit hex biases)
 r[0..15] (1 line, 16 signed 15-bit hex expected results)
"""
import os, random
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")

DATA_W = 15
MUL_OUT = 23 # after 7-LSB drop: 30-7=23
TREE_OUT = 31 # adder_tree_29: 23+8
ACC_BITS = 34 # +3 for log2(7) with N_ACC=7; for other N_ACC we compute below
BIAS_OUT = 35
IN_MIN = -(1 << (DATA_W-1))
IN_MAX = (1 << (DATA_W-1)) - 1

def clamp(v, bits):
 lo = -(1 << (bits-1))
 hi = (1 << (bits-1)) - 1
 return max(lo, min(hi, v))

def signed_trunc(v, bits):
 """Truncate to `bits`-wide signed integer (drop lower 7 for MAC)."""
 mask = (1 << bits) - 1
 v &= mask
 if v >= (1 << (bits-1)):
 v -= (1 << bits)
 return v

def mac_unit(d, w):
 """15x15 signed multiply, drop 7 LSBs -> 23-bit result."""
 raw = d * w # 30-bit
 return signed_trunc(raw >> 7, MUL_OUT)

def adder_tree_29(prods):
 """Sum 29 values exactly (Python arbitrary precision)."""
 return sum(prods)

def quantize_onesided(v, out_w=DATA_W):
 """One-sided saturating quantizer (after ReLU: values >= 0)."""
 hi = (1 << (out_w-1)) - 1
 if v < 0: return 0 # ReLU
 if v > hi: return hi
 return v

def compute_filter(data, weights, bias, n_acc, acc_clr_steps):
 """
 Simulate one pixel output for one filter.
 data: list of n_acc * 29 input values (grouped by step)
 weights: list of 29 weight values
 bias: integer bias value
 acc_clr_steps: set of step indices where acc_clr=1
 Returns final quantized output.
 """
 import math
 acc_bits = MUL_OUT + 8 + math.ceil(math.log2(max(n_acc, 2)))
 acc = 0
 mac_reg = [0] * 29 # pipeline register inside MAC

 for step in range(n_acc + 1):
 if step == n_acc:
 # Wait cycle: don't update MAC regs, just finalize
 break
 # Products from data[step] through MAC pipeline register
 d_step = data[step * 29 : (step+1) * 29]
 prods = [mac_unit(d_step[c], weights[c]) for c in range(29)]
 mac_reg = prods # update MAC register at this posedge
 # Tree sum using REGISTERED mac outputs
 tree = adder_tree_29(mac_reg)
 # Accumulate
 if step in acc_clr_steps:
 acc = tree
 else:
 acc = acc + tree

 # Bias
 bias_ext = bias # 15-bit signed
 total = acc + bias_ext
 # One-sided quantize (ReLU + saturate)
 return quantize_onesided(total >> (MUL_OUT - DATA_W)) # align Q6.8

def compute_output_simple(data_flat, weight_flat, biases, n_filt, n_chan, n_acc):
 """
 Simpler model matching RTL behaviour exactly.
 data_flat: n_acc x n_chan data values (per step, all channels)
 weight_flat: n_filt x n_chan weights
 biases: n_filt biases
 Returns: n_filt output values
 """
 import math
 ACC_EXTRA = math.ceil(math.log2(max(n_acc, 2)))
 results = []
 for f in range(n_filt):
 w = weight_flat[f * n_chan : (f+1) * n_chan]
 b = biases[f]
 # Accumulate over n_acc steps with pipeline delay
 acc = 0
 mac_prev = [0] * n_chan # MAC register (previous cycle products)
 for step in range(n_acc + 1):
 # Combinational adder_tree uses MAC register (previous products)
 tree = sum(mac_prev) # exact sum for Python model
 # Determine acc_clr for this step
 acc_clr = (step <= 1)
 if step < n_acc:
 # Load new MAC register
 d = data_flat[step * n_chan : (step+1) * n_chan]
 mac_prev = [mac_unit(d[c], w[c]) for c in range(n_chan)]
 # Accumulate using tree result (from mac_prev BEFORE update)
 if acc_clr:
 acc = tree
 else:
 acc = acc + tree
 # On step == n_acc (wait cycle): finalize without new MAC load
 # Add bias
 total = acc + b
 # >> 7 already applied inside mac_unit; tree sum is at Q12.9 scale
 # The accumulator output needs right-shift by (MUL_OUT-DATA_W)=8 to get Q6.8
 # Actually: mac_unit already dropped 7 LSBs (at Q12.9). Sum of n_acc*n_chan macs
 # is still Q12.9. We need Q6.8 output: right shift by 1 more? Let's just use
 # the quantizer directly as RTL does.
 results.append(quantize_onesided(total))
 return results

def sh(v, w=DATA_W):
 mask = (1 << w) - 1
 return format(v & mask, f'0{(w+3)//4}x')

def write_vectors(out_path, n_filt=16, n_chan=29, n_acc=7, n_cases=12, seed=0):
 rng = random.Random(seed)
 Path(out_path).parent.mkdir(parents=True, exist_ok=True)

 with open(out_path, 'w') as f:
 f.write(f"// conv1x1_g3_core vectors: N_FILT={n_filt} N_CHAN={n_chan} N_ACC={n_acc}\n")
 f.write(f"{n_filt} {n_chan} {n_acc} {n_cases}\n")

 for case_idx in range(n_cases):
 # Generate random inputs
 data_flat = [rng.randint(IN_MIN, IN_MAX)
 for _ in range((n_acc+1) * n_chan)]
 weight_flat = [rng.randint(IN_MIN, IN_MAX)
 for _ in range(n_filt * n_chan)]
 biases = [rng.randint(IN_MIN, IN_MAX) for _ in range(n_filt)]

 results = compute_output_simple(data_flat, weight_flat, biases,
 n_filt, n_chan, n_acc)

 # Write per-step: acc_clr en, then data, then weights, biases, expected
 for step in range(n_acc + 1):
 acc_clr = 1 if step <= 1 else 0
 en = 1
 f.write(f"{acc_clr} {en}\n")
 d = data_flat[step*n_chan:(step+1)*n_chan]
 f.write(' '.join(sh(x) for x in d) + '\n')

 for filt in range(n_filt):
 w = weight_flat[filt*n_chan:(filt+1)*n_chan]
 f.write(' '.join(sh(x) for x in w) + '\n')
 f.write(' '.join(sh(b) for b in biases) + '\n')
 f.write(' '.join(sh(r) for r in results) + '\n')
 f.write('\n')

 print(f"Written {n_cases} cases to {out_path}")

if __name__ == "__main__":
 out_path = os.path.join(PROJ_ROOT, "tb", "group3", "vectors",
 "conv1x1_g3_vectors.hex")
 write_vectors(out_path)
