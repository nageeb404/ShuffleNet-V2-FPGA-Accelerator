"""
gen_dw_conv3x3_core_vectors.py
===============================
Generate test vectors for dw_conv3x3_core (Module 2.2).


58 dw_conv3x3_filter_unit instances in parallel.

File format: 58 lines per test case (one line per filter).
  Each line: d0..d8 w0..w8 bias expected   (9+9+1+1 = 20 x 4-hex 15-bit values)

Cases are separated by a blank line for readability.

Pipeline timing (same as filter unit):
  negedge 0: drive all 58 filters' data + weights, en=1
  negedge 1: drive all 58 biases
  negedge 2: CHECK all 58 results
"""

import random, os
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT  = os.path.join(SCRIPT_DIR, "..", "..")

DATA_W     = 15
MUL_FULL_W = 30
MUL_DROP   = 7
MAC_OUT_W  = MUL_FULL_W - MUL_DROP   # 23
TREE_OUT_W = MAC_OUT_W + 4            # 27
BIAS_OUT_W = TREE_OUT_W + 1           # 28
N_FILT     = 58
N_TAPS     = 9

DATA_MAX   =  (1 << (DATA_W - 1)) - 1
DATA_MIN   = -(1 << (DATA_W - 1))


def mask(w):      return (1 << w) - 1
def to_uns(v, w): return int(v) & mask(w)
def to_sgn(u, w):
    u = int(u) & mask(w)
    return u - (1 << w) if (u >> (w - 1)) else u
def hex_str(v, w): return f"{to_uns(v, w):0{(w+3)//4}x}"


def model_mac(a, b):
    full    = int(a) * int(b)
    dropped = full >> MUL_DROP
    return to_sgn(to_uns(dropped, MAC_OUT_W), MAC_OUT_W)


def model_adder3(a_s, b_s, c_s, in_w):
    out_w = in_w + 2
    a = to_uns(a_s, out_w); b = to_uns(b_s, out_w); c = to_uns(c_s, out_w)
    sv = cv = 0
    for i in range(out_w):
        ai = (a >> i) & 1; bi = (b >> i) & 1; ci = (c >> i) & 1
        sv |= (ai ^ bi ^ ci) << i
        cv |= ((ai & bi) | (bi & ci) | (ai & ci)) << i
    carry_s = (cv << 1) & mask(out_w)
    raw = to_sgn(sv, out_w) + to_sgn(carry_s, out_w)
    return to_sgn(to_uns(raw, out_w), out_w)


def model_adder_tree_9(macs):
    l1_0 = model_adder3(macs[0], macs[1], macs[2], MAC_OUT_W)
    l1_1 = model_adder3(macs[3], macs[4], macs[5], MAC_OUT_W)
    l1_2 = model_adder3(macs[6], macs[7], macs[8], MAC_OUT_W)
    return model_adder3(l1_0, l1_1, l1_2, MAC_OUT_W + 2)


def model_quantizer_twosided(v, in_w, out_w):
    out_max =  (1 << (out_w - 1)) - 1
    out_min = -(1 << (out_w - 1))
    v_s = to_sgn(to_uns(v, in_w), in_w)
    if v_s > out_max: return out_max
    if v_s < out_min: return out_min
    return v_s


def model_dw_filter(data, weights, bias):
    macs     = [model_mac(data[i], weights[i]) for i in range(N_TAPS)]
    tree_out = model_adder_tree_9(macs)
    tree_ext = to_sgn(to_uns(tree_out, BIAS_OUT_W), BIAS_OUT_W)
    bias_ext = to_sgn(to_uns(bias,     BIAS_OUT_W), BIAS_OUT_W)
    bias_sum = to_sgn(to_uns(tree_ext + bias_ext, BIAS_OUT_W), BIAS_OUT_W)
    return model_quantizer_twosided(bias_sum, BIAS_OUT_W, DATA_W)


def rand_q68():
    return random.randint(DATA_MIN, DATA_MAX)


def write_vectors(out_path, n_random=20):
    cases = []

    # Deterministic edge cases
    cases.append((
        [[0]*N_TAPS for _ in range(N_FILT)],
        [[0]*N_TAPS for _ in range(N_FILT)],
        [0]*N_FILT
    ))
    cases.append((
        [[1]*N_TAPS for _ in range(N_FILT)],
        [[1]*N_TAPS for _ in range(N_FILT)],
        [0]*N_FILT
    ))
    cases.append((
        [[DATA_MAX]*N_TAPS for _ in range(N_FILT)],
        [[DATA_MAX]*N_TAPS for _ in range(N_FILT)],
        [DATA_MAX]*N_FILT
    ))
    cases.append((
        [[DATA_MIN]*N_TAPS for _ in range(N_FILT)],
        [[DATA_MIN]*N_TAPS for _ in range(N_FILT)],
        [0]*N_FILT
    ))

    # Random cases
    for _ in range(n_random):
        d = [[rand_q68() for _ in range(N_TAPS)] for _ in range(N_FILT)]
        w = [[rand_q68() for _ in range(N_TAPS)] for _ in range(N_FILT)]
        b = [rand_q68() for _ in range(N_FILT)]
        cases.append((d, w, b))

    out_dir = Path(out_path).parent
    out_dir.mkdir(parents=True, exist_ok=True)

    with open(out_path, "w") as f:
        f.write("// dw_conv3x3_core test vectors\n")
        f.write(f"// Format: {N_FILT} lines per case (one filter per line)\n")
        f.write("// Each line: d0..d8 w0..w8 bias expected  (20 x 4-hex values)\n")
        f.write(f"// n_cases={len(cases)}\n")
        for case_idx, (d, w, b) in enumerate(cases):
            results = [model_dw_filter(d[flt], w[flt], b[flt]) for flt in range(N_FILT)]
            for flt in range(N_FILT):
                d_hex   = " ".join(hex_str(d[flt][t], DATA_W) for t in range(N_TAPS))
                w_hex   = " ".join(hex_str(w[flt][t], DATA_W) for t in range(N_TAPS))
                b_hex   = hex_str(b[flt], DATA_W)
                res_hex = hex_str(results[flt], DATA_W)
                f.write(f"{d_hex} {w_hex} {b_hex} {res_hex}\n")
            f.write("\n")  # blank line between cases

    print(f"Written {len(cases)} test cases ({len(cases)*N_FILT} lines) to {out_path}")
    return len(cases)


if __name__ == "__main__":
    out_path = os.path.join(PROJ_ROOT, "tb", "group2", "vectors",
                            "dw_conv3x3_core_vectors.hex")
    n = write_vectors(out_path)
    print(f"Done. {n} cases.")
