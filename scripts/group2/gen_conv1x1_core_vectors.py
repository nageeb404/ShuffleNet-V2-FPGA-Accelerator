"""
gen_conv1x1_core_vectors.py
=============================
Generate test vectors for conv1x1_core (Module 2.5).


58 conv1x1_filter_unit instances in parallel, sharing 29 data inputs.

File format: (N_ACC * N_FILT + N_FILT) lines per test case.
  For each accumulation step k (0..N_ACC-1):
    58 lines, one per filter:
      w0..w28   (29 x 4-hex 15-bit weight tokens for filter f at step k)
  Then 58 lines (one per filter):
      bias expected   (2 x 4-hex 15-bit tokens for filter f)
  Data inputs d0..d28 are the same for all 58 filters per step (on a separate line).

Simpler format used (avoids huge lines):
  Per case:  N_ACC+1 "blocks"
    Block k (k=0..N_ACC-1):
      1 line: d0..d28    (29 tokens, data for this accumulation step, shared)
      58 lines: w0..w28  (29 tokens each, weights for each filter at this step)
    Block N_ACC:
      58 lines: bias expected  (2 tokens each, for each filter)

This keeps each line short (max 29 or 2 tokens).
"""

import random, os
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT  = os.path.join(SCRIPT_DIR, "..", "..")

DATA_W     = 15
MUL_FULL_W = 30
MUL_DROP   = 7
MAC_OUT_W  = MUL_FULL_W - MUL_DROP   # 23
TREE_OUT_W = MAC_OUT_W + 8            # 31
ACC_OUT_W  = TREE_OUT_W + 3           # 34
BIAS_OUT_W = ACC_OUT_W + 1            # 35
N_FILT     = 58
N_CHAN     = 29
N_ACC      = 7

DATA_MAX   =  (1 << (DATA_W - 1)) - 1
DATA_MIN   = -(1 << (DATA_W - 1))


def mask(w):      return (1 << w) - 1
def to_uns(v, w): return int(v) & mask(w)
def to_sgn(u, w):
    u = int(u) & mask(w)
    return u - (1 << w) if (u >> (w - 1)) else u
def hex_str(v, w): return f"{to_uns(v, w):0{(w+3)//4}x}"


def model_mac(a, b):
    return to_sgn(to_uns((int(a) * int(b)) >> MUL_DROP, MAC_OUT_W), MAC_OUT_W)


def model_adder3(a_s, b_s, c_s, in_w):
    out_w = in_w + 2
    a = to_uns(a_s, out_w); b = to_uns(b_s, out_w); c = to_uns(c_s, out_w)
    sv = cv = 0
    for i in range(out_w):
        ai = (a >> i) & 1; bi = (b >> i) & 1; ci = (c >> i) & 1
        sv |= (ai ^ bi ^ ci) << i
        cv |= ((ai & bi) | (bi & ci) | (ai & ci)) << i
    carry_s = (cv << 1) & mask(out_w)
    return to_sgn(to_uns(to_sgn(sv, out_w) + to_sgn(carry_s, out_w), out_w), out_w)


def model_tree29(macs):
    L1_W = MAC_OUT_W + 2
    L2_W = L1_W + 2
    L3_W = L2_W + 2
    l1 = [model_adder3(macs[3*i], macs[3*i+1], macs[3*i+2], MAC_OUT_W) for i in range(9)]
    l2 = [model_adder3(l1[3*i], l1[3*i+1], l1[3*i+2], L1_W) for i in range(3)]
    l3 = model_adder3(l2[0], l2[1], l2[2], L2_W)
    in27_ext = to_sgn(to_uns(macs[27], L3_W), L3_W)
    in28_ext = to_sgn(to_uns(macs[28], L3_W), L3_W)
    return model_adder3(l3, in27_ext, in28_ext, L3_W)


def model_quant_onesided(v, in_w, out_w):
    out_max = (1 << (out_w - 1)) - 1
    v_s = to_sgn(to_uns(v, in_w), in_w)
    if v_s < 0:       return 0
    if v_s > out_max: return out_max
    return v_s


