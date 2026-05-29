#!/usr/bin/env python3
# =============================================================================
# gen_foundation_vectors.py
# -----------------------------------------------------------------------------
# Generates golden test vectors (hex files) for the foundation utilities:
# - Adder3 (3-input CSA adder)
# - quantizer (saturating quantizer / 5.4.1.2)
#
# All arithmetic is bit-true to the RTL:
#   - Q6.8 signed format: 15 bits = 1 sign + 6 integer + 8 fraction
#   - DATA_MAX = +16383 (0x3FFF)
#   - DATA_MIN = -16384 (= signed value of 0x4000 in 15 bits)
#
# Usage:
#   python3 gen_foundation_vectors.py [output_dir]
#
# This implements the "Python -> hex files -> $readmemh -> self-checking
# testbench" verification flow described in
# =============================================================================

import os
import sys
import random
from pathlib import Path

# -----------------------------------------------------------------------------
# Constants (mirror shufflenet_pkg.vh exactly)
# -----------------------------------------------------------------------------
DATA_W   = 15
INT_W    = 6
FRAC_W   = 8
DATA_MAX = (1 << (DATA_W - 1)) - 1     # +16383
DATA_MIN = -(1 << (DATA_W - 1))        # -16384


# -----------------------------------------------------------------------------
# Helpers for two's complement <-> signed integer
# -----------------------------------------------------------------------------
def to_unsigned(val: int, width: int) -> int:
    """Convert a signed integer to unsigned two's complement of given width."""
    if val < 0:
        return (1 << width) + val
    return val & ((1 << width) - 1)


def to_signed(uval: int, width: int) -> int:
    """Convert unsigned two's complement to signed integer."""
    uval &= (1 << width) - 1
    if uval & (1 << (width - 1)):
        return uval - (1 << width)
    return uval


def hex_str(val: int, width: int) -> str:
    """Format an integer as a hex string of ceil(width/4) digits, two's-comp."""
    n_digits = (width + 3) // 4
    return f"{to_unsigned(val, width):0{n_digits}x}"


def saturate(val: int, width: int) -> int:
    """Saturate a signed integer to the given width's signed range."""
    hi = (1 << (width - 1)) - 1
    lo = -(1 << (width - 1))
    if val > hi:
        return hi
    if val < lo:
        return lo
    return val


# -----------------------------------------------------------------------------
# Adder3 model: bit-true CSA reference
# -----------------------------------------------------------------------------
# Sec 5.3.2.1, output width = input width + 2.
# The arithmetic is just a 3-operand signed addition; the CSA structure does
# not change the value, only the way it is computed in hardware.
# -----------------------------------------------------------------------------
def adder3_model(a: int, b: int, c: int, in_width: int) -> int:
    """Compute the signed sum of three in_width-bit signed integers."""
    return a + b + c


# -----------------------------------------------------------------------------
# Quantizer model: bit-true saturation
# -----------------------------------------------------------------------------
# Two modes:
#   has_relu = False -> two-sided (min + max checks)
#   has_relu = True -> one-sided (max check only; input assumed >= 0)
# Output is always DATA_W bits signed Q6.8.
# -----------------------------------------------------------------------------
def quantizer_model(val: int, in_width: int, has_relu: bool) -> int:
    """
    Saturating quantizer to the 15-bit Q6.8 datapath format.

     / 5.5.1.1, the post-ReLU mode assumes the input is
    already non-negative (the parent core's ReLU has zeroed all negatives).
    The quantizer itself does NOT do ReLU; it only does max saturation.
    """
    if has_relu:
        assert val >= 0, "post-ReLU quantizer received a negative value"
        if val > DATA_MAX:
            return DATA_MAX
        return val
    else:
        if val > DATA_MAX:
            return DATA_MAX
        if val < DATA_MIN:
            return DATA_MIN
        return val


