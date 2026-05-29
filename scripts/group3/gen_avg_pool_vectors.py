"""
gen_avg_pool_vectors.py
========================
Generate test vectors for avg_pool_core (Module 3.2).

 average = (accumulator * 5) >> 8 (approximates / 49)
 accumulate 49 pixels per channel, 16 channels in parallel

Vector format per case:
 Header: N_CHAN N_PIX (e.g. "16 49")
 Per-pixel lines (49 lines): 16 hex values (one per channel)
 Result line: 16 hex expected outputs
"""
import os, random, math
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")

DATA_W = 15
ACC_W = DATA_W + 6 # 21
MUL5_W = ACC_W + 2 # 23
N_CHAN = 16
N_PIX = 49 # 7x7

IN_MIN = -(1 << (DATA_W-1))
IN_MAX = (1 << (DATA_W-1)) - 1
Q_MAX = (1 << (DATA_W-1)) - 1 # 16383

def to_signed(v, bits):
 mask = (1 << bits) - 1
 v &= mask
 if v >= (1 << (bits-1)):
 v -= (1 << bits)
 return v

def avg_pool_model(pixels, n_chan=N_CHAN, n_pix=N_PIX):
 """
 RTL-accurate Python model of avg_pool_core.
 pixels: list of n_pix lists, each of length n_chan (signed DATA_W values)
 Returns: list of n_chan output values
 """
 results = []
 for ch in range(n_chan):
 # Accumulate
 acc = 0
 for pix_idx in range(n_pix):
 d = pixels[pix_idx][ch]
 # Sign-extend to ACC_W
 acc += d
 # acc is now an exact Python integer (no overflow)
 # Clamp to ACC_W signed range
 acc = to_signed(acc, ACC_W)

 # Multiply by 5: (acc<<2) + acc, clamped to MUL5_W
 acc_x5 = (acc << 2) + acc
 acc_x5 = to_signed(acc_x5, MUL5_W)

 # >> 8: take bits [MUL5_W-1 : MUL5_W-DATA_W] = top DATA_W bits
 # Equivalent to arithmetic right shift by (MUL5_W - DATA_W) = 8
 avg_raw = acc_x5 >> (MUL5_W - DATA_W)
 # to_signed not needed here since we used Python signed >> (arithmetic)
 avg_raw = to_signed(avg_raw, DATA_W)

 # One-sided quantizer: clamp [0, Q_MAX]
 if avg_raw < 0:
 avg_sat = 0
 elif avg_raw > Q_MAX:
 avg_sat = Q_MAX
 else:
 avg_sat = avg_raw

 results.append(avg_sat)
 return results

def sh(v, w=DATA_W):
 mask = (1 << w) - 1
 return format(v & mask, f'0{(w+3)//4}x')

def write_vectors(out_path, seed=42):
 rng = random.Random(seed)
 Path(out_path).parent.mkdir(parents=True, exist_ok=True)

 cases = []

 # Case 0: all zeros
 cases.append([[0]*N_CHAN for _ in range(N_PIX)])
 # Case 1: all 256 (1.0 in Q6.8) -> avg = (49*256*5)>>8 = 62720>>8 = 245
 cases.append([[256]*N_CHAN for _ in range(N_PIX)])
 # Case 2: all max -> accumulate, no saturation expected
 cases.append([[IN_MAX]*N_CHAN for _ in range(N_PIX)])
 # Case 3: alternating max/0 -> avg = (25*max*5)>>8
 cases.append([[IN_MAX if i%2==0 else 0]*N_CHAN for i in range(N_PIX)])
 # Case 4: random
 for _ in range(4):
 cases.append([[rng.randint(0, IN_MAX) for _ in range(N_CHAN)]
 for _ in range(N_PIX)])

 with open(out_path, 'w') as f:
 f.write(f"// avg_pool_core vectors: N_CHAN={N_CHAN} N_PIX={N_PIX}\n")
 for case_idx, pixels in enumerate(cases):
 expected = avg_pool_model(pixels)
 f.write(f"\n// Case {case_idx}\n")
 f.write(f"{N_CHAN} {N_PIX}\n")
 for pix_row in pixels:
 f.write(' '.join(sh(v) for v in pix_row) + '\n')
 f.write(' '.join(sh(v) for v in expected) + '\n')

 # Verify case 1 manually
 exp1 = avg_pool_model([[256]*N_CHAN]*N_PIX)
 print(f"Case 1 expected (all 256): {exp1[0]} (should be 245)")
 print(f"Written {len(cases)} cases to {out_path}")

if __name__ == "__main__":
 out_path = os.path.join(PROJ_ROOT, "tb", "group3", "vectors",
 "avg_pool_vectors.hex")
 write_vectors(out_path)
