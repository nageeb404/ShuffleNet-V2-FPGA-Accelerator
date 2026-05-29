"""
gen_conv1x1_filter_unit_vectors.py
====================================
Generate test vectors for conv1x1_filter_unit (Module 2.4).


29 MACs -> adder_tree_29 -> accumulate N_ACC times -> bias -> ReLU quant.

The maximum number of accumulations tested is N_ACC (default 7).
We test 1, 2, 4, and 7 accumulations as well as random cases.

File format: (N_ACC + 2) lines per test case
 Lines 0..N_ACC-1: d[0..28] w[0..28] (29+29=58 hex values, 15-bit each)
 Line N_ACC: bias expected (2 hex values, 15-bit)

(N_ACC is written as a comment on the first data line's header.)

Pipeline timing (same pattern as conv3x3_filter_unit):
 For N_ACC accumulations:
 negedge 0: drive row0, en=1, acc_clr=1
 negedge 1: drive row1, acc_clr=1 (posedge 0: acc = tree(stale))
 negedge 2..N_ACC-1: drive row k, acc_clr=0 (posedge 1: acc = tree(row0))
 negedge N_ACC: drive last row, acc_clr=0
 negedge N_ACC+1: wait (posedge N_ACC: acc = final sum)
 negedge N_ACC+2: CHECK result (bias+quant combinationally valid)

For simplicity, we fix N_ACC=7 for all cases in this vector file and use
zero-padding for rows that don't contribute (all-zeros rows are neutral).
The generator computes the correct result for the chosen inputs.
"""

import random, os
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")

DATA_W = 15
MUL_FULL_W = 30
MUL_DROP = 7
MAC_OUT_W = MUL_FULL_W - MUL_DROP # 23
TREE_OUT_W = MAC_OUT_W + 8 # 31 (4 Adder3 levels)
ACC_OUT_W = TREE_OUT_W + 3 # 34
BIAS_OUT_W = ACC_OUT_W + 1 # 35
N_CHAN = 29
N_ACC = 7 # fixed accumulation count ( max)

DATA_MAX = (1 << (DATA_W - 1)) - 1
DATA_MIN = -(1 << (DATA_W - 1))


def mask(w): return (1 << w) - 1
def to_uns(v, w): return int(v) & mask(w)
def to_sgn(u, w):
 u = int(u) & mask(w)
 return u - (1 << w) if (u >> (w - 1)) else u
def hex_str(v, w): return f"{to_uns(v, w):0{(w+3)//4}x}"


def model_mac(a, b):
 full = int(a) * int(b)
 dropped = full >> MUL_DROP
 return to_sgn(to_uns(dropped, MAC_OUT_W), MAC_OUT_W)


def model_adder3(a_s, b_s, c_s, in_w):
 out_w = in_w + 2
 a = to_uns(a_s, out_w); b = to_uns(b_s, out_w); c = to_uns(c_s, out_w)
 sv = cv = 0
 for i in range(out_w):
 ai = (a >> i) & 1; bi = (b >> i) & 1; ci = (c >> i) & 1
 sv |= (ai ^ bi ^ ci) << i
 cv |= ((ai & bi) | (bi & ci) | (ai & ci)) << i
 carry_s = (cv << 1) & mask(out_w)
 raw = to_sgn(sv, out_w) + to_sgn(carry_s, out_w)
 return to_sgn(to_uns(raw, out_w), out_w)


def model_adder_tree_29(macs):
 L1_W = MAC_OUT_W + 2
 L2_W = L1_W + 2
 L3_W = L2_W + 2
 l1 = [model_adder3(macs[3*i], macs[3*i+1], macs[3*i+2], MAC_OUT_W) for i in range(9)]
 l2 = [model_adder3(l1[3*i], l1[3*i+1], l1[3*i+2], L1_W) for i in range(3)]
 l3 = model_adder3(l2[0], l2[1], l2[2], L2_W)
 in27_ext = to_sgn(to_uns(macs[27], L3_W), L3_W)
 in28_ext = to_sgn(to_uns(macs[28], L3_W), L3_W)
 return model_adder3(l3, in27_ext, in28_ext, L3_W)


def model_quantizer_onesided(v, in_w, out_w):
 """One-sided saturating quantizer with ReLU (HAS_RELU=1)."""
 out_max = (1 << (out_w - 1)) - 1
 v_s = to_sgn(to_uns(v, in_w), in_w)
 if v_s < 0: return 0 # ReLU clamp
 if v_s > out_max: return out_max
 return v_s


