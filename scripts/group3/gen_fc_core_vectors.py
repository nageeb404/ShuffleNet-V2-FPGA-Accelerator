"""
gen_fc_core_vectors.py
=======================
Generate test vectors for fc_core (Module 3.3).


fc_core processes one class at a time, accumulating 32 channels per step
over N_ACC=32 steps (covering all 1024 input channels).

Model:
 step 0: acc_clr=1, en=1 -> acc = tree_sum (replaces old value)
 steps 1..N_ACC-1: acc_clr=0, en=1 -> acc += tree_sum
 result available after step N_ACC-1

Pipeline behaviour matches fc_filter_unit:
 - MAC registers capture d*w at posedge; tree sum is combinational
 - acc_clr=1 at step 0: acc <- tree (from step-1 MAC regs, initially 0)
 - This matches conv1x1_filter_unit behavior (steps 0,1 are pipeline settling)

Vector format per case:
 Header: N_PAR N_ACC (32 32)
 N_ACC+1 groups (step 0..N_ACC, including the "wait" step):
 Line 1: acc_clr en
 Line 2: d0..d31 (32 hex values)
 Line 3: w0..w31 (32 hex values)
 Bias line: bias (1 hex value)
 Expected result line: result (1 hex value)
"""
import os, random, math
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")

DATA_W = 15
MUL_W = 23
TREE_W = MUL_W + 7 # 30
N_ACC = 32 # accumulation steps (1024 channels / 32 per step)
N_PAR = 32
ACC_W = TREE_W + 5 # 35
BIAS_W = ACC_W + 1 # 36

IN_MIN = -(1 << (DATA_W-1))
IN_MAX = (1 << (DATA_W-1)) - 1

def to_signed(v, bits):
 mask = (1 << bits) - 1
 v &= mask
 if v >= (1 << (bits-1)):
 v -= (1 << bits)
 return v

def mac_unit(d, w):
 raw = d * w
 return to_signed(raw >> 7, MUL_W)

def adder_tree_32(prods):
 return sum(prods)

def quantize_twosided(v, out_w=DATA_W):
 """Two-sided saturating quantizer (no ReLU -- FC output can be negative)."""
 hi = (1 << (out_w-1)) - 1
 lo = -(1 << (out_w-1))
 if v > hi: return hi
 if v < lo: return lo
 return v

def simulate_fc_filter(data_steps, weights, bias, n_acc=N_ACC):
 """
 data_steps: list of n_acc+1 lists, each of length n_par (step data)
 weights: list of n_par weights (fixed for one class)
 bias: integer bias
 Returns expected result (quantized, ReLU applied)
 """
 mac_reg = [0] * N_PAR # initially 0 (after reset)
 acc = 0
 for step in range(n_acc + 1):
 # Combinational tree uses REGISTERED mac outputs
 tree = adder_tree_32(mac_reg)
 tree = to_signed(tree, TREE_W)
 # Determine acc_clr
 acc_clr = (step <= 1) # first 2 steps: pipeline settling
 if step < n_acc:
 # Load new MAC register
 d = data_steps[step]
 new_mac = [mac_unit(d[c], weights[c]) for c in range(N_PAR)]
 mac_reg = new_mac
 if acc_clr:
 acc = to_signed(tree, ACC_W)
 else:
 acc = to_signed(acc + tree, ACC_W)
 # Add bias
 total = to_signed(acc + bias, BIAS_W)
 return quantize_twosided(total)

def sh(v, w=DATA_W):
 mask = (1 << w) - 1
 return format(v & mask, f'0{(w+3)//4}x')

def write_vectors(out_path, n_cases=8, seed=7):
 rng = random.Random(seed)
 Path(out_path).parent.mkdir(parents=True, exist_ok=True)

 with open(out_path, 'w') as f:
 f.write(f"// fc_core vectors: N_PAR={N_PAR} N_ACC={N_ACC}\n")

 for case_idx in range(n_cases):
 # Generate random data and weights
 data_steps = [[rng.randint(IN_MIN, IN_MAX) for _ in range(N_PAR)]
 for _ in range(N_ACC + 1)]
 weights = [rng.randint(IN_MIN, IN_MAX) for _ in range(N_PAR)]
 bias = rng.randint(IN_MIN, IN_MAX)

 expected = simulate_fc_filter(data_steps, weights, bias)

 f.write(f"\n// Case {case_idx}\n")
 f.write(f"{N_PAR} {N_ACC}\n")
 for step in range(N_ACC + 1):
 acc_clr = 1 if step <= 1 else 0
 en = 1
 f.write(f"{acc_clr} {en}\n")
 f.write(' '.join(sh(v) for v in data_steps[step]) + '\n')
 f.write(' '.join(sh(v) for v in weights) + '\n')
 f.write(sh(bias) + '\n')
 f.write(sh(expected) + '\n')

 print(f"Written {n_cases} cases to {out_path}")

if __name__ == "__main__":
 out_path = os.path.join(PROJ_ROOT, "tb", "group3", "vectors",
 "fc_core_vectors.hex")
 write_vectors(out_path)
