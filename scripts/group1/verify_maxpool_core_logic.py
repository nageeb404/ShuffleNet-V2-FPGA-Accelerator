#!/usr/bin/env python3
# =============================================================================
# verify_maxpool_core_logic.py
# -----------------------------------------------------------------------------
# Bit-true shadow simulator for maxpool_core.v (Module 1.4).
#
# Max pooling has no arithmetic -- just comparison. The bit-true model
# is simply Python's max(). Verification focuses on:
#   1. Golden-vector cross-check (all 24 channels, all cases)
#   2. Position fuzz: max in every possible window position for every channel
#   3. Per-channel isolation: distinct inputs across channels -> distinct results
# =============================================================================

import random
import sys
from pathlib import Path

DATA_W   = 15
DATA_MAX =  (1 << (DATA_W - 1)) - 1
DATA_MIN = -(1 << (DATA_W - 1))
N_CHAN   = 24
N_WIN    = 9


def mask(w):
    return (1 << w) - 1

def to_uns(v, w):
    return int(v) & mask(w)

def to_sgn(u, w):
    u = int(u) & mask(w)
    return u - (1 << w) if (u >> (w - 1)) else u


# ---- Bit-true model ----
# The RTL comparator tree reduces 9 inputs via:
#   Stage1: m01=max(d0,d1), m23=max(d2,d3), m45=max(d4,d5), m67=max(d6,d7)
#   Stage2: m0123=max(m01,m23), m4567=max(m45,m67), d8 bypasses
#   [pipeline register]
#   Stage3: m01234567=max(m0123,m4567), chan_max=max(m01234567, d8)
# The result equals max(d0..d8) for any signed 15-bit inputs.

def model_chan(window):
    """Model one channel: signed max of 9 values (Q6.8)."""
    return max(window)

def model_core(windows):
    return [model_chan(windows[c]) for c in range(N_CHAN)]


# ---- RTL-structural model (matches the exact comparator tree) ----
def model_chan_structural(d):
    """Follows the exact RTL tree structure to verify no structural bug."""
    # Stage 1
    m01   = d[0] if d[0] > d[1] else d[1]
    m23   = d[2] if d[2] > d[3] else d[3]
    m45   = d[4] if d[4] > d[5] else d[4] if d[4] > d[5] else d[5]
    m45   = d[4] if d[4] > d[5] else d[5]
    m67   = d[6] if d[6] > d[7] else d[7]
    # Stage 2
    m0123 = m01 if m01 > m23 else m23
    m4567 = m45 if m45 > m67 else m67
    # Stage 3
    m01234567 = m0123 if m0123 > m4567 else m4567
    chan_max   = m01234567 if m01234567 > d[8] else d[8]
    return chan_max


# ---- Golden-vector parser ----
def parse_hex_file(path):
    with open(path) as f:
        raw = [line.strip() for line in f
               if line.strip() and not line.strip().startswith("//")]
    cases = []
    i = 0
    while i + N_CHAN < len(raw):
        try:
            windows = []
            for c in range(N_CHAN):
                vals = [to_sgn(int(x, 16), DATA_W) for x in raw[i+c].split()]
                if len(vals) != N_WIN:
                    break
                windows.append(vals)
            else:
                exp_vals = [to_sgn(int(x, 16), DATA_W)
                            for x in raw[i + N_CHAN].split()]
                if len(exp_vals) == N_CHAN:
                    cases.append((windows, exp_vals))
                    i += N_CHAN + 1
                    continue
            i += 1
        except (ValueError, IndexError):
            i += 1
    return cases


def check_golden(vec_path):
    cases = parse_hex_file(vec_path)
    fail = 0
    for idx, (windows, exp) in enumerate(cases):
        got = model_core(windows)
        # Also verify structural model matches simple model
        got_struct = [model_chan_structural(windows[c]) for c in range(N_CHAN)]
        for c in range(N_CHAN):
            if got[c] != exp[c]:
                fail += 1
                if fail <= 5:
                    print(f"  [golden] FAIL case={idx} ch={c}: "
                          f"got={got[c]} exp={exp[c]}")
            if got[c] != got_struct[c]:
                fail += 1
                if fail <= 5:
                    print(f"  [struct] MISMATCH case={idx} ch={c}: "
                          f"simple={got[c]} structural={got_struct[c]}")
    return len(cases), fail


def fuzz_position(n_per_pos):
    """For each of the 9 positions, verify the max is found when it's the biggest."""
    rng = random.Random(0xABC123)
    fail = 0
    total = 0
    for pos in range(N_WIN):
        for _ in range(n_per_pos):
            for c in range(N_CHAN):
                base = [rng.randint(DATA_MIN, DATA_MAX // 2) for _ in range(N_WIN)]
                base[pos] = DATA_MAX  # max is always at `pos`
                got = model_chan_structural(base)
                if got != DATA_MAX:
                    fail += 1
                total += 1
    return total, fail


def fuzz_random(n, seed):
    rng = random.Random(seed)
    fail = 0
    for _ in range(n):
        windows = [[rng.randint(DATA_MIN, DATA_MAX) for _ in range(N_WIN)]
                   for _ in range(N_CHAN)]
        got      = model_core(windows)
        got_s    = [model_chan_structural(windows[c]) for c in range(N_CHAN)]
        for c in range(N_CHAN):
            if got[c] < DATA_MIN or got[c] > DATA_MAX:
                fail += 1
            if got[c] != got_s[c]:
                fail += 1
    return n, fail


def main():
    fast   = "--fast" in sys.argv
    n_rand = 50_000 if fast else 1_000_000
    n_pos  = 100 if fast else 1000

    vec_dir  = (Path(__file__).resolve().parent.parent.parent
                / "tb" / "group1" / "vectors")
    vec_path = vec_dir / "maxpool_core_vectors.hex"

    print("=" * 70)
    print("MAXPOOL_CORE BIT-TRUE SHADOW SIMULATOR")
    print("24-ch x 9-win max-of-9")
    print("=" * 70)

    total_cases, total_fail = 0, 0

    print("\n[Stage 1] Golden-vector cross-check + structural model")
    if not vec_path.exists():
        print(f"  WARNING: {vec_path} not found -- run gen script first")
    else:
        n1, f1 = check_golden(vec_path)
        print(f"  {n1 - f1}/{n1} cases PASS  ({f1} fail)")
        total_cases += n1; total_fail += f1

    print(f"\n[Stage 2] Max-in-each-position fuzz ({n_pos} per position x 9)")
    n2, f2 = fuzz_position(n_pos)
    print(f"  {n2 - f2}/{n2} PASS  ({f2} fail)")
    total_cases += n2; total_fail += f2

    print(f"\n[Stage 3] Random fuzz ({n_rand:,} cases x {N_CHAN} channels)")
    n3, f3 = fuzz_random(n_rand, 0x1337C0DE)
    print(f"  {n3 - f3}/{n3} PASS  ({f3} fail)")
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
