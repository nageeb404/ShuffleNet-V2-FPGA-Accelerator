#!/usr/bin/env python3
# =============================================================================
# gen_conv3x3_filter_unit_vectors.py
# -----------------------------------------------------------------------------
# Generate golden test vectors for conv3x3_filter_unit (Module 1.3a).
# The filter unit takes 9 data + 9 weights per clock cycle and accumulates
# for 3 cycles (one per row of the 3x3 window across 3 channels), then adds
# a bias, applies ReLU, and quantizes to Q6.8.
# File format: 4 lines per test case
# Line 1: d[0..8] w[0..8] (9+9=18 hex values, row 0)
# Line 2: d[0..8] w[0..8] (18 hex values, row 1)
# Line 3: d[0..8] w[0..8] (18 hex values, row 2)
# Line 4: bias expected (2 hex values)
# All values are 15-bit two's complement hex (4 digits, unsigned encoding).
# =============================================================================

import random
import sys
from pathlib import Path

# ---- Bit-width constants (match shufflenet_pkg.vh) ----
DATA_W = 15
MUL_FULL_W = 30
MUL_DROP = 7
MAC_OUT_W = MUL_FULL_W - MUL_DROP # 23
TREE_OUT_W = MAC_OUT_W + 4 # 27 (2 Adder3 levels x +2)
ACC_W = TREE_OUT_W + 2 # 29 (ceil(log2(3)) = 2)
BIAS_OUT_W = ACC_W + 1 # 30 (2-input bias adder)
OUT_W = DATA_W # 15

DATA_MAX = (1 << (DATA_W - 1)) - 1 # +16383
DATA_MIN = -(1 << (DATA_W - 1)) # -16384
N_ROWS = 3
N_TAPS = 9


# ---- Bit-manipulation helpers ----

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


# ---- Bit-true RTL models ----

def model_mac(a, b):
 """mac_unit: signed 15x15 -> 30 bits, drop 7 LSBs -> 23 bits signed."""
 full = int(a) * int(b) # exact signed product (Python bigint)
 # Arithmetic right shift by MUL_DROP (truncation toward -inf)
 # Python >> on ints is arithmetic, so this is correct for negatives too.
 dropped = full >> MUL_DROP
 return to_sgn(to_uns(dropped, MAC_OUT_W), MAC_OUT_W)


def model_adder3(a_s, b_s, c_s, in_w):
 """Bit-true Adder3 (matches Adder3.v: CSA then 2-input CPA)."""
 out_w = in_w + 2
 a = to_uns(a_s, out_w)
 b = to_uns(b_s, out_w)
 c = to_uns(c_s, out_w)
 sum_v = carry_v = 0
 for i in range(out_w):
 ai = (a >> i) & 1
 bi = (b >> i) & 1
 ci = (c >> i) & 1
 sum_v |= (ai ^ bi ^ ci) << i
 carry_v |= ((ai & bi) | (bi & ci) | (ai & ci)) << i
 carry_s = (carry_v << 1) & mask(out_w)
 raw = to_sgn(sum_v, out_w) + to_sgn(carry_s, out_w)
 return to_sgn(to_uns(raw, out_w), out_w)


def model_adder_tree_9(macs):
 """9-input adder tree: 3 Adder3 at L1, 1 Adder3 at L2."""
 l1_0 = model_adder3(macs[0], macs[1], macs[2], MAC_OUT_W)
 l1_1 = model_adder3(macs[3], macs[4], macs[5], MAC_OUT_W)
 l1_2 = model_adder3(macs[6], macs[7], macs[8], MAC_OUT_W)
 return model_adder3(l1_0, l1_1, l1_2, MAC_OUT_W + 2)


def model_filter_unit(data_rows, weight_rows, bias):
 """
 Bit-true model of conv3x3_filter_unit.v.
 data_rows : list of 3 lists of 9 signed Q6.8 ints
 weight_rows: list of 3 lists of 9 signed Q6.8 ints
 bias : signed Q6.8 int
 Returns : signed 15-bit Q6.8 result
 """
 acc = 0
 for row in range(N_ROWS):
 macs = [model_mac(data_rows[row][j], weight_rows[row][j])
 for j in range(N_TAPS)]
 tree_out = model_adder_tree_9(macs)
 # Accumulate into ACC_W-bit register (wraps in simulation)
 acc = to_sgn(to_uns(acc + tree_out, ACC_W), ACC_W)

 # Bias addition -> BIAS_OUT_W bits
 bias_sum = to_sgn(to_uns(acc + bias, BIAS_OUT_W), BIAS_OUT_W)

 # ReLU: clamp negative to 0
 relu_out = 0 if bias_sum < 0 else bias_sum

 # Quantizer (HAS_RELU=1): max-clamp only
 if relu_out > DATA_MAX:
 return DATA_MAX
 return relu_out # already >= 0, fits in DATA_W-1 bits


