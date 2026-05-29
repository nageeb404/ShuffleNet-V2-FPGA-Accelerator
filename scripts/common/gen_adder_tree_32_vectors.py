"""
gen_adder_tree_32_vectors.py
============================
Generate test vectors for adder_tree_32 (32-input, IN_W=23, OUT_W=30).


Vector format (one hex line per test):
  32 inputs (signed 23-bit as hex, space-separated), then expected output (signed 30-bit)
"""
import os, random, struct
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT  = os.path.join(SCRIPT_DIR, "..", "..")

IN_W  = 23
OUT_W = IN_W + 7  # 30

IN_MIN  = -(1 << (IN_W-1))
IN_MAX  =  (1 << (IN_W-1)) - 1
OUT_MIN = -(1 << (OUT_W-1))
OUT_MAX =  (1 << (OUT_W-1)) - 1

def signed_hex(v, width):
    mask = (1 << width) - 1
    return format(v & mask, f'0{(width+3)//4}x')

def py_sum32(vals):
    """Python model: exact signed sum (no overflow for 32 23-bit values)."""
    return sum(vals)

def write_vectors(out_path, n_cases=200, seed=42):
    rng = random.Random(seed)
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)

    cases = []
    # 1. All zeros
    cases.append([0]*32)
    # 2. All +1
    cases.append([1]*32)
    # 3. All -1
    cases.append([-1]*32)
    # 4. All max
    cases.append([IN_MAX]*32)
    # 5. All min
    cases.append([IN_MIN]*32)
    # 6. Alternating +max/-max
    cases.append([IN_MAX if i%2==0 else IN_MIN for i in range(32)])
    # Random
    while len(cases) < n_cases:
        cases.append([rng.randint(IN_MIN, IN_MAX) for _ in range(32)])

    errors = 0
    with open(out_path, 'w') as f:
        f.write(f"// adder_tree_32 vectors: IN_W={IN_W} OUT_W={OUT_W}\n")
        f.write(f"// Format: 32 hex inputs, then 1 hex output\n")
        for vals in cases:
            expected = py_sum32(vals)
            ins = ' '.join(signed_hex(v, IN_W) for v in vals)
            f.write(f"{ins} {signed_hex(expected, OUT_W)}\n")

    print(f"Written {len(cases)} vectors to {out_path}")
    return len(cases)

if __name__ == "__main__":
    out_path = os.path.join(PROJ_ROOT, "tb", "common", "vectors",
                            "adder_tree_32_vectors.hex")
    write_vectors(out_path)
