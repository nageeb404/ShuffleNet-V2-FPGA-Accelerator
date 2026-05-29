#!/usr/bin/env python3
# =============================================================================
# gen_fifo_pool_vectors.py
# -----------------------------------------------------------------------------
# Generate golden test vectors for fifo_pool (Module 1.6).
# =============================================================================

import random, sys
from pathlib import Path

DATA_W      = 15
DEPTH       = 231
TAP_STRIDE  = (DEPTH - 3) // 2   # 114
DATA_MAX    =  (1 << (DATA_W - 1)) - 1
DATA_MIN    = -(1 << (DATA_W - 1))


def mask(w):  return (1 << w) - 1
def to_uns(v, w): return int(v) & mask(w)
def to_sgn(u, w):
    u = int(u) & mask(w)
    return u - (1 << w) if (u >> (w-1)) else u
def hex_str(v, w):
    return f"{to_uns(v, w):0{(w+3)//4}x}"

def model_step(state, data_in, padding_sel, sal):
    if sal:
        val = 0 if padding_sel else data_in
        ns = [val] + state[:-1]
    else:
        ns = state[:]
    return ns, (ns[0], ns[TAP_STRIDE], ns[2*TAP_STRIDE])

def gen_vectors(out_path: Path):
    rng = random.Random(0xF00DBEEF)
    cases = []
    def rq(): return rng.randint(DATA_MIN, DATA_MAX)

    # Phase 1: TAP_STRIDE real-data shifts -> tap1/tap2 still 0
    cases += [(rq(), 0, 1) for _ in range(TAP_STRIDE)]
    # Phase 2: TAP_STRIDE zero-padding shifts
    cases += [(0,    1, 1) for _ in range(TAP_STRIDE)]
    # Phase 3: 10 hold cycles
    cases += [(rq(), 0, 0) for _ in range(10)]
    # Phase 4: TAP_STRIDE more real-data shifts
    cases += [(rq(), 0, 1) for _ in range(TAP_STRIDE)]
    # Phase 5: 50 random
    cases += [(rq(), rng.randint(0,1), rng.randint(0,1)) for _ in range(50)]

    state = [0] * DEPTH
    with open(out_path, "w") as f:
        f.write("// fifo_pool golden test vectors\n")
        f.write("// Module 1.6\n")
        f.write(f"// DEPTH={DEPTH}  TAP_STRIDE={TAP_STRIDE}\n")
        f.write("// data_in  padding_sel  shift_and_load  tap0  tap1  tap2\n")
        f.write(f"// n_cycles={len(cases)}\n")
        for (d, ps, sal) in cases:
            state, (t0, t1, t2) = model_step(state, d, ps, sal)
            f.write(f"{hex_str(d,DATA_W)} {ps} {sal} "
                    f"{hex_str(t0,DATA_W)} {hex_str(t1,DATA_W)} {hex_str(t2,DATA_W)}\n")
    print(f"[fifo_pool] Wrote {len(cases)} cycles to {out_path}")

def main():
    out_dir = (Path(sys.argv[1]) if len(sys.argv) > 1
               else Path(__file__).resolve().parent.parent.parent/"tb"/"group1"/"vectors")
    out_dir.mkdir(parents=True, exist_ok=True)
    gen_vectors(out_dir / "fifo_pool_vectors.hex")
    print("Done.")

if __name__ == "__main__":
    main()
