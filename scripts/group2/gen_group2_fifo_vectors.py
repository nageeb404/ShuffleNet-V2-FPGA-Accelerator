"""
gen_group2_fifo_vectors.py
============================
Generate test vectors for group2_fifo (Module 2.6).


One-fit-all 119-deep FIFO with:
  - Input MUX: zero-padding or data_in
  - 9 window taps: first 3 fixed (positions 0,1,2), last 6 via 4:1 MUX (width_sel)
  - width_sel: 00=W7(stride=9), 01=W14(stride=16), 10=W28(stride=30), 11=W56(stride=58)

Vector format per case:
  Line 1: width_sel (1 hex token, 0-3)
  N_STEPS lines: shift_load padding_sel data_in tap00 tap01 tap02 tap10 tap11 tap12 tap20 tap21 tap22
  Blank line between cases.
"""

import random
import os
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT  = os.path.join(SCRIPT_DIR, "..", "..")

DATA_W   = 15
DEPTH    = 119         # G2_FIFO_DEPTH = 2*58 + 3
N_STEPS  = 130         # steps per case (> DEPTH to test all taps fully)

DATA_MAX =  (1 << (DATA_W - 1)) - 1
DATA_MIN = -(1 << (DATA_W - 1))

# Padded stride for each width_sel value
# padded width = feature map width + 2 zero-padding columns (1 each side)
STRIDES = {
    0b00: 9,   # W=7:  7+2=9
    0b01: 16,  # W=14: 14+2=16
    0b10: 30,  # W=28: 28+2=30
    0b11: 58,  # W=56: 56+2=58
}


def mask(w):
    return (1 << w) - 1


def to_uns(v, w):
    return int(v) & mask(w)


def hex_str(v, w):
    return f"{to_uns(v, w):0{(w + 3) // 4}x}"


def sim_step(sr, shift_and_load, padding_sel, data_in):
    """Return new 119-element shift register state after one clock."""
    if not shift_and_load:
        return sr[:]
    val = 0 if padding_sel else int(data_in)
    return [val] + sr[:-1]


def get_taps(sr, stride):
    """Return all 9 window taps given the stride for this width_sel."""
    return (
        sr[0],          sr[1],          sr[2],
        sr[stride],     sr[stride + 1], sr[stride + 2],
        sr[2 * stride], sr[2 * stride + 1], sr[2 * stride + 2],
    )


def write_vectors(out_path, n_random=3):
    cases = []

    # One case per width_sel with a sequential data pattern
    for ws in range(4):
        stride = STRIDES[ws]
        steps = []
        sr = [0] * DEPTH
        val = 1
        for _ in range(N_STEPS):
            sl = 1
            ps = 0
            din = val & mask(DATA_W - 1)  # keep positive for easy reading
            val += 1
            sr_next = sim_step(sr, sl, ps, din)
            taps = get_taps(sr_next, stride)
            steps.append((sl, ps, din, taps))
            sr = sr_next
        cases.append((ws, steps))

    # One case with padding_sel toggling (width_sel=3, W=56)
    for ws in [0b11]:
        stride = STRIDES[ws]
        steps = []
        sr = [0] * DEPTH
        for i in range(N_STEPS):
            sl = 1
            ps = 1 if (i % 4 == 3) else 0
            din = ((i * 7 + 1) & mask(DATA_W - 1))
            sr_next = sim_step(sr, sl, ps, din)
            taps = get_taps(sr_next, stride)
            steps.append((sl, ps, din, taps))
            sr = sr_next
        cases.append((ws, steps))

    # Random cases for each width_sel
    random.seed(42)
    for _ in range(n_random):
        ws = random.randint(0, 3)
        stride = STRIDES[ws]
        steps = []
        sr = [0] * DEPTH
        for _ in range(N_STEPS):
            sl = 1
            ps = random.randint(0, 1)
            din = random.randint(DATA_MIN, DATA_MAX)
            sr_next = sim_step(sr, sl, ps, din)
            taps = get_taps(sr_next, stride)
            steps.append((sl, ps, din, taps))
            sr = sr_next
        cases.append((ws, steps))

    out_dir = Path(out_path).parent
    out_dir.mkdir(parents=True, exist_ok=True)

    with open(out_path, "w") as f:
        f.write("// group2_fifo test vectors\n")
        f.write(f"// DEPTH={DEPTH}  DATA_W={DATA_W}  N_STEPS={N_STEPS}\n")
        f.write("// Format per case:\n")
        f.write("//   Line 1: width_sel (0-3)\n")
        f.write("//   N_STEPS lines: shift_load padding_sel data_in tap00..tap22 (12 tokens)\n")
        f.write("//   Blank line between cases\n")

        for case_idx, (ws, steps) in enumerate(cases):
            stride = STRIDES[ws]
            f.write(f"\n// Case {case_idx}: width_sel={ws} stride={stride}\n")
            f.write(f"{ws:x}\n")
            for (sl, ps, din, taps) in steps:
                tokens = [f"{sl}", f"{ps}", hex_str(din, DATA_W)]
                tokens += [hex_str(t, DATA_W) for t in taps]
                f.write(" ".join(tokens) + "\n")
            f.write("\n")

    total_checks = sum(len(steps) for _, steps in cases)
    print(f"Written {len(cases)} cases, {total_checks} checks to {out_path}")
    return len(cases)


if __name__ == "__main__":
    out_path = os.path.join(PROJ_ROOT, "tb", "group2", "vectors",
                            "group2_fifo_vectors.hex")
    n = write_vectors(out_path)
    print(f"Done. {n} cases.")