def model_conv1x1_filter(rows, bias):
 """
 Bit-true model of conv1x1_filter_unit.
 rows: list of N_ACC lists, each with N_CHAN signed Q6.8 values (data and weights)
 Each rows[k] = (data[29], weights[29])
 bias: signed Q6.8
 """
 acc = 0 # 34-bit signed accumulator
 for data, weights in rows:
 macs = [model_mac(data[i], weights[i]) for i in range(N_CHAN)]
 tree_out = model_adder_tree_29(macs)
 # sign-extend tree to ACC_OUT_W
 tree_ext = to_sgn(to_uns(tree_out, ACC_OUT_W), ACC_OUT_W)
 acc = to_sgn(to_uns(acc + tree_ext, ACC_OUT_W), ACC_OUT_W)
 # Bias add
 acc_ext = to_sgn(to_uns(acc, BIAS_OUT_W), BIAS_OUT_W)
 bias_ext = to_sgn(to_uns(bias, BIAS_OUT_W), BIAS_OUT_W)
 bias_sum = to_sgn(to_uns(acc_ext + bias_ext, BIAS_OUT_W), BIAS_OUT_W)
 return model_quantizer_onesided(bias_sum, BIAS_OUT_W, DATA_W)


def rand_q68:
 return random.randint(DATA_MIN, DATA_MAX)


def write_vectors(out_path, n_random=100):
 # Each case: list of N_ACC (data_list, weight_list) pairs, plus bias
 cases = []

 def zero_row: return ([0]*N_CHAN, [0]*N_CHAN)
 def ones_row: return ([1]*N_CHAN, [1]*N_CHAN)
 def max_row: return ([DATA_MAX]*N_CHAN, [DATA_MAX]*N_CHAN)
 def min_row: return ([DATA_MIN]*N_CHAN, [DATA_MIN]*N_CHAN)
 def rand_row: return ([rand_q68 for _ in range(N_CHAN)],
 [rand_q68 for _ in range(N_CHAN)])

 # Deterministic edge cases
 cases.append(([zero_row]*N_ACC, 0))
 cases.append(([ones_row]*N_ACC, 0))
 cases.append(([max_row]*N_ACC, DATA_MAX)) # saturate positive
 cases.append(([min_row]*N_ACC, DATA_MAX)) # neg*neg sums, may saturate
 cases.append(([zero_row]*N_ACC, DATA_MAX)) # bias only, saturates positive
 cases.append(([zero_row]*N_ACC, DATA_MIN)) # negative bias, ReLU clamps to 0

 # Mix: some real rows, rest zeros
 for k in [1, 2, 4, 7]:
 rows = [rand_row for _ in range(k)] + [zero_row]*(N_ACC - k)
 cases.append((rows, rand_q68))

 # Random cases
 for _ in range(n_random):
 rows = [rand_row for _ in range(N_ACC)]
 cases.append((rows, rand_q68))

 out_dir = Path(out_path).parent
 out_dir.mkdir(parents=True, exist_ok=True)

 with open(out_path, "w") as f:
 f.write("// conv1x1_filter_unit test vectors\n")
 f.write(f"// N_ACC={N_ACC} fixed accumulations per case\n")
 f.write(f"// Format: {N_ACC+1} lines per case\n")
 f.write(f"// Lines 0..{N_ACC-1}: d0..d28 w0..w28 (58 x 4-hex values)\n")
 f.write(f"// Line {N_ACC}: bias expected (2 x 4-hex values)\n")
 for rows, bias in cases:
 result = model_conv1x1_filter(rows, bias)
 for data, weights in rows:
 d_hex = " ".join(hex_str(v, DATA_W) for v in data)
 w_hex = " ".join(hex_str(v, DATA_W) for v in weights)
 f.write(f"{d_hex} {w_hex}\n")
 f.write(f"{hex_str(bias, DATA_W)} {hex_str(result, DATA_W)}\n")

 print(f"Written {len(cases)} test cases to {out_path}")
 return len(cases)


if __name__ == "__main__":
 out_path = os.path.join(PROJ_ROOT, "tb", "group2", "vectors",
 "conv1x1_filter_unit_vectors.hex")
 n = write_vectors(out_path)
 print(f"Done. {n} cases.")
