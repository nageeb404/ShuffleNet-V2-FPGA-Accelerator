"""
gen_adder_tree_29_vectors.py
=============================
Generate test vectors for adder_tree_29 (Module 2.3 / common).


File format: 2 lines per test case
 Line 1: in0..in28 (29 hex values, MUL_OUT_W=23-bit 2's-complement, 6-hex each)
 Line 2: expected (1 hex value, OUT_W=31-bit 2's-complement, 8-hex)
"""

import random, os
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")

IN_W = 23 # MUL_OUT_W
OUT_W = 31 # IN_W + 8 (4 Adder3 levels)

IN_MAX = (1 << (IN_W - 1)) - 1
IN_MIN = -(1 << (IN_W - 1))


def mask(w): return (1 << w) - 1
def to_uns(v, w): return int(v) & mask(w)
def to_sgn(u, w):
 u = int(u) & mask(w)
 return u - (1 << w) if (u >> (w - 1)) else u
def hex_str(v, w): return f"{to_uns(v, w):0{(w+3)//4}x}"


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


def model_adder_tree_29(ins):
 """29-input tree: L1 (9 Adder3) -> L2 (3 Adder3) -> L3 (1 Adder3) -> L4 (1 extra Adder3)."""
 L1_W = IN_W + 2
 L2_W = L1_W + 2
 L3_W = L2_W + 2
 # L1
 l1 = [model_adder3(ins[3*i], ins[3*i+1], ins[3*i+2], IN_W) for i in range(9)]
 # L2
 l2 = [model_adder3(l1[3*i], l1[3*i+1], l1[3*i+2], L1_W) for i in range(3)]
 # L3
 l3 = model_adder3(l2[0], l2[1], l2[2], L2_W)
 # L4 (extra): l3 + in27 + in28 (sign-extend in27,in28 to L3_W)
 in27_ext = to_sgn(to_uns(ins[27], L3_W), L3_W)
 in28_ext = to_sgn(to_uns(ins[28], L3_W), L3_W)
 return model_adder3(l3, in27_ext, in28_ext, L3_W)


def rand_in:
 return random.randint(IN_MIN, IN_MAX)


def write_vectors(out_path, n_random=200):
 cases = []

 # Deterministic edge cases
 cases += [
 [0]*29,
 [1]*29,
 [IN_MAX]*29, # max positive -> saturates tree output
 [IN_MIN]*29, # max negative
 [-1]*29,
 [IN_MAX]*27 + [0, 0], # extra Adder3 inputs = 0
 [IN_MIN]*27 + [0, 0],
 [IN_MAX]*27 + [IN_MAX, IN_MAX], # saturate extra Adder3
 [IN_MIN]*27 + [IN_MIN, IN_MIN],
 ]

 for _ in range(n_random):
 cases.append([rand_in for _ in range(29)])

 out_dir = Path(out_path).parent
 out_dir.mkdir(parents=True, exist_ok=True)

 with open(out_path, "w") as f:
 f.write("// adder_tree_29 test vectors\n")
 f.write("// Format: 2 lines per case\n")
 f.write(f"// Line 1: in0..in28 (29 x 6-hex {IN_W}-bit values)\n")
 f.write(f"// Line 2: expected (1 x 8-hex {OUT_W}-bit value)\n")
 for ins in cases:
 result = model_adder_tree_29(ins)
 in_hex = " ".join(hex_str(v, IN_W) for v in ins)
 f.write(f"{in_hex}\n")
 f.write(f"{hex_str(result, OUT_W)}\n")

 print(f"Written {len(cases)} test cases to {out_path}")
 return len(cases)


if __name__ == "__main__":
 out_path = os.path.join(PROJ_ROOT, "tb", "common", "vectors",
 "adder_tree_29_vectors.hex")
 n = write_vectors(out_path)
 print(f"Done. {n} cases.")
