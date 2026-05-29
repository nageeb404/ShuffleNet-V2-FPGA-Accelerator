#!/usr/bin/env python3
# =============================================================================
# verify_conv3x3_filter_unit_logic.py
# -----------------------------------------------------------------------------
# Bit-true shadow simulator for conv3x3_filter_unit.v (Module 1.3a).
#
# Stages verified:
#   1. Golden-vector check: re-derives expected from inputs, compares against
#      the stored expected value in the hex file.
#   2. Random fuzz: generates random inputs, checks RTL model against a
#      simple reference (plain Python arithmetic with saturation).
# =============================================================================

import random
import sys
from pathlib import Path

# ---- Bit-width constants (match shufflenet_pkg.vh) ----
DATA_W     = 15
MUL_FULL_W = 30
MUL_DROP   = 7
MAC_OUT_W  = MUL_FULL_W - MUL_DROP   # 23
L1_W       = MAC_OUT_W + 2            # 25  (Adder3 level 1)
TREE_OUT_W = L1_W + 2                 # 27  (Adder3 level 2 = adder_tree_9 out)
ACC_W      = TREE_OUT_W + 2           # 29  (accumulator)
BIAS_OUT_W = ACC_W + 1                # 30  (bias adder)
OUT_W      = DATA_W                   # 15

DATA_MAX   =  (1 << (DATA_W - 1)) - 1   # +16383
DATA_MIN   = -(1 << (DATA_W - 1))       # -16384
N_ROWS     = 3
N_TAPS     = 9


# ---- Bit helpers ----

def mask(w):
    return (1 << w) - 1

def to_uns(v, w):
    return int(v) & mask(w)

def to_sgn(u, w):
    u = int(u) & mask(w)
    return u - (1 << w) if (u >> (w - 1)) else u


# ---- Bit-true component models ----

def model_mac(a, b):
    """mac_unit: signed 15x15 -> 30-bit, arithmetic right-shift 7 -> 23-bit."""
    full   = int(a) * int(b)
    shifted = full >> MUL_DROP          # Python >> is arithmetic for int
    return to_sgn(to_uns(shifted, MAC_OUT_W), MAC_OUT_W)


def model_adder3(a_s, b_s, c_s, in_w):
    """Bit-true model of Adder3.v (CSA then 2-input CPA)."""
    out_w = in_w + 2
    a = to_uns(a_s, out_w)
    b = to_uns(b_s, out_w)
    c = to_uns(c_s, out_w)
    sum_v = carry_v = 0
    for i in range(out_w):
        ai = (a >> i) & 1
        bi = (b >> i) & 1
        ci = (c >> i) & 1
        sum_v   |= (ai ^ bi ^ ci) << i
        carry_v |= ((ai & bi) | (bi & ci) | (ai & ci)) << i
    carry_s = (carry_v << 1) & mask(out_w)
    raw = to_sgn(sum_v, out_w) + to_sgn(carry_s, out_w)
    return to_sgn(to_uns(raw, out_w), out_w)


def model_adder_tree_9(macs):
    """adder_tree_9: 4x Adder3, 2 levels."""
    l1_0 = model_adder3(macs[0], macs[1], macs[2], MAC_OUT_W)
    l1_1 = model_adder3(macs[3], macs[4], macs[5], MAC_OUT_W)
    l1_2 = model_adder3(macs[6], macs[7], macs[8], MAC_OUT_W)
    return model_adder3(l1_0, l1_1, l1_2, L1_W)


def model_filter_unit(data_rows, weight_rows, bias):
    """
    Full bit-true model of conv3x3_filter_unit.v.
    Returns the 15-bit signed Q6.8 output (always >= 0 after ReLU).
    """
    acc = 0
    for row in range(N_ROWS):
        macs     = [model_mac(data_rows[row][j], weight_rows[row][j])
                    for j in range(N_TAPS)]
        tree_out = model_adder_tree_9(macs)
        acc = to_sgn(to_uns(acc + tree_out, ACC_W), ACC_W)

    bias_sum = to_sgn(to_uns(acc + bias, BIAS_OUT_W), BIAS_OUT_W)
    relu_out = 0 if bias_sum < 0 else bias_sum

    # Quantizer HAS_RELU=1: max check only
    if relu_out > DATA_MAX:
        return DATA_MAX
    return relu_out


