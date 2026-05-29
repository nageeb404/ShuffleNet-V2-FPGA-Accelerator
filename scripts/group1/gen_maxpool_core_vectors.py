#!/usr/bin/env python3
# =============================================================================
# gen_maxpool_core_vectors.py
# -----------------------------------------------------------------------------
# Generate golden test vectors for maxpool_core (Module 1.4).
#
# The core takes 24 channels x 9 window values and outputs the max per channel.
# No bit growth -- output is the same 15-bit Q6.8 as input.
#
# File format: 25 lines per test case
#   Lines 1-24: 9 hex values for channel 0..23 (input window taps)
#   Line 25: 24 hex values (expected max per channel)
# =============================================================================

import random
import sys
from pathlib import Path

DATA_W   = 15
DATA_MAX =  (1 << (DATA_W - 1)) - 1   # +16383
DATA_MIN = -(1 << (DATA_W - 1))        # -16384
N_CHAN   = 24
N_WIN    = 9


def mask(w):
    return (1 << w) - 1

def to_uns(v, w):
    return int(v) & mask(w)

def to_sgn(u, w):
    u = int(u) & mask(w)
    return u - (1 << w) if (u >> (w - 1)) else u

def hex_str(v, w):
    digits = (w + 3) // 4
    return f"{to_uns(v, w):0{digits}x}"


def model_maxpool_chan(window):
    """Max of 9 signed Q6.8 values -- no bit growth."""
    return max(window)


def model_maxpool_core(windows):
    """
    windows: list of N_CHAN lists of N_WIN signed ints
    Returns: list of N_CHAN max values
    """
    return [model_maxpool_chan(windows[c]) for c in range(N_CHAN)]


def rand_q68():
    return random.randint(DATA_MIN, DATA_MAX)


def gen_vectors(out_path: Path, n_random: int = 200):
    dmax, dmin = DATA_MAX, DATA_MIN
    cases = []

    # ---- Edge cases ----
    # All zeros
    cases.append([[0]*N_WIN]*N_CHAN)
    # All max
    cases.append([[dmax]*N_WIN]*N_CHAN)
    # All min
    cases.append([[dmin]*N_WIN]*N_CHAN)
    # Max in position 0 for all channels
    cases.append([[dmax] + [0]*(N_WIN-1)]*N_CHAN)
    # Max in position 8 for all channels
    cases.append([[0]*(N_WIN-1) + [dmax]]*N_CHAN)
    # Max in middle position (position 4)
    cases.append([[dmin, dmin, dmin, dmin, dmax, dmin, dmin, dmin, dmin]]*N_CHAN)
    # Monotonically increasing
    cases.append([list(range(-4, 5))]*N_CHAN)
    # Monotonically decreasing
    cases.append([list(range(4, -5, -1))]*N_CHAN)
    # Distinct max per channel (channel c has max = c - 12)
    distinct = [[dmin]*N_WIN for _ in range(N_CHAN)]
    for c in range(N_CHAN):
        distinct[c][c % N_WIN] = c - 12
    cases.append(distinct)
    # Mixed positive/negative, max=1
    cases.append([[dmin, -1, 1, dmin, dmin, dmin, dmin, dmin, dmin]]*N_CHAN)
    # Post-ReLU style: all non-negative
    relu_case = [[random.randint(0, dmax) for _ in range(N_WIN)]
                 for _ in range(N_CHAN)]
    cases.append(relu_case)

    # ---- Random fuzz ----
    random.seed(0xF00DCAFE)
    for _ in range(n_random):
        windows = [[rand_q68() for _ in range(N_WIN)] for _ in range(N_CHAN)]
        cases.append(windows)

    total = len(cases)
    with open(out_path, "w") as f:
        f.write("// maxpool_core golden test vectors\n")
        f.write("// Module 1.4\n")
        f.write("// 25 lines per test case:\n")
        f.write("//   Lines 1-24: 9 hex values per channel (input window)\n")
        f.write("//   Line 25:    24 hex values (expected max per channel)\n")
        f.write(f"// n_cases={total}\n")
        for windows in cases:
            results = model_maxpool_core(windows)
            # 24 input lines
            for c in range(N_CHAN):
                line = " ".join(hex_str(v, DATA_W) for v in windows[c])
                f.write(line + "\n")
            # 1 expected-results line (all 24 channels)
            exp_line = " ".join(hex_str(v, DATA_W) for v in results)
            f.write(exp_line + "\n")

    print(f"[maxpool_core] Wrote {total} test cases ({total*25} lines) to {out_path}")
    return total


def main():
    if len(sys.argv) > 1:
        out_dir = Path(sys.argv[1])
    else:
        out_dir = (Path(__file__).resolve().parent.parent.parent
                   / "tb" / "group1" / "vectors")
    out_dir.mkdir(parents=True, exist_ok=True)
    gen_vectors(out_dir / "maxpool_core_vectors.hex")
    print("Done.")


if __name__ == "__main__":
    main()
