#!/usr/bin/env python3
# =============================================================================
# verify_mac_unit_logic.py
# -----------------------------------------------------------------------------
# Bit-true shadow simulator for mac_unit.v. Same methodology as Phase 0:
# re-implement the Verilog logic line-for-line in Python and verify against
# golden vectors + random fuzz.
# =============================================================================

from pathlib import Path
import random
import sys

DATA_W     = 15
MUL_FULL_W = 30
MUL_OUT_W  = 23
DROP_LSB   = 7


def to_uns(v, w):
    return (v + (1 << w)) & ((1 << w) - 1) if v < 0 else v & ((1 << w) - 1)


def to_sgn(u, w):
    u &= (1 << w) - 1
    return u - (1 << w) if u & (1 << (w - 1)) else u


# =============================================================================
# Bit-level simulator: mac_unit.v
# =============================================================================
def rtl_mac_unit(a_s, b_s):
    """Mirror rtl/common/mac_unit.v exactly."""
    # MIRRORS: wire signed [29:0] product_full = a_data * b_weight;
    # Verilog signed * signed: result is exactly MUL_FULL_W bits wide,
    # bottom MUL_FULL_W bits of the true mathematical product.
    p_full_uns = to_uns(a_s * b_s, MUL_FULL_W)

    # MIRRORS: wire [22:0] product_truncated = product_full[29:7];
    # Bit-slice from MUL_FULL_W-1 down to DROP_LSB inclusive -> MUL_OUT_W bits.
    p_trunc_uns = (p_full_uns >> DROP_LSB) & ((1 << MUL_OUT_W) - 1)

    # MIRRORS: p_out <= product_truncated (the pipeline register;
    # the value latched is the same as product_truncated, just delayed)
    return to_sgn(p_trunc_uns, MUL_OUT_W)


# =============================================================================
# Reference model (what the math should produce)
# =============================================================================
def ref_mac_unit(a_s, b_s):
    """High-level reference: signed multiply, arithmetic right shift by 7."""
    return (a_s * b_s) >> DROP_LSB   # Python >> on signed ints is arith shift


# =============================================================================
# Test runners
# =============================================================================
def parse_hex_file(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("/"):
                continue
            rows.append(line.split())
    return rows


def check_golden_vectors(vec_path):
    rows = parse_hex_file(vec_path)
    fail = 0
    for idx, row in enumerate(rows):
        a   = to_sgn(int(row[0], 16), DATA_W)
        b   = to_sgn(int(row[1], 16), DATA_W)
        exp = to_sgn(int(row[2], 16), MUL_OUT_W)
        got = rtl_mac_unit(a, b)
        if got != exp:
            fail += 1
            if fail <= 3:
                print(f"  [golden] FAIL #{idx}: a={a} b={b} got={got} exp={exp}")
    return len(rows), fail


def fuzz(n, seed):
    rng = random.Random(seed)
    in_max =  (1 << (DATA_W - 1)) - 1
    in_min = -(1 << (DATA_W - 1))
    fail = 0
    for _ in range(n):
        a = rng.randint(in_min, in_max)
        b = rng.randint(in_min, in_max)
        got = rtl_mac_unit(a, b)
        exp = ref_mac_unit(a, b)
        if got != exp:
            fail += 1
            if fail <= 3:
                print(f"  [fuzz] FAIL: a={a} b={b} got={got} exp={exp}")
    return n, fail


def exhaustive():
    """Exhaustive: 16-bit input pairs * 16-bit input pairs is 2^28 = too many.
    Instead: every 12-bit signed value crossed with every 12-bit signed value
    = 2^24 ~ 16M cases, fully covers sign-bit transitions and small-magnitude
    edge cases."""
    NW = 12
    in_max =  (1 << (NW - 1)) - 1
    in_min = -(1 << (NW - 1))
    fail = 0
    count = 0
    for a in range(in_min, in_max + 1):
        for b in range(in_min, in_max + 1):
            count += 1
            got = rtl_mac_unit(a, b)
            exp = ref_mac_unit(a, b)
            if got != exp:
                fail += 1
                if fail <= 3:
                    print(f"  [exh] FAIL: a={a} b={b} got={got} exp={exp}")
    return count, fail


def main():
    fast = "--fast" in sys.argv
    n_fuzz = 10_000 if fast else 1_000_000

    vec_dir = Path(__file__).resolve().parent.parent.parent / "tb" / "common" / "vectors"

    print("=" * 70)
    print("MAC_UNIT BIT-TRUE SHADOW SIMULATOR")
    print("=" * 70)

    total_cases, total_fail = 0, 0

    print("\n[Stage 1] Golden vectors")
    n1, f1 = check_golden_vectors(vec_dir / "mac_unit_vectors.hex")
    print(f"  mac_unit: {n1 - f1}/{n1} PASS  ({f1} fail)")
    total_cases += n1; total_fail += f1

    print(f"\n[Stage 2] Random fuzz ({n_fuzz:,} cases)")
    n2, f2 = fuzz(n_fuzz, 0xBEEF)
    print(f"  mac_unit: {n2 - f2}/{n2} PASS  ({f2} fail)")
    total_cases += n2; total_fail += f2

    if not fast:
        print("\n[Stage 3] Exhaustive 12-bit x 12-bit sweep (~16M cases)")
        n3, f3 = exhaustive()
        print(f"  mac_unit: {n3 - f3}/{n3} PASS  ({f3} fail)")
        total_cases += n3; total_fail += f3

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
