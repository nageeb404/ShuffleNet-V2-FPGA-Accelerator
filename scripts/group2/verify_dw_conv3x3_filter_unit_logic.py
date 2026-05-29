#!/usr/bin/env python3
"""
verify_dw_conv3x3_filter_unit_logic.py
========================================
Bit-true shadow simulator for dw_conv3x3_filter_unit (Module 2.1).
Reads the generated hex vectors and re-derives expected outputs independently,
then cross-checks against the stored expected values.
"""

import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve.parent
PROJ_ROOT = SCRIPT_DIR.parent.parent

DATA_W = 15
MUL_FULL_W = 30
MUL_DROP = 7
MAC_OUT_W = MUL_FULL_W - MUL_DROP # 23
TREE_OUT_W = MAC_OUT_W + 4 # 27
BIAS_OUT_W = TREE_OUT_W + 1 # 28


def mask(w): return (1 << w) - 1
def to_uns(v, w): return int(v) & mask(w)
def to_sgn(u, w):
 u = int(u) & mask(w)
 return u - (1 << w) if (u >> (w - 1)) else u


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


def model_adder_tree_9(macs):
 l1_0 = model_adder3(macs[0], macs[1], macs[2], MAC_OUT_W)
 l1_1 = model_adder3(macs[3], macs[4], macs[5], MAC_OUT_W)
 l1_2 = model_adder3(macs[6], macs[7], macs[8], MAC_OUT_W)
 return model_adder3(l1_0, l1_1, l1_2, MAC_OUT_W + 2)


def model_quantizer_twosided(v, in_w, out_w):
 out_max = (1 << (out_w - 1)) - 1
 out_min = -(1 << (out_w - 1))
 v_s = to_sgn(to_uns(v, in_w), in_w)
 if v_s > out_max: return out_max
 if v_s < out_min: return out_min
 return v_s


def model_dw_filter_unit(data, weights, bias):
 macs = [model_mac(data[i], weights[i]) for i in range(9)]
 tree_out = model_adder_tree_9(macs)
 tree_ext = to_sgn(to_uns(tree_out, BIAS_OUT_W), BIAS_OUT_W)
 bias_ext = to_sgn(to_uns(bias, BIAS_OUT_W), BIAS_OUT_W)
 bias_sum = to_sgn(to_uns(tree_ext + bias_ext, BIAS_OUT_W), BIAS_OUT_W)
 return model_quantizer_twosided(bias_sum, BIAS_OUT_W, DATA_W)


def parse_vectors(path):
 """Parse 2-line-per-case format: line1 = d0..d8 w0..w8, line2 = bias expected."""
 cases = []
 with open(path) as f:
 lines = [l.strip for l in f if l.strip and not l.strip.startswith("//")]
 i = 0
 while i + 1 < len(lines):
 toks1 = lines[i].split
 toks2 = lines[i + 1].split
 if len(toks1) == 18 and len(toks2) == 2:
 d = [to_sgn(int(t, 16), DATA_W) for t in toks1[:9]]
 w = [to_sgn(int(t, 16), DATA_W) for t in toks1[9:]]
 b = to_sgn(int(toks2[0], 16), DATA_W)
 e = to_sgn(int(toks2[1], 16), DATA_W)
 cases.append((d, w, b, e))
 i += 2
 return cases


def main:
 vec_path = PROJ_ROOT / "tb" / "group2" / "vectors" / "dw_conv3x3_filter_unit_vectors.hex"
 if not vec_path.exists:
 print(f"ERROR: vector file not found: {vec_path}")
 sys.exit(1)

 cases = parse_vectors(vec_path)
 print("=" * 70)
 print(f"DW_CONV3X3_FILTER_UNIT SHADOW SIM ({len(cases)} cases)")
 print("=" * 70)

 fail = 0
 for idx, (d, w, b, expected) in enumerate(cases):
 got = model_dw_filter_unit(d, w, b)
 if got != expected:
 fail += 1
 if fail <= 10:
 print(f" FAIL case {idx}: got={got} expected={expected}")
 print(f" d={d}")
 print(f" w={w} bias={b}")

 print(f"\nPASS: {len(cases)-fail}/{len(cases)}")
 if fail == 0:
 print("RESULT: *** ALL CHECKS PASSED ***")
 sys.exit(0)
 else:
 print(f"RESULT: *** {fail} FAILURES ***")
 sys.exit(1)


if __name__ == "__main__":
 main
