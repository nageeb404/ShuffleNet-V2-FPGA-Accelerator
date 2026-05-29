"""
gen_dw_conv3x3_filter_unit_vectors.py
======================================
Generate test vectors for dw_conv3x3_filter_unit (Module 2.1).


Differences from Group 1 filter unit:
 - Single-pass (no accumulation): 9 data * 9 weights -> tree -> bias -> quant
 - HAS_RELU = 0 (two-sided saturating quantizer)

File format: 2 lines per test case
 Line 1: d[0..8] w[0..8] (9+9=18 hex values, each 15-bit 2's-complement)
 Line 2: bias expected (2 hex values, 15-bit 2's-complement)

Pipeline timing:
 negedge 0: drive d[0..8], w[0..8], en=1
 negedge 1: drive bias; (MAC outputs settle after posedge 0)
 negedge 2: CHECK result (combinational from tree+bias after posedge 1)
"""

import random, os, sys
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")

DATA_W = 15
MUL_FULL_W = 30
MUL_DROP = 7
MAC_OUT_W = MUL_FULL_W - MUL_DROP # 23
TREE_OUT_W = MAC_OUT_W + 4 # 27 (2 Adder3 levels)
BIAS_OUT_W = TREE_OUT_W + 1 # 28

DATA_MAX = (1 << (DATA_W - 1)) - 1 # 16383
DATA_MIN = -(1 << (DATA_W - 1)) # -16384
N_TAPS = 9


# ---- Bit-manipulation helpers ----
def mask(w): return (1 << w) - 1
def to_uns(v, w): return int(v) & mask(w)
def to_sgn(u, w):
 u = int(u) & mask(w)
 return u - (1 << w) if (u >> (w-1)) else u
def hex_str(v, w): return f"{to_uns(v, w):0{(w+3)//4}x}"


# ---- Bit-true RTL models ----
def model_mac(a, b):
 full = int(a) * int(b)
 dropped = full >> MUL_DROP
 return to_sgn(to_uns(dropped, MAC_OUT_W), MAC_OUT_W)


def model_adder3(a_s, b_s, c_s, in_w):
 out_w = in_w + 2
 a = to_uns(a_s, out_w); b = to_uns(b_s, out_w); c = to_uns(c_s, out_w)
 sv = cv = 0
 for i in range(out_w):
 ai=(a>>i)&1; bi=(b>>i)&1; ci=(c>>i)&1
 sv |= (ai^bi^ci) << i
 cv |= ((ai&bi)|(bi&ci)|(ai&ci)) << i
 carry_s = (cv << 1) & mask(out_w)
 raw = to_sgn(sv, out_w) + to_sgn(carry_s, out_w)
 return to_sgn(to_uns(raw, out_w), out_w)


def model_adder_tree_9(macs):
 """9-input adder tree: 3 Adder3 at L1, 1 Adder3 at L2."""
 l1_0 = model_adder3(macs[0], macs[1], macs[2], MAC_OUT_W)
 l1_1 = model_adder3(macs[3], macs[4], macs[5], MAC_OUT_W)
 l1_2 = model_adder3(macs[6], macs[7], macs[8], MAC_OUT_W)
 return model_adder3(l1_0, l1_1, l1_2, MAC_OUT_W + 2)


def model_quantizer_twosided(v, in_w, out_w):
 """Two-sided saturating quantizer (HAS_RELU=0)."""
 out_max = (1 << (out_w - 1)) - 1
 out_min = -(1 << (out_w - 1))
 v_s = to_sgn(to_uns(v, in_w), in_w)
 if v_s > out_max: return out_max
 if v_s < out_min: return out_min
 return v_s


def model_dw_filter_unit(data, weights, bias):
 """
 Bit-true model of dw_conv3x3_filter_unit.
 data, weights: lists of 9 signed Q6.8 ints
 bias: signed Q6.8 int
 Returns: signed 15-bit Q6.8 result
 """
 macs = [model_mac(data[i], weights[i]) for i in range(N_TAPS)]
 tree_out = model_adder_tree_9(macs)
 # Sign-extend to BIAS_OUT_W
 tree_ext = to_sgn(to_uns(tree_out, BIAS_OUT_W), BIAS_OUT_W)
 bias_ext = to_sgn(to_uns(bias, BIAS_OUT_W), BIAS_OUT_W)
 bias_sum = to_sgn(to_uns(tree_ext + bias_ext, BIAS_OUT_W), BIAS_OUT_W)
 return model_quantizer_twosided(bias_sum, BIAS_OUT_W, DATA_W)


def rand_q68:
 return random.randint(DATA_MIN, DATA_MAX)


def write_vectors(out_path, n_random=200):
 cases = []

 # Deterministic edge cases
 cases += [
 ([0]*9, [0]*9, 0),
 ([1]*9, [1]*9, 0),
 ([DATA_MAX]*9, [DATA_MAX]*9, DATA_MAX), # saturates positive
 ([DATA_MIN]*9, [DATA_MIN]*9, 0), # neg*neg->pos, may saturate
 ([0]*9, [DATA_MAX]*9, 0),
 ([1]*9, [-1]*9, 0), # slight negative, no ReLU clamp
 ([DATA_MAX]*9, [DATA_MAX]*9, DATA_MIN), # bias drives negative
 ([0]*9, [0]*9, DATA_MAX),
 ([0]*9, [0]*9, DATA_MIN),
 ]

 # Random cases
 for _ in range(n_random):
 d = [rand_q68 for _ in range(N_TAPS)]
 w = [rand_q68 for _ in range(N_TAPS)]
 b = rand_q68
 cases.append((d, w, b))

 out_dir = Path(out_path).parent
 out_dir.mkdir(parents=True, exist_ok=True)

 with open(out_path, "w") as f:
 f.write("// dw_conv3x3_filter_unit test vectors\n")
 f.write("// Format: 2 lines per case\n")
 f.write("// Line 1: d0..d8 w0..w8 (18 x 4-hex values)\n")
 f.write("// Line 2: bias expected (2 x 4-hex values)\n")
 for d, w, b in cases:
 result = model_dw_filter_unit(d, w, b)
 d_hex = " ".join(hex_str(v, DATA_W) for v in d)
 w_hex = " ".join(hex_str(v, DATA_W) for v in w)
 f.write(f"{d_hex} {w_hex}\n")
 f.write(f"{hex_str(b, DATA_W)} {hex_str(result, DATA_W)}\n")

 print(f"Written {len(cases)} test cases to {out_path}")
 return len(cases)


if __name__ == "__main__":
 out_path = os.path.join(PROJ_ROOT, "tb", "group2", "vectors",
 "dw_conv3x3_filter_unit_vectors.hex")
 n = write_vectors(out_path)
 print(f"Done. {n} cases.")
