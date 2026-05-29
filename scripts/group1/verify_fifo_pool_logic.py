#!/usr/bin/env python3
# =============================================================================
# verify_fifo_pool_logic.py -- Shadow sim for fifo_pool (Module 1.6)
# =============================================================================

import random, sys
from pathlib import Path

DATA_W = 15
DEPTH = 231
TAP_STRIDE = (DEPTH - 3) // 2 # 114
DATA_MAX = (1 << (DATA_W - 1)) - 1
DATA_MIN = -(1 << (DATA_W - 1))

def mask(w): return (1 << w) - 1
def to_uns(v, w): return int(v) & mask(w)
def to_sgn(u, w):
 u = int(u) & mask(w)
 return u - (1 << w) if (u >> (w-1)) else u

def model_step(state, data_in, padding_sel, sal):
 if sal:
 val = 0 if padding_sel else data_in
 ns = [val] + state[:-1]
 else:
 ns = state[:]
 return ns, (ns[0], ns[TAP_STRIDE], ns[2*TAP_STRIDE])

def parse_hex_file(path):
 rows = []
 with open(path) as f:
 for line in f:
 line = line.strip
 if not line or line.startswith("//"): continue
 p = line.split
 if len(p) == 6:
 try:
 rows.append((to_sgn(int(p[0],16),DATA_W), int(p[1],16),
 int(p[2],16), to_sgn(int(p[3],16),DATA_W),
 to_sgn(int(p[4],16),DATA_W), to_sgn(int(p[5],16),DATA_W)))
 except ValueError: pass
 return rows

def check_golden(vec_path):
 rows = parse_hex_file(vec_path)
 state = [0] * DEPTH
 fail = 0
 for idx, (d, ps, sal, e0, e1, e2) in enumerate(rows):
 state, (t0, t1, t2) = model_step(state, d, ps, sal)
 if t0 != e0 or t1 != e1 or t2 != e2:
 fail += 1
 if fail <= 5:
 print(f" [golden] FAIL cycle={idx}: tap0={t0}/{e0} tap1={t1}/{e1} tap2={t2}/{e2}")
 return len(rows), fail

def fuzz(n, seed):
 rng = random.Random(seed)
 fail = 0
 for _ in range(n):
 state = [0] * DEPTH
 data = [rng.randint(DATA_MIN, DATA_MAX) for _ in range(DEPTH + 20)]
 for t in range(DEPTH + 20):
 state, _ = model_step(state, data[t], 0, 1)
 exp_t0 = data[DEPTH + 19]
 exp_t1 = data[DEPTH + 19 - TAP_STRIDE]
 exp_t2 = data[DEPTH + 19 - 2*TAP_STRIDE]
 t0, t1, t2 = state[0], state[TAP_STRIDE], state[2*TAP_STRIDE]
 if t0 != exp_t0 or t1 != exp_t1 or t2 != exp_t2:
 fail += 1
 return n, fail

def main:
 fast = "--fast" in sys.argv
 n_fuz = 50 if fast else 500
 vp = (Path(__file__).resolve.parent.parent.parent/"tb"/"group1"/"vectors"/"fifo_pool_vectors.hex")

 print("=" * 70)
 print(f"FIFO_POOL SHADOW SIMULATOR DEPTH={DEPTH} TAP_STRIDE={TAP_STRIDE}")
 print("=" * 70)

 tot, tfail = 0, 0

 print("\n[Stage 1] Golden-vector check")
 if not vp.exists:
 print(" WARNING: vector file not found")
 else:
 n, f = check_golden(vp)
 print(f" {n-f}/{n} PASS ({f} fail)")
 tot += n; tfail += f

 print(f"\n[Stage 2] Tap-position fuzz ({n_fuz} trials)")
 n, f = fuzz(n_fuz, 0xBEEFCAFE)
 print(f" {n-f}/{n} PASS ({f} fail)")
 tot += n; tfail += f

 print("\n" + "=" * 70)
 print(f"TOTAL: {tot-tfail}/{tot} PASS")
 if tfail == 0:
 print("RESULT: *** ALL CHECKS PASSED ***"); sys.exit(0)
 else:
 print(f"RESULT: *** {tfail} FAILURES ***"); sys.exit(1)

if __name__ == "__main__":
 main