def model_conv1x1_filter(data_steps, weight_steps, bias):
    acc = 0
    for k in range(N_ACC):
        macs     = [model_mac(data_steps[k][c], weight_steps[k][c]) for c in range(N_CHAN)]
        tree_out = model_tree29(macs)
        tree_ext = to_sgn(to_uns(tree_out, ACC_OUT_W), ACC_OUT_W)
        acc      = to_sgn(to_uns(acc + tree_ext, ACC_OUT_W), ACC_OUT_W)
    acc_ext  = to_sgn(to_uns(acc, BIAS_OUT_W), BIAS_OUT_W)
    bias_ext = to_sgn(to_uns(bias, BIAS_OUT_W), BIAS_OUT_W)
    bias_sum = to_sgn(to_uns(acc_ext + bias_ext, BIAS_OUT_W), BIAS_OUT_W)
    return model_quant_onesided(bias_sum, BIAS_OUT_W, DATA_W)


def rand_q68():
    return random.randint(DATA_MIN, DATA_MAX)


def write_vectors(out_path, n_random=10):
    # Each case: data_steps[N_ACC][N_CHAN], weight_steps[N_ACC][N_FILT][N_CHAN], biases[N_FILT]
    cases = []

    # Edge case: all zeros
    cases.append((
        [[0]*N_CHAN]*N_ACC,
        [[[0]*N_CHAN]*N_ACC for _ in range(N_FILT)],
        [0]*N_FILT
    ))

    # Edge case: all ones
    cases.append((
        [[1]*N_CHAN]*N_ACC,
        [[[1]*N_CHAN]*N_ACC for _ in range(N_FILT)],
        [0]*N_FILT
    ))

    # Random cases
    for _ in range(n_random):
        d_steps = [[rand_q68() for _ in range(N_CHAN)] for _ in range(N_ACC)]
        w_steps = [[[rand_q68() for _ in range(N_CHAN)] for _ in range(N_ACC)]
                   for _ in range(N_FILT)]
        biases  = [rand_q68() for _ in range(N_FILT)]
        cases.append((d_steps, w_steps, biases))

    out_dir = Path(out_path).parent
    out_dir.mkdir(parents=True, exist_ok=True)

    with open(out_path, "w") as f:
        f.write("// conv1x1_core test vectors\n")
        f.write(f"// N_FILT={N_FILT}  N_CHAN={N_CHAN}  N_ACC={N_ACC}\n")
        f.write("// Format per case:\n")
        f.write(f"//   For k=0..{N_ACC-1}: 1 data line (29 tokens) + {N_FILT} weight lines (29 tokens each)\n")
        f.write(f"//   Then {N_FILT} bias+expected lines (2 tokens each)\n")

        for case_idx, (d_steps, w_steps, biases) in enumerate(cases):
            results = [model_conv1x1_filter(d_steps, w_steps[flt], biases[flt])
                       for flt in range(N_FILT)]

            for k in range(N_ACC):
                # Data line (shared across all 58 filters)
                d_hex = " ".join(hex_str(d_steps[k][c], DATA_W) for c in range(N_CHAN))
                f.write(f"{d_hex}\n")
                # Weight lines, one per filter
                for flt in range(N_FILT):
                    w_hex = " ".join(hex_str(w_steps[flt][k][c], DATA_W) for c in range(N_CHAN))
                    f.write(f"{w_hex}\n")

            # Bias + expected lines, one per filter
            for flt in range(N_FILT):
                f.write(f"{hex_str(biases[flt], DATA_W)} {hex_str(results[flt], DATA_W)}\n")

            f.write("\n")  # blank line between cases

    print(f"Written {len(cases)} test cases to {out_path}")
    return len(cases)


if __name__ == "__main__":
    out_path = os.path.join(PROJ_ROOT, "tb", "group2", "vectors",
                            "conv1x1_core_vectors.hex")
    n = write_vectors(out_path)
    print(f"Done. {n} cases.")