# -----------------------------------------------------------------------------
# Vector generation
# -----------------------------------------------------------------------------
def gen_adder3_vectors(out_dir: Path, in_width: int = 23, n_random: int = 200):
    """
    Generate vectors for the Adder3 module.

    File format (each line is one test case):
       a_hex b_hex c_hex expected_sum_hex

    Widths:
       a/b/c           : in_width bits (default 23, matching MUL_OUT_W)
       expected_sum    : in_width + 2 bits
    """
    out_width = in_width + 2
    in_max  =  (1 << (in_width  - 1)) - 1
    in_min  = -(1 << (in_width  - 1))

    cases = []

    # --- Edge cases ---
    edge_inputs = [0, 1, -1, in_max, in_min, in_max // 2, in_min // 2]
    for a in edge_inputs:
        for b in edge_inputs:
            for c in edge_inputs:
                cases.append((a, b, c))

    # --- Random cases ---
    random.seed(0xA3D3)  # deterministic
    for _ in range(n_random):
        a = random.randint(in_min, in_max)
        b = random.randint(in_min, in_max)
        c = random.randint(in_min, in_max)
        cases.append((a, b, c))

    out_path = out_dir / "adder3_vectors.hex"
    with open(out_path, "w") as f:
        f.write(f"// Adder3 test vectors\n")
        f.write(f"// Format: a b c expected_sum  (all hex, two's complement)\n")
        f.write(f"// in_width={in_width}, out_width={out_width}, "
                f"n_cases={len(cases)}\n")
        for a, b, c in cases:
            s = adder3_model(a, b, c, in_width)
            # Sanity check: result must fit in out_width bits signed
            assert -(1 << (out_width - 1)) <= s <= (1 << (out_width - 1)) - 1, \
                f"Adder3 result {s} overflows {out_width}-bit signed range"
            f.write(f"{hex_str(a, in_width)} "
                    f"{hex_str(b, in_width)} "
                    f"{hex_str(c, in_width)} "
                    f"{hex_str(s, out_width)}\n")

    print(f"[adder3] Wrote {len(cases)} vectors to {out_path}")
    return out_path


def gen_quantizer_vectors(out_dir: Path,
                          in_width: int = 27,
                          n_random: int = 200):
    """
    Generate vectors for the quantizer module, in BOTH modes.

     and 5.5.1.1, the post-ReLU quantizer ALWAYS receives
    a non-negative input ("the ReLU output will never be a negative value").
    So the two modes are tested with two different stimulus distributions:

       - signed mode (HAS_RELU=0): inputs span the full signed range
       - relu  mode (HAS_RELU=1): inputs are non-negative only

    File format (each line is one test case):
       in_hex  expected_signed_quant_hex  in_relu_hex  expected_relu_quant_hex

    Widths:
       in / in_relu                  : in_width bits (two's-comp; in_relu>=0)
       expected_*_quant              : DATA_W-bit Q6.8
    """
    in_max  =  (1 << (in_width  - 1)) - 1
    in_min  = -(1 << (in_width  - 1))

    # ---- signed-mode stimulus: full range ----
    signed_cases = []
    edge_signed = [
        0, 1, -1,
        DATA_MAX, DATA_MAX + 1, DATA_MAX * 2,
        DATA_MIN, DATA_MIN - 1, DATA_MIN * 2,
        in_max, in_min,
        in_max // 4, in_min // 4,
        DATA_MAX // 2, DATA_MIN // 2,
    ]
    for v in edge_signed:
        if in_min <= v <= in_max:
            signed_cases.append(v)
    random.seed(0x9A11)
    for _ in range(n_random):
        signed_cases.append(random.randint(in_min, in_max))

    # ---- relu-mode stimulus: non-negative only ----
    relu_cases = []
    edge_relu = [
        0, 1,
        DATA_MAX, DATA_MAX + 1, DATA_MAX * 2,
        in_max, in_max // 4, DATA_MAX // 2,
    ]
    for v in edge_relu:
        if 0 <= v <= in_max:
            relu_cases.append(v)
    random.seed(0x9A12)
    for _ in range(n_random):
        relu_cases.append(random.randint(0, in_max))

    # Pad shorter list (so we have one case per file line)
    n = max(len(signed_cases), len(relu_cases))
    while len(signed_cases) < n: signed_cases.append(0)
    while len(relu_cases)   < n: relu_cases.append(0)

    out_path = out_dir / "quantizer_vectors.hex"
    with open(out_path, "w") as f:
        f.write(f"// Quantizer test vectors\n")
        f.write(f"// Format: in_signed  exp_signed_out  in_relu  exp_relu_out\n")
        f.write(f"// in_width={in_width}, data_w={DATA_W}, n_cases={n}\n")
        for vs, vr in zip(signed_cases, relu_cases):
            q_signed = quantizer_model(vs, in_width, has_relu=False)
            q_relu   = quantizer_model(vr, in_width, has_relu=True)
            f.write(f"{hex_str(vs,       in_width)} "
                    f"{hex_str(q_signed, DATA_W)} "
                    f"{hex_str(vr,       in_width)} "
                    f"{hex_str(q_relu,   DATA_W)}\n")

    print(f"[quantizer] Wrote {n} vectors (each with signed+relu) to {out_path}")
    return out_path


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
def main():
    if len(sys.argv) > 1:
        out_dir = Path(sys.argv[1])
    else:
        out_dir = Path(__file__).resolve().parent.parent.parent / "tb" / "common" / "vectors"
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Output directory: {out_dir}")

    gen_adder3_vectors(out_dir)
    gen_quantizer_vectors(out_dir)

    print("Done.")


if __name__ == "__main__":
    main()
