#!/usr/bin/env python3
# =============================================================================
# verify_fifo_3x3_logic.py
# -----------------------------------------------------------------------------
# Bit-true shadow simulator for fifo_3x3.v (Module 1.5).
# =============================================================================

import random
import sys
from pathlib import Path

DATA_W = 15
DEPTH = 455
TAP_STRIDE = (DEPTH - 3) // 2 # 226

DATA_MAX = (1 << (DATA_W - 1)) - 1
DATA_MIN = -(1 << (DATA_W - 1))


def mask(w):
 return (1 << w) - 1

def to_uns(v, w):
 return int(v) & mask(w)

def to_sgn(u, w):
 u = int(u) & mask(w)
 return u - (1 << w) if (u >> (w - 1)) else u


def model_step(state, data_in, padding_sel, shift_and_load):
 """Advance FIFO model by one clock cycle."""
 if shift_and_load:
 val = 0 if padding_sel else data_in
 new_state = [val] + state[:-1]
 else:
 new_state = state[:]
 return new_state, (new_state[0], new_state[TAP_STRIDE], new_state[2*TAP_STRIDE])


def parse_hex_file(path):
 rows = []
 with open(path) as f:
 for line in f:
 line = line.strip
 if not line or line.startswith("//"):
 continue
 parts = line.split
 if len(parts) == 6:
 try:
 d = to_sgn(int(parts[0], 16), DATA_W)
 ps = int(parts[1], 16)
 sal = int(parts[2], 16)
 t0 = to_sgn(int(parts[3], 16), DATA_W)
 t1 = to_sgn(int(parts[4], 16), DATA_W)
 t2 = to_sgn(int(parts[5], 16), DATA_W)
 rows.append((d, ps, sal, t0, t1, t2))
 except ValueError:
 pass
 return rows


def check_golden(vec_path):
 rows = parse_hex_file(vec_path)
 state = [0] * DEPTH
 fail = 0
 for idx, (d, ps, sal, exp_t0, exp_t1, exp_t2) in enumerate(rows):
 state, (got_t0, got_t1, got_t2) = model_step(state, d, ps, sal)
 if got_t0 != exp_t0 or got_t1 != exp_t1 or got_t2 != exp_t2:
 fail += 1
 if fail <= 5:
 print(f" [golden] FAIL cycle={idx}: "
 f"tap0 got={got_t0} exp={exp_t0} | "
 f"tap1 got={got_t1} exp={exp_t1} | "
 f"tap2 got={got_t2} exp={exp_t2}")
 return len(rows), fail


def fuzz_tap_positions(n, seed):
 """Verify each tap position is correct by driving known patterns."""
 rng = random.Random(seed)
 fail = 0

 # Fill FIFO with unique values and check taps
 for trial in range(n):
 state = [0] * DEPTH
 data = [rng.randint(DATA_MIN, DATA_MAX) for _ in range(DEPTH + 10)]

 for t in range(DEPTH + 10):
 state, (t0, t1, t2) = model_step(state, data[t], 0, 1)

 # After DEPTH+10 shifts, check exact tap positions
 # tap0 = most recently shifted value = data[DEPTH+9]
 # tap1 = data[DEPTH+9 - TAP_STRIDE] = data[DEPTH+9-226] = data[DEPTH-217]
 # tap2 = data[DEPTH+9 - 2*TAP_STRIDE] = data[DEPTH-443]
 exp_t0 = data[DEPTH + 9]
 exp_t1 = data[DEPTH + 9 - TAP_STRIDE]
 exp_t2 = data[DEPTH + 9 - 2 * TAP_STRIDE]

 if t0 != exp_t0 or t1 != exp_t1 or t2 != exp_t2:
 fail += 1
 if fail <= 3:
 print(f" [fuzz-tap] trial={trial}: "
 f"t0={t0}/{exp_t0} t1={t1}/{exp_t1} t2={t2}/{exp_t2}")

 return n, fail


def fuzz_padding(n, seed):
 """Verify padding_sel inserts zeros correctly."""
 rng = random.Random(seed)
 fail = 0

 for _ in range(n):
 state = [0] * DEPTH
 # Fill with non-zero data
 for t in range(DEPTH):
 state, _ = model_step(state, rng.randint(1, DATA_MAX), 0, 1)
 # Now shift in one zero via padding_sel=1
 state, (t0, _, _) = model_step(state, 9999, 1, 1) # data_in ignored
 if t0 != 0:
 fail += 1
 return n, fail


def fuzz_hold(n, seed):
 """Verify shift_and_load=0 holds taps constant."""
 rng = random.Random(seed)
 fail = 0

 for _ in range(n):
 state = [0] * DEPTH
 for t in range(DEPTH):
 state, _ = model_step(state, rng.randint(DATA_MIN, DATA_MAX), 0, 1)
 # Record taps
 t0 = state[0]; t1 = state[TAP_STRIDE]; t2 = state[2*TAP_STRIDE]
 # Hold for 5 cycles
 for _ in range(5):
 state, (nt0, nt1, nt2) = model_step(state, 9999, 0, 0)
 if nt0 != t0 or nt1 != t1 or nt2 != t2:
 fail += 1
 return n, fail


def main:
 fast = "--fast" in sys.argv
 n_fuzz = 10 if fast else 100

 vec_dir = (Path(__file__).resolve.parent.parent.parent
 / "tb" / "common" / "vectors")
 vec_path = vec_dir / "fifo_3x3_vectors.hex"

 print("=" * 70)
 print("FIFO_3X3 BIT-TRUE SHADOW SIMULATOR")
 print(f"DEPTH={DEPTH} TAP_STRIDE={TAP_STRIDE}")
 print("=" * 70)

 total_cases, total_fail = 0, 0

 print("\n[Stage 1] Golden-vector cross-check")
 if not vec_path.exists:
 print(f" WARNING: {vec_path} not found")
 else:
 n1, f1 = check_golden(vec_path)
 print(f" {n1 - f1}/{n1} PASS ({f1} fail)")
 total_cases += n1; total_fail += f1

 print(f"\n[Stage 2] Tap-position fuzz ({n_fuzz} trials)")
 n2, f2 = fuzz_tap_positions(n_fuzz, 0xF1F0CADE)
 print(f" {n2 - f2}/{n2} PASS ({f2} fail)")
 total_cases += n2; total_fail += f2

 print(f"\n[Stage 3] Padding-select fuzz ({n_fuzz} trials)")
 n3, f3 = fuzz_padding(n_fuzz, 0xABCDEF01)
 print(f" {n3 - f3}/{n3} PASS ({f3} fail)")
 total_cases += n3; total_fail += f3

 print(f"\n[Stage 4] Hold-state fuzz ({n_fuzz} trials)")
 n4, f4 = fuzz_hold(n_fuzz, 0x12345678)
 print(f" {n4 - f4}/{n4} PASS ({f4} fail)")
 total_cases += n4; total_fail += f4

 print("\n" + "=" * 70)
 print(f"TOTAL: {total_cases - total_fail:,} / {total_cases:,} PASS")
 if total_fail == 0:
 print("RESULT: *** ALL CHECKS PASSED ***")
 sys.exit(0)
 else:
 print(f"RESULT: *** {total_fail:,} FAILURES ***")
 sys.exit(1)


if __name__ == "__main__":
 main
