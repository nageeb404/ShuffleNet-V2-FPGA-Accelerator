#!/usr/bin/env python3
# =============================================================================
# gen_conv3x3_core_vectors.py
# -----------------------------------------------------------------------------
# Generate golden test vectors for conv3x3_core (Module 1.3b).
# The core is 24 parallel conv3x3_filter_unit instances sharing the same
# 9 data inputs. Each filter has its own 9 weights (per accumulation row)
# and 1 bias.
# File format: 123 lines per test case
# Row r (r=0,1,2): 25 lines
# Line 1: 9 shared data values (hex, 15-bit)
# Lines 2-25: one weight line per filter (9 hex values each, filter 0..23)
# Lines 76-99: bias for each filter, 1 hex value per line (filter 0..23)
# Lines 100-123: expected result per filter, 1 hex value per line
# All hex values are 15-bit two's-complement (4 hex digits).
# =============================================================================

import random
import sys
from pathlib import Path

# ---- Constants (match shufflenet_pkg.vh) ----
DATA_W = 15
MUL_FULL_W = 30
MUL_DROP = 7
MAC_OUT_W = MUL_FULL_W - MUL_DROP # 23
L1_W = MAC_OUT_W + 2 # 25
TREE_OUT_W = L1_W + 2 # 27
ACC_W = TREE_OUT_W + 2 # 29
BIAS_OUT_W = ACC_W + 1 # 30

DATA_MAX = (1 << (DATA_W - 1)) - 1 # +16383
DATA_MIN = -(1 << (DATA_W - 1)) # -16384
N_FILT = 24
N_ROWS = 3
N_TAPS = 9


# ---- Bit helpers (same as filter_unit generator) ----

def mask(w):
 return (1 << w) - 1

def to_uns(v, w):
 return int(v) & mask(w)

def to_sgn(u, w):
 u = int(u) & mask(w)
 return u - (1 << w) if (u >> (w - 1)) else u

def hex_str(v, w):
 digits = (w + 3) // 4
 return f"{to_uns(v, w):0{digits}x}"


# ---- Bit-true component models (identical to filter unit) ----

def model_mac(a, b):
 full = int(a) * int(b)
 shifted = full >> MUL_DROP
 return to_sgn(to_uns(shifted, MAC_OUT_W), MAC_OUT_W)

def model_adder3(a_s, b_s, c_s, in_w):
 out_w = in_w + 2
 a = to_uns(a_s, out_w); b = to_uns(b_s, out_w); c = to_uns(c_s, out_w)
 sum_v = carry_v = 0
 for i in range(out_w):
 ai = (a >> i) & 1; bi = (b >> i) & 1; ci = (c >> i) & 1
 sum_v |= (ai ^ bi ^ ci) << i
 carry_v |= ((ai & bi) | (bi & ci) | (ai & ci)) << i
 carry_s = (carry_v << 1) & mask(out_w)
 raw = to_sgn(sum_v, out_w) + to_sgn(carry_s, out_w)
 return to_sgn(to_uns(raw, out_w), out_w)

def model_adder_tree_9(macs):
 l1_0 = model_adder3(macs[0], macs[1], macs[2], MAC_OUT_W)
 l1_1 = model_adder3(macs[3], macs[4], macs[5], MAC_OUT_W)
 l1_2 = model_adder3(macs[6], macs[7], macs[8], MAC_OUT_W)
 return model_adder3(l1_0, l1_1, l1_2, L1_W)

def model_filter_unit(data_rows, weight_rows, bias):
 """Bit-true single-filter result."""
 acc = 0
 for row in range(N_ROWS):
 macs = [model_mac(data_rows[row][j], weight_rows[row][j])
 for j in range(N_TAPS)]
 tree_out = model_adder_tree_9(macs)
 acc = to_sgn(to_uns(acc + tree_out, ACC_W), ACC_W)
 bias_sum = to_sgn(to_uns(acc + bias, BIAS_OUT_W), BIAS_OUT_W)
 relu_out = 0 if bias_sum < 0 else bias_sum
 return DATA_MAX if relu_out > DATA_MAX else relu_out

