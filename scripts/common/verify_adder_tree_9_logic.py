#!/usr/bin/env python3
# =============================================================================
# verify_adder_tree_9_logic.py
# -----------------------------------------------------------------------------
# Bit-true shadow simulator for adder_tree_9.v.
# =============================================================================

from pathlib import Path
import random
import sys


IN_W  = 23
L1_W  = IN_W + 2    # 25
L2_W  = L1_W + 2    # 27 = OUT_W
OUT_W = L2_W


def to_uns(v, w):
    return (v + (1 << w)) & ((1 << w) - 1) if v < 0 else v & ((1 << w) - 1)


def to_sgn(u, w):
    u &= (1 << w) - 1
    return u - (1 << w) if u & (1 << (w - 1)) else u


def get_bit(u, i):
    return (u >> i) & 1


# -----------------------------------------------------------------------------
# Bit-level model of one Adder3 (matches Adder3.v exactly)
# -----------------------------------------------------------------------------
def rtl_adder3(a_s, b_s, c_s, in_w):
    out_w = in_w + 2
    a = to_uns(a_s, out_w)
    b = to_uns(b_s, out_w)
    c = to_uns(c_s, out_w)

    sum_vec_u, carry_vec_u = 0, 0
    for i in range(out_w):
        ai, bi, ci = get_bit(a, i), get_bit(b, i), get_bit(c, i)
        sum_vec_u   |= ((ai ^ bi ^ ci) << i)
        carry_vec_u |= (((ai & bi) | (bi & ci) | (ai & ci)) << i)
    carry_shifted_u = (carry_vec_u << 1) & ((1 << out_w) - 1)
    raw_sum = to_sgn(sum_vec_u, out_w) + to_sgn(carry_shifted_u, out_w)
    return to_sgn(to_uns(raw_sum, out_w), out_w)


# -----------------------------------------------------------------------------
# Bit-level model of adder_tree_9 (4x Adder3 in 2 levels)
# -----------------------------------------------------------------------------
def rtl_adder_tree_9(inputs):
    """inputs: list of 9 signed integers."""
    # MIRRORS: 3x Adder3 at level 1
    l1_0 = rtl_adder3(inputs[0], inputs[1], inputs[2], IN_W)
    l1_1 = rtl_adder3(inputs[3], inputs[4], inputs[5], IN_W)
    l1_2 = rtl_adder3(inputs[6], inputs[7], inputs[8], IN_W)
    # MIRRORS: 1x Adder3 at level 2
    return rtl_adder3(l1_0, l1_1, l1_2, L1_W)


def ref_adder_tree_9(inputs):
    return sum(inputs)


# -----------------------------------------------------------------------------
# Test runners
# -----------------------------------------------------------------------------
def parse_hex_file(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("/"):
                continue
            rows.append(line.split())
    return rows


def check_golden(vec_path):
    rows = parse_hex_file(vec_path)
    fail = 0
    for idx, row in enumerate(rows):
        ins = [to_sgn(int(row[k], 16), IN_W) for k in range(9)]
        exp = to_sgn(int(row[9], 16), OUT_W)
        got = rtl_adder_tree_9(ins)
        if got != exp:
            fail += 1
            if fail <= 3:
                print(f"  [golden] FAIL #{idx}: ins={ins} got={got} exp={exp}")
    return len(rows), fail


def fuzz(n, seed):
    rng = random.Random(seed)
    in_max =  (1 << (IN_W - 1)) - 1
    in_min = -(1 << (IN_W - 1))
    fail = 0
    for _ in range(n):
        ins = [rng.randint(in_min, in_max) for _ in range(9)]
        got = rtl_adder_tree_9(ins)
        exp = ref_adder_tree_9(ins)
        if got != exp:
            fail += 1
            if fail <= 3:
                print(f"  [fuzz] FAIL: ins={ins} got={got} exp={exp}")
    return n, fail


def main():
    fast = "--fast" in sys.argv
    n_fuzz = 10_000 if fast else 1_000_000

    vec_dir = Path(__file__).resolve().parent.parent.parent / "tb" / "common" / "vectors"

    print("=" * 70)
    print("ADDER_TREE_9 BIT-TRUE SHADOW SIMULATOR")
    print("=" * 70)

    total_cases, total_fail = 0, 0

    print("\n[Stage 1] Golden vectors")
    n1, f1 = check_golden(vec_dir / "adder_tree_9_vectors.hex")
    print(f"  adder_tree_9: {n1 - f1}/{n1} PASS  ({f1} fail)")
    total_cases += n1; total_fail += f1

    print(f"\n[Stage 2] Random fuzz ({n_fuzz:,} cases)")
    n2, f2 = fuzz(n_fuzz, 0xC0DE)
    print(f"  adder_tree_9: {n2 - f2}/{n2} PASS  ({f2} fail)")
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
