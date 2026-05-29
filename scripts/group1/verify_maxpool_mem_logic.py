"""
verify_maxpool_mem_logic.py
===========================
Bit-true Python shadow simulator for maxpool_mem (Module 1.11).

24 independent SDP BRAM instances. Write all channels in parallel each
clock; registered read output with 1-cycle latency.

Reads the same vector file used by the Verilog TB.

"""

import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")
VEC_FILE = os.path.join(PROJ_ROOT, "tb", "group1", "vectors",
 "maxpool_mem_tb_vectors.hex")

N_CHAN = 24
IMG_W = 4
IMG_H = 4
DEPTH = IMG_W * IMG_H # 16
DATA_W = 15
FLAT_W = N_CHAN * DATA_W # 360
FLAT_MASK = (1 << FLAT_W) - 1


class MaxpoolMem:
 def __init__(self, n_chan, depth, data_w):
 self.n_chan = n_chan
 self.depth = depth
 self.data_w = data_w
 self.mask = (1 << data_w) - 1
 self.flat_w = n_chan * data_w
 self.flat_mask = (1 << self.flat_w) - 1
 # 24 BRAM arrays
 self.mem = [[0]*depth for _ in range(n_chan)]
 # Registered read output (1-cycle latency)
 self.dout_flat = 0
 # Inputs
 self.addr_wr = 0
 self.addr_rd = 0
 self.data_in = 0 # flat 360-bit
 self.we = 0

 def clock_posedge(self):
 """Simulate one rising clock edge."""
 # Write (all channels simultaneously)
 if self.we:
 for ch in range(self.n_chan):
 val = (self.data_in >> (ch * self.data_w)) & self.mask
 self.mem[ch][self.addr_wr] = val

 # Registered read (all channels simultaneously)
 flat = 0
 for ch in range(self.n_chan):
 flat |= self.mem[ch][self.addr_rd] << (ch * self.data_w)
 self.dout_flat = flat

 def data_out(self):
 return self.dout_flat


def run:
 if not os.path.exists(VEC_FILE):
 print(f"ERROR: vector file not found: {VEC_FILE}")
 print("Run: python scripts/gen_maxpool_mem_vectors.py")
 sys.exit(1)

 mem = MaxpoolMem(N_CHAN, DEPTH, DATA_W)
 n_checks = 0
 pass_count = 0
 fail_count = 0

 print("==============================================")
 print("maxpool_mem shadow simulator")
 print(f"N_CHAN={N_CHAN} IMG_W={IMG_W} IMG_H={IMG_H} DEPTH={DEPTH}")
 print("==============================================")

 with open(VEC_FILE) as f:
 for line in f:
 line = line.strip
 if not line or line.startswith("//"):
 continue
 parts = line.split
 if len(parts) != 3:
 continue
 op = parts[0].upper
 addr = int(parts[1], 16)
 flat = int(parts[2], 16)

 if op == "W":
 mem.addr_wr = addr
 mem.data_in = flat
 mem.we = 1
 mem.clock_posedge
 mem.we = 0

 elif op == "R":
 mem.addr_rd = addr
 mem.we = 0
 mem.clock_posedge

 got = mem.data_out
 n_checks += 1
 if got == flat:
 pass_count += 1
 else:
 fail_count += 1
 if fail_count <= 5:
 print(f"FAIL addr={addr:04X}: got {got:090X}")
 print(f" exp {flat:090X}")

 print(f"Checks: {n_checks}")
 print(f"PASS : {pass_count} / {n_checks}")
 print(f"FAIL : {fail_count} / {n_checks}")
 if fail_count == 0:
 print("RESULT: *** ALL TESTS PASSED ***")
 else:
 print(f"RESULT: *** {fail_count} TESTS FAILED ***")
 print("==============================================")
 return fail_count == 0


if __name__ == "__main__":
 ok = run
 sys.exit(0 if ok else 1)
