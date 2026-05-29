#!/usr/bin/env python3
# =============================================================================
# gen_adder_tree_9_vectors.py
# -----------------------------------------------------------------------------
# Generate golden test vectors for the adder_tree_9 module (Module 1.2).
#
# Operation modeled:
#   sum_out = in0 + in1 + ... + in8 (signed)
#   Width grows by +4 (2 Adder3 levels x +2 each).
#
# File format (one test case per line):
#   in0_hex in1_hex in2_hex in3_hex in4_hex in5_hex in6_hex in7_hex in8_hex sum_hex
# =============================================================================

import random
import sys
from pathlib import Path

# ---- Constants ----
IN_W  = 23      # = MUL_OUT_W
OUT_W = IN_W + 4   # 27


def to_uns(v, w):
    return (v + (1 << w)) & ((1 << w) - 1) if v < 0 else v & ((1 << w) - 1)


def hex_str(val, width):
    n_digits = (width + 3) // 4
    return f"{to_uns(val, width):0{n_digits}x}"


def gen_vectors(out_path: Path, n_random: int = 500):
    in_max =  (1 << (IN_W - 1)) - 1
    in_min = -(1 << (IN_W - 1))

    cases = []

    # ---- Edge cases ----
    # All-zero, all-one, all-max, all-min, alternating, etc.
    edge_patterns = [
        [0]*9,
        [1]*9,
        [-1]*9,
        [in_max]*9,                 # exercises +max accumulation
        [in_min]*9,                 # exercises -max accumulation
        [in_max, in_min]*4 + [0],
        [in_min, in_max]*4 + [0],
        list(range(-4, 5)),
        list(range(4, -5, -1)),
        [in_max, 0, 0, 0, 0, 0, 0, 0, 0],
        [in_min, 0, 0, 0, 0, 0, 0, 0, 0],
        [in_max // 2]*9,
        [in_min // 2]*9,
    ]
    cases.extend(edge_patterns)

    # ---- Random fuzz ----
    random.seed(0xAD7E)
    for _ in range(n_random):
        cases.append([random.randint(in_min, in_max) for _ in range(9)])

    with open(out_path, "w") as f:
        f.write("// adder_tree_9 test vectors\n")
        f.write("// Format: in0..in8 (hex)  expected_sum_hex  (all signed 2's-comp)\n")
        f.write(f"// IN_W={IN_W}, OUT_W={OUT_W}, n_cases={len(cases)}\n")
        for case in cases:
            s = sum(case)
            # Sanity check: result must fit in OUT_W bits signed
            assert -(1 << (OUT_W - 1)) <= s <= (1 << (OUT_W - 1)) - 1, \
                f"sum {s} overflows OUT_W={OUT_W}"
            in_hex = " ".join(hex_str(v, IN_W) for v in case)
            f.write(f"{in_hex} {hex_str(s, OUT_W)}\n")

    print(f"[adder_tree_9] Wrote {len(cases)} vectors to {out_path}")
    return out_path


def main():
    if len(sys.argv) > 1:
        out_dir = Path(sys.argv[1])
    else:
        out_dir = Path(__file__).resolve().parent.parent.parent / "tb" / "common" / "vectors"
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Output directory: {out_dir}")
    gen_vectors(out_dir / "adder_tree_9_vectors.hex")
    print("Done.")


if __name__ == "__main__":
    main()