# ---- Vector generation ----

def rand_q68:
 return random.randint(DATA_MIN, DATA_MAX)


def write_case(f, data_rows, weight_rows, bias):
 result = model_filter_unit(data_rows, weight_rows, bias)
 for row in range(N_ROWS):
 d_hex = " ".join(hex_str(v, DATA_W) for v in data_rows[row])
 w_hex = " ".join(hex_str(v, DATA_W) for v in weight_rows[row])
 f.write(f"{d_hex} {w_hex}\n")
 f.write(f"{hex_str(bias, DATA_W)} {hex_str(result, DATA_W)}\n")


def gen_vectors(out_path: Path, n_random: int = 200):
 dmax, dmin = DATA_MAX, DATA_MIN
 cases = []

 # ---- Deterministic edge cases ----
 # all zeros
 cases.append(([[0]*9]*3, [[0]*9]*3, 0))
 # zero data, max weights -> product=0 -> result=0
 cases.append(([[0]*9]*3, [[dmax]*9]*3, 0))
 # data=1, weight=1, bias=0 -> small positive accumulation
 cases.append(([[1]*9]*3, [[1]*9]*3, 0))
 # max positive data x max positive weight -> saturates at DATA_MAX
 cases.append(([[dmax]*9]*3, [[dmax]*9]*3, dmax))
 # all min data x all min weight -> positive (neg*neg) -> likely saturates
 cases.append(([[dmin]*9]*3, [[dmin]*9]*3, 0))
 # alternating max/min data, weight=1 -> partial cancellation
 cases.append(([[dmax, dmin] * 4 + [0]] * 3, [[1] * 9] * 3, 0))
 # bias dominates positive -> saturates
 cases.append(([[0]*9]*3, [[0]*9]*3, dmax))
 # bias negative, zero accumulation -> ReLU clamps to 0
 cases.append(([[0]*9]*3, [[0]*9]*3, dmin))
 # small positive accumulation, huge negative bias -> 0 after ReLU
 cases.append(([[1]*9]*3, [[1]*9]*3, dmin))
 # data=max, weight=-1 -> negative products -> likely 0 after ReLU
 cases.append(([[dmax]*9]*3, [[-1]*9]*3, 0))
 # unit impulse: single non-zero tap
 cases.append(([[1, 0, 0, 0, 0, 0, 0, 0, 0]] * 3,
 [[1, 0, 0, 0, 0, 0, 0, 0, 0]] * 3, 0))
 # positive accumulation, zero bias
 cases.append(([[100]*9]*3, [[100]*9]*3, 0))
 # negative data, positive weight -> negative sum -> ReLU=0
 cases.append([[[dmin // 2] * 9] * 3, [[1] * 9] * 3, 0])

 # ---- Random fuzz ----
 random.seed(0xBEEF1234)
 for _ in range(n_random):
 dr = [[rand_q68 for _ in range(N_TAPS)] for _ in range(N_ROWS)]
 wr = [[rand_q68 for _ in range(N_TAPS)] for _ in range(N_ROWS)]
 b = rand_q68
 cases.append((dr, wr, b))

 total = len(cases)
 with open(out_path, "w") as f:
 f.write("// conv3x3_filter_unit golden test vectors\n")
 f.write("// -- Module 1.3a\n")
 f.write("// 4 lines per test case:\n")
 f.write("// row0: d[0..8] w[0..8] (18 x 15-bit hex)\n")
 f.write("// row1: d[0..8] w[0..8] (18 x 15-bit hex)\n")
 f.write("// row2: d[0..8] w[0..8] (18 x 15-bit hex)\n")
 f.write("// bias(15b) expected_result(15b)\n")
 f.write(f"// n_cases={total}\n")
 for (dr, wr, b) in cases:
 write_case(f, dr, wr, b)

 print(f"[conv3x3_filter_unit] Wrote {total} test cases ({total * 4} lines) "
 f"to {out_path}")
 return total


def main:
 if len(sys.argv) > 1:
 out_dir = Path(sys.argv[1])
 else:
 out_dir = (Path(__file__).resolve.parent.parent.parent
 / "tb" / "group1" / "vectors")
 out_dir.mkdir(parents=True, exist_ok=True)
 gen_vectors(out_dir / "conv3x3_filter_unit_vectors.hex")
 print("Done.")


if __name__ == "__main__":
 main