def model_core(data_rows, weights_per_filt, biases):
 """
 data_rows : list of 3 lists of 9 signed ints (shared)
 weights_per_filt : list of N_FILT, each a list of 3 lists of 9 signed ints
 biases : list of N_FILT signed ints
 Returns : list of N_FILT signed ints (results)
 """
 return [model_filter_unit(data_rows, weights_per_filt[f], biases[f])
 for f in range(N_FILT)]


# ---- Random helpers ----

def rand_q68:
 return random.randint(DATA_MIN, DATA_MAX)

def rand_data_rows:
 return [[rand_q68 for _ in range(N_TAPS)] for _ in range(N_ROWS)]

def rand_weights:
 return [rand_data_rows for _ in range(N_FILT)]

def rand_biases:
 return [rand_q68 for _ in range(N_FILT)]


# ---- Write one test case to file ----

def write_case(f_out, data_rows, weights_per_filt, biases, results):
 # 3 rows x (data + N_FILT weight lines)
 for row in range(N_ROWS):
 d_hex = " ".join(hex_str(v, DATA_W) for v in data_rows[row])
 f_out.write(d_hex + "\n")
 for filt in range(N_FILT):
 w_hex = " ".join(hex_str(v, DATA_W) for v in weights_per_filt[filt][row])
 f_out.write(w_hex + "\n")
 # biases (1 per line)
 for filt in range(N_FILT):
 f_out.write(hex_str(biases[filt], DATA_W) + "\n")
 # expected results (1 per line)
 for filt in range(N_FILT):
 f_out.write(hex_str(results[filt], DATA_W) + "\n")


def gen_vectors(out_path: Path, n_random: int = 18):
 cases = []
 dmax, dmin = DATA_MAX, DATA_MIN

 # ---- Edge cases ----
 # All zeros
 dr = [[0]*N_TAPS]*N_ROWS
 wf = [[[0]*N_TAPS]*N_ROWS for _ in range(N_FILT)]
 bs = [0]*N_FILT
 cases.append((dr, wf, bs))

 # Distinct filter weights to verify per-filter wiring
 # filter f gets weight = f+1 everywhere, data=1 everywhere, bias=0
 dr2 = [[1]*N_TAPS]*N_ROWS
 wf2 = [[[f+1]*N_TAPS]*N_ROWS for f in range(N_FILT)]
 bs2 = [0]*N_FILT
 cases.append((dr2, wf2, bs2))

 # Random cases
 random.seed(0xC0DE5EED)
 for _ in range(n_random):
 dr = rand_data_rows
 wf = rand_weights
 bs = rand_biases
 cases.append((dr, wf, bs))

 total = len(cases)
 with open(out_path, "w") as f_out:
 f_out.write("// conv3x3_core golden test vectors\n")
 f_out.write("// -- Module 1.3b\n")
 f_out.write("// 123 lines per test case:\n")
 f_out.write("// row r (r=0,1,2): data line (9 hex) + 24 weight lines (9 hex each)\n")
 f_out.write("// 24 bias lines (1 hex each)\n")
 f_out.write("// 24 expected result lines (1 hex each)\n")
 f_out.write(f"// n_cases={total}\n")
 for (dr, wf, bs) in cases:
 results = model_core(dr, wf, bs)
 write_case(f_out, dr, wf, bs, results)

 print(f"[conv3x3_core] Wrote {total} test cases "
 f"({total * 123} lines) to {out_path}")
 return total


def main:
 if len(sys.argv) > 1:
 out_dir = Path(sys.argv[1])
 else:
 out_dir = (Path(__file__).resolve.parent.parent.parent
 / "tb" / "group1" / "vectors")
 out_dir.mkdir(parents=True, exist_ok=True)
 gen_vectors(out_dir / "conv3x3_core_vectors.hex")
 print("Done.")


if __name__ == "__main__":
 main
