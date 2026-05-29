#!/usr/bin/env python3
# =============================================================================
# gen_mac_unit_vectors.py
# -----------------------------------------------------------------------------
# Generate golden test vectors for the mac_unit module (Module 1.1).
#
# Operation modeled:
#   p_full = signed(a_data) * signed(b_weight) # 15 x 15 = 30 bits
#   p_out = p_full[29:7] # drop 7 LSBs -> 23 bits
#
# File format (each line is one test case):
#   a_hex b_hex expected_p_out_hex
#
# Widths:
#   a / b : 15 bits, signed two's complement
#   expected_p_out : 23 bits, signed two's complement (= MUL_OUT_W)
# =============================================================================

import random
import sys
from pathlib import Path

# ---- Constants must match shufflenet_pkg.vh ----
DATA_W     = 15
MUL_FULL_W = 30
MUL_OUT_W  = 23
DROP_LSB   = 7


# ---- Helpers ----
def to_uns(v, w):
    return (v + (1 << w)) & ((1 << w) - 1) if v < 0 else v & ((1 << w) - 1)


def to_sgn(u, w):
    u &= (1 << w) - 1
    return u - (1 << w) if u & (1 << (w - 1)) else u


def hex_str(val, width):
    n_digits = (width + 3) // 4
    return f"{to_uns(val, width):0{n_digits}x}"


# ---- Bit-true model of the multiplier + 7-LSB-drop ----
def mac_model(a_signed, b_signed):
    """
    Compute the same arithmetic that the RTL computes:
      1) Signed 15x15 multiply -> 30-bit signed product.
      2) Truncate the bottom 7 bits (arithmetic right shift, since this is
         signed two's complement, the sign is preserved).
    """
    p_full = a_signed * b_signed  # Python ints, unbounded

    # Truncate to MUL_FULL_W bits FIRST (Verilog signed * signed yields exactly
    # MUL_FULL_W bits; Python's '*' gives unbounded result), then drop 7 LSBs.
    # The bit pattern is preserved either way for any in-range operands; we do
    # this defensively in case a corner case ever produces a value outside the
    # natural 30-bit signed range (it can't, given 15-bit signed inputs, but
    # the explicit truncation makes the intent obvious).
    p_full_u  = to_uns(p_full, MUL_FULL_W)
    p_trunc_u = p_full_u >> DROP_LSB  # MUL_OUT_W bits remain
    return to_sgn(p_trunc_u, MUL_OUT_W)


# ---- Vector generation ----
def gen_vectors(out_path: Path, n_random: int = 500):
    in_max =  (1 << (DATA_W - 1)) - 1     # +16383
    in_min = -(1 << (DATA_W - 1))         # -16384

    cases = []

    # --- Edge cases ---
    edges = [0, 1, -1, in_max, in_min, in_max // 2, in_min // 2, 256, -256]
    for a in edges:
        for b in edges:
            cases.append((a, b))

    # --- Random fuzz ---
    random.seed(0x3AC0)
    for _ in range(n_random):
        a = random.randint(in_min, in_max)
        b = random.randint(in_min, in_max)
        cases.append((a, b))

    with open(out_path, "w") as f:
        f.write("// mac_unit test vectors\n")
        f.write("// Format: a_hex  b_hex  expected_p_out_hex  (all signed 2's-comp)\n")
        f.write(f"// DATA_W={DATA_W}, MUL_OUT_W={MUL_OUT_W}, "
                f"n_cases={len(cases)}\n")
        for a, b in cases:
            p = mac_model(a, b)
            # Sanity check: result must fit in 23-bit signed range
            assert -(1 << (MUL_OUT_W - 1)) <= p <= (1 << (MUL_OUT_W - 1)) - 1, \
                f"mac result {p} overflows MUL_OUT_W={MUL_OUT_W}"
            f.write(f"{hex_str(a, DATA_W)} "
                    f"{hex_str(b, DATA_W)} "
                    f"{hex_str(p, MUL_OUT_W)}\n")

    print(f"[mac_unit] Wrote {len(cases)} vectors to {out_path}")
    return out_path


def main():
    if len(sys.argv) > 1:
        out_dir = Path(sys.argv[1])
    else:
        out_dir = Path(__file__).resolve().parent.parent.parent / "tb" / "common" / "vectors"
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Output directory: {out_dir}")
    gen_vectors(out_dir / "mac_unit_vectors.hex")
    print("Done.")


if __name__ == "__main__":
    main()
