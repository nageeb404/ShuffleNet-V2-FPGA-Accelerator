#!/usr/bin/env python3
"""
verify_dw_conv3x3_core_logic.py
=================================
Bit-true shadow simulator for dw_conv3x3_core (Module 2.2).
Format: 58 lines per case, each line = d0..d8 w0..w8 bias expected (20 tokens).
"""

import sys
from pathlib import Path

PROJ_ROOT = Path(__file__).resolve().parent.parent.parent

DATA_W     = 15
MUL_DROP   = 7
MAC_OUT_W  = 30 - MUL_DROP   # 23
TREE_OUT_W = MAC_OUT_W + 4   # 27
BIAS_OUT_W = TREE_OUT_W + 1  # 28
N_FILT     = 58
N_TAPS     = 9


def mask(w):      return (1 << w) - 1
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


def model_tree9(macs):
    l1_0 = model_adder3(macs[0], macs[1], macs[2], MAC_OUT_W)
    l1_1 = model_adder3(macs[3], macs[4], macs[5], MAC_OUT_W)
    l1_2 = model_adder3(macs[6], macs[7], macs[8], MAC_OUT_W)
    return model_adder3(l1_0, l1_1, l1_2, MAC_OUT_W + 2)


def model_quant_twosided(v, in_w, out_w):
    lo = -(1 << (out_w - 1)); hi = (1 << (out_w - 1)) - 1
    s = to_sgn(to_uns(v, in_w), in_w)
    return max(lo, min(hi, s))


def model_dw_filter(d9, w9, bias):
    macs     = [model_mac(d9[t], w9[t]) for t in range(N_TAPS)]
    tree     = model_tree9(macs)
    tree_ext = to_sgn(to_uns(tree, BIAS_OUT_W), BIAS_OUT_W)
    bias_ext = to_sgn(to_uns(bias, BIAS_OUT_W), BIAS_OUT_W)
    bias_sum = to_sgn(to_uns(tree_ext + bias_ext, BIAS_OUT_W), BIAS_OUT_W)
    return model_quant_twosided(bias_sum, BIAS_OUT_W, DATA_W)


def parse_vectors(path):
    """Parse 58-lines-per-case format. Returns list of (d_list, w_list, b_list, e_list)."""
    cases = []
    with open(path) as f:
        lines = [l.strip() for l in f]

    i = 0
    while i < len(lines):
        # Skip comment and blank lines
        if not lines[i] or lines[i].startswith("//"):
            i += 1
            continue
        # Try to read N_FILT consecutive data lines
        filter_lines = []
        j = i
        while j < len(lines) and len(filter_lines) < N_FILT:
            if lines[j] and not lines[j].startswith("//"):
                filter_lines.append(lines[j])
            j += 1
        if len(filter_lines) < N_FILT:
            break
        d_list = []; w_list = []; b_list = []; e_list = []
        ok = True
        for fl in filter_lines:
            toks = fl.split()
            if len(toks) != 20:
                ok = False; break
            d = [to_sgn(int(toks[t], 16), DATA_W) for t in range(9)]
            w = [to_sgn(int(toks[9+t], 16), DATA_W) for t in range(9)]
            b = to_sgn(int(toks[18], 16), DATA_W)
            e = to_sgn(int(toks[19], 16), DATA_W)
            d_list.append(d); w_list.append(w); b_list.append(b); e_list.append(e)
        if ok:
            cases.append((d_list, w_list, b_list, e_list))
        i = j
    return cases


def main():
    vec_path = PROJ_ROOT / "tb" / "group2" / "vectors" / "dw_conv3x3_core_vectors.hex"
    if not vec_path.exists():
        print(f"ERROR: {vec_path} not found"); sys.exit(1)

    cases = parse_vectors(vec_path)
    print("=" * 70)
    print(f"DW_CONV3X3_CORE SHADOW SIM  N_FILT={N_FILT}  ({len(cases)} cases)")
    print("=" * 70)

    fail = 0
    for idx, (d_list, w_list, b_list, e_list) in enumerate(cases):
        for flt in range(N_FILT):
            got = model_dw_filter(d_list[flt], w_list[flt], b_list[flt])
            if got != e_list[flt]:
                fail += 1
                if fail <= 10:
                    print(f"  FAIL case {idx} filter {flt}: got={got} exp={e_list[flt]}")

    total = len(cases) * N_FILT
    print(f"\nPASS: {total-fail}/{total}  ({len(cases)} cases x {N_FILT} filters)")
    if fail == 0:
        print("RESULT: *** ALL CHECKS PASSED ***"); sys.exit(0)
    else:
        print(f"RESULT: *** {fail} FAILURES ***"); sys.exit(1)


if __name__ == "__main__":
    main()