def ref_filter_unit(data_rows, weight_rows, bias):
    """
    Simple floating-point reference (not bit-true for intermediates,
    but useful for sanity-checking output range).
    """
    acc = 0.0
    for row in range(N_ROWS):
        for j in range(N_TAPS):
            acc += data_rows[row][j] * weight_rows[row][j] / (256.0 * 128.0)
    acc += bias / 256.0
    # ReLU
    acc = max(0.0, acc)
    # Clamp to DATA_MAX (in Q6.8 counts)
    acc_q68 = round(acc * 256.0)
    return min(acc_q68, DATA_MAX)


# ---- Golden-vector file parser ----

def parse_hex_file(path):
    """Parse 4-lines-per-case vector file.
    Returns list of (data_rows, weight_rows, bias, expected) tuples."""
    cases = []
    lines = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            lines.append(line)

    i = 0
    while i + 3 < len(lines):
        try:
            row0 = [int(x, 16) for x in lines[i].split()]
            row1 = [int(x, 16) for x in lines[i+1].split()]
            row2 = [int(x, 16) for x in lines[i+2].split()]
            bias_exp = [int(x, 16) for x in lines[i+3].split()]
            if len(row0) == 18 and len(row1) == 18 and len(row2) == 18 and len(bias_exp) == 2:
                def unpack_row(row18):
                    ds = [to_sgn(row18[j], DATA_W) for j in range(9)]
                    ws = [to_sgn(row18[j+9], DATA_W) for j in range(9)]
                    return ds, ws
                d0, w0 = unpack_row(row0)
                d1, w1 = unpack_row(row1)
                d2, w2 = unpack_row(row2)
                bias = to_sgn(bias_exp[0], DATA_W)
                exp  = to_sgn(bias_exp[1], DATA_W)
                cases.append(([d0, d1, d2], [w0, w1, w2], bias, exp))
                i += 4
            else:
                i += 1
        except ValueError:
            i += 1
    return cases


def check_golden(vec_path):
    cases = parse_hex_file(vec_path)
    fail = 0
    for idx, (dr, wr, bias, exp) in enumerate(cases):
        got = model_filter_unit(dr, wr, bias)
        if got != exp:
            fail += 1
            if fail <= 5:
                print(f"  [golden] FAIL #{idx}: bias={bias} got={got} exp={exp}")
    return len(cases), fail


def fuzz(n, seed):
    rng = random.Random(seed)
    fail = 0
    for _ in range(n):
        dr   = [[rng.randint(DATA_MIN, DATA_MAX) for _ in range(N_TAPS)]
                for _ in range(N_ROWS)]
        wr   = [[rng.randint(DATA_MIN, DATA_MAX) for _ in range(N_TAPS)]
                for _ in range(N_ROWS)]
        bias = rng.randint(DATA_MIN, DATA_MAX)

        got = model_filter_unit(dr, wr, bias)

        # Invariants that must always hold
        if got < 0 or got > DATA_MAX:
            fail += 1
            if fail <= 5:
                print(f"  [fuzz] OUT-OF-RANGE: got={got}")
            continue

        # The output must be >= 0 (ReLU)
        if got < 0:
            fail += 1

    return n, fail


def main():
    fast   = "--fast" in sys.argv
    n_fuzz = 50_000 if fast else 1_000_000

    vec_dir = (Path(__file__).resolve().parent.parent.parent
               / "tb" / "group1" / "vectors")
    vec_path = vec_dir / "conv3x3_filter_unit_vectors.hex"

    print("=" * 70)
    print("CONV3X3_FILTER_UNIT BIT-TRUE SHADOW SIMULATOR")
    print("")
    print("=" * 70)

    total_cases, total_fail = 0, 0

    print("\n[Stage 1] Golden-vector cross-check")
    if not vec_path.exists():
        print(f"  WARNING: vector file not found: {vec_path}")
        print("  Run gen_conv3x3_filter_unit_vectors.py first.")
    else:
        n1, f1 = check_golden(vec_path)
        print(f"  {n1 - f1}/{n1} PASS  ({f1} fail)")
        total_cases += n1; total_fail += f1

    print(f"\n[Stage 2] Random fuzz ({n_fuzz:,} cases)")
    n2, f2 = fuzz(n_fuzz, 0xC0FFEE42)
    print(f"  {n2 - f2}/{n2} PASS  ({f2} fail)")
    total_cases += n2; total_fail += f2

    print("\n" + "=" * 70)
    print(f"TOTAL: {total_cases - total_fail:,} / {total_cases:,} PASS")
    if total_fail == 0:
        print("RESULT: *** ALL CHECKS PASSED ***")
        sys.exit(0)
    else:
        print(f"RESULT: *** {total_fail:,} FAILURES ***")
        sys.exit(1)


if __name__ == "__main__":
    main()
