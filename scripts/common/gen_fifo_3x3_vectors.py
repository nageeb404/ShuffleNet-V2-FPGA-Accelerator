#!/usr/bin/env python3
# =============================================================================
# gen_fifo_3x3_vectors.py
# -----------------------------------------------------------------------------
# Generate golden test vectors for fifo_3x3 (Module 1.5).
# The FIFO is a depth-455 shift register with an input MUX for zero-padding.
# 3 output taps at positions 0, TAP_STRIDE=226, 2*TAP_STRIDE=452.
# Each vector represents ONE clock edge where shift_and_load=1 (or 0 for hold).
# File format: one line per test cycle
# data_in_hex padding_sel(0/1) shift_and_load(0/1)
# expected_tap0_hex expected_tap1_hex expected_tap2_hex
# All values are 15-bit two's-complement hex (4 digits).
# padding_sel and shift_and_load are single hex digits (0 or 1).
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

def hex_str(v, w):
 digits = (w + 3) // 4
 return f"{to_uns(v, w):0{digits}x}"


def model_fifo(state, data_in, padding_sel, shift_and_load):
 """
 Advance the FIFO model by one clock cycle.
 state: list of DEPTH signed ints (state[0] = newest).
 Returns new state and (tap0, tap1, tap2).
 """
 if shift_and_load:
 val = 0 if padding_sel else data_in
 new_state = [val] + state[:-1]
 else:
 new_state = state[:]
 tap0 = new_state[0]
 tap1 = new_state[TAP_STRIDE]
 tap2 = new_state[2 * TAP_STRIDE]
 return new_state, (tap0, tap1, tap2)


def gen_vectors(out_path: Path):
 cases = []

 # ---- Sequence design ----
 # Phases:
 # 1. First TAP_STRIDE cycles (226): real data, shift_and_load=1
 # -> tap0 changes each cycle, tap1/tap2 still 0
 # 2. Next TAP_STRIDE cycles (226): zero padding, shift_and_load=1
 # -> original data rolls into tap1 position; zeros into tap0
 # 3. 10 hold cycles (shift_and_load=0): taps must stay constant
 # 4. Next TAP_STRIDE cycles (226): real data again
 # -> original data now at tap2, zeros at tap1, new data at tap0
 # 5. 50 random cycles with random padding_sel and shift_and_load

 rng = random.Random(0xDEADF1F0)

 def rand_q68:
 return rng.randint(DATA_MIN, DATA_MAX)

 phase1 = [(rand_q68, 0, 1) for _ in range(TAP_STRIDE)]
 phase2 = [(0, 1, 1) for _ in range(TAP_STRIDE)]
 phase3 = [(rand_q68, 0, 0) for _ in range(10)] # hold
 phase4 = [(rand_q68, 0, 1) for _ in range(TAP_STRIDE)]
 phase5 = [(rand_q68, rng.randint(0,1), rng.randint(0,1))
 for _ in range(50)]

 all_phases = phase1 + phase2 + phase3 + phase4 + phase5

 # Simulate the FIFO from reset (all zeros)
 state = [0] * DEPTH
 for (data_in, padding_sel, sal) in all_phases:
 state, (t0, t1, t2) = model_fifo(state, data_in, padding_sel, sal)
 cases.append((data_in, padding_sel, sal, t0, t1, t2))

 total = len(cases)
 with open(out_path, "w") as f:
 f.write("// fifo_3x3 golden test vectors\n")
 f.write("// -- Module 1.5\n")
 f.write(f"// DEPTH={DEPTH}, TAP_STRIDE={TAP_STRIDE}\n")
 f.write("// One line per clock edge:\n")
 f.write("// data_in padding_sel shift_and_load tap0 tap1 tap2\n")
 f.write(f"// n_cycles={total}\n")
 for (d, ps, sal, t0, t1, t2) in cases:
 f.write(f"{hex_str(d, DATA_W)} {ps} {sal} "
 f"{hex_str(t0, DATA_W)} {hex_str(t1, DATA_W)} {hex_str(t2, DATA_W)}\n")

 print(f"[fifo_3x3] Wrote {total} cycles to {out_path}")
 return total


def main:
 if len(sys.argv) > 1:
 out_dir = Path(sys.argv[1])
 else:
 out_dir = (Path(__file__).resolve.parent.parent.parent
 / "tb" / "common" / "vectors")
 out_dir.mkdir(parents=True, exist_ok=True)
 gen_vectors(out_dir / "fifo_3x3_vectors.hex")
 print("Done.")


if __name__ == "__main__":
 main
