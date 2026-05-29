#!/usr/bin/env python3
"""
verify_conv1x1_filter_unit_logic.py
=====================================
Bit-true shadow simulator for conv1x1_filter_unit (Module 2.4).
"""

import sys
from pathlib import Path

PROJ_ROOT = Path(__file__).resolve.parent.parent.parent

DATA_W = 15
MUL_DROP = 7
MAC_OUT_W = 30 - MUL_DROP # 23
TREE_OUT_W = MAC_OUT_W + 8 # 31
ACC_OUT_W = TREE_OUT_W + 3 # 34
BIAS_OUT_W = ACC_OUT_W + 1 # 35
N_CHAN = 29
N_ACC = 7


def mask(w): return (1 << w) - 1
def to_uns(v, w): return int(v) & mask(w)
def to_sgn(u, w):
 u = int(u) & mask(w)
 return u - (1 << w) if (u >> (w - 1)) else u


def model_mac(a, b):
 return to_sgn(to_uns((int(a) * int(b)) >> MUL_DROP, MAC_OUT_W), MAC_OUT_W)


def model_adder3(a_s, b_s, c_s, in_w):
 out_w = in_w + 2
 a = to_uns(a_s, out_w); b = to_uns(b_s, out_w); c = to_uns(c_s, out_w)
 sv = cv = 0
 for i in range(out_w):
 ai = (a >> i) & 1; bi = (b >> i) & 1; ci = (c >> i) & 1
 sv |= (ai ^ bi ^ ci) << i
 cv |= ((ai & bi) | (bi & ci) | (ai & ci)) << i
 carry_s = (cv << 1) & mask(out_w)
 return to_sgn(to_uns(to_sgn(sv, out_w) + to_sgn(carry_s, out_w), out_w), out_w)


def model_tree29(macs):
 L1_W = MAC_OUT_W + 2
 L2_W = L1_W + 2
 L3_W = L2_W + 2
 l1 = [model_adder3(macs[3*i], macs[3*i+1], macs[3*i+2], MAC_OUT_W) for i in range(9)]
 l2 = [model_adder3(l1[3*i], l1[3*i+1], l1[3*i+2], L1_W) for i in range(3)]
 l3 = model_adder3(l2[0], l2[1], l2[2], L2_W)
 in27_ext = to_sgn(to_uns(macs[27], L3_W), L3_W)
 in28_ext = to_sgn(to_uns(macs[28], L3_W), L3_W)
 return model_adder3(l3, in27_ext, in28_ext, L3_W)


def model_quant_onesided(v, in_w, out_w):
 out_max = (1 << (out_w - 1)) - 1
 v_s = to_sgn(to_uns(v, in_w), in_w)
 if v_s < 0: return 0
 if v_s > out_max: return out_max
 return v_s


def model_conv1x1_filter(rows, bias):
 acc = 0
 for data, weights in rows:
 macs = [model_mac(data[i], weights[i]) for i in range(N_CHAN)]
 tree_out = model_tree29(macs)
 tree_ext = to_sgn(to_uns(tree_out, ACC_OUT_W), ACC_OUT_W)
 acc = to_sgn(to_uns(acc + tree_ext, ACC_OUT_W), ACC_OUT_W)
 acc_ext = to_sgn(to_uns(acc, BIAS_OUT_W), BIAS_OUT_W)
 bias_ext = to_sgn(to_uns(bias, BIAS_OUT_W), BIAS_OUT_W)
 bias_sum = to_sgn(to_uns(acc_ext + bias_ext, BIAS_OUT_W), BIAS_OUT_W)
 return model_quant_onesided(bias_sum, BIAS_OUT_W, DATA_W)


def parse_vectors(path):
 cases = []
 with open(path) as f:
 lines = [l.strip for l in f if l.strip and not l.strip.startswith("//")]
 i = 0
 while i + N_ACC < len(lines):
 rows = []
 ok = True
 for k in range(N_ACC):
 toks = lines[i+k].split
 if len(toks) != 2*N_CHAN:
 ok = False; break
 d = [to_sgn(int(toks[j], 16), DATA_W) for j in range(N_CHAN)]
 w = [to_sgn(int(toks[N_CHAN+j], 16), DATA_W) for j in range(N_CHAN)]
 rows.append((d, w))
 if not ok:
 i += 1; continue
 bias_line = lines[i + N_ACC].split
 if len(bias_line) < 2:
 i += N_ACC + 1; continue
 bias = to_sgn(int(bias_line[0], 16), DATA_W)
 exp = to_sgn(int(bias_line[1], 16), DATA_W)
 cases.append((rows, bias, exp))
 i += N_ACC + 1
 return cases


def main:
 vec_path = PROJ_ROOT / "tb" / "group2" / "vectors" / "conv1x1_filter_unit_vectors.hex"
 if not vec_path.exists:
 print(f"ERROR: {vec_path} not found"); sys.exit(1)

 cases = parse_vectors(vec_path)
 print("=" * 70)
 print(f"CONV1X1_FILTER_UNIT SHADOW SIM N_ACC={N_ACC} ({len(cases)} cases)")
 print("=" * 70)

 fail = 0
 for idx, (rows, bias, expected) in enumerate(cases):
 got = model_conv1x1_filter(rows, bias)
 if got != expected:
 fail += 1
 if fail <= 10:
 print(f" FAIL case {idx}: got={got} expected={expected}")

 print(f"\nPASS: {len(cases)-fail}/{len(cases)}")
 if fail == 0:
 print("RESULT: *** ALL CHECKS PASSED ***"); sys.exit(0)
 else:
 print(f"RESULT: *** {fail} FAILURES ***"); sys.exit(1)


if __name__ == "__main__":
 main
