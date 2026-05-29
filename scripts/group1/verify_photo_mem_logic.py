"""
verify_photo_mem_logic.py
=========================
Bit-true Python shadow simulator for photo_mem (Module 1.10).

Simulates the ping-pong BRAM with registered read (1-cycle latency) and
registered output mux. Reads the same vector file used by the Verilog TB
and reports pass/fail for all read checks.

"""

import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")
VEC_FILE = os.path.join(PROJ_ROOT, "tb", "group1", "vectors",
 "photo_mem_tb_vectors.hex")

IMG_W = 4
IMG_H = 4
DEPTH = IMG_W * IMG_H
DATA_W = 15
MASK = (1 << DATA_W) - 1 # 0x7FFF


# ---------------------------------------------------------------------------
# Photo memory model (Python shadow)
# ---------------------------------------------------------------------------
class PhotoMem:
 def __init__(self, depth, data_w):
 self.depth = depth
 self.data_w = data_w
 self.mask = (1 << data_w) - 1
 # 3 channels x 2 banks; initialized to 0
 self.banks = [[0]*depth, [0]*depth] # banks[bank][addr]
 self.ch_banks = [
 [[0]*depth, [0]*depth], # ch0 (ch1 in Verilog)
 [[0]*depth, [0]*depth], # ch1 (ch2 in Verilog)
 [[0]*depth, [0]*depth], # ch2 (ch3 in Verilog)
 ]
 # BRAM registered read output (registered after clock edge)
 self.dout_b0 = [0, 0, 0] # ch0..ch2 bank0 dout
 self.dout_b1 = [0, 0, 0] # ch0..ch2 bank1 dout
 # Registered output mux select
 self.mem_select_r = 0
 # Current inputs (combinational)
 self.mem_select = 0
 self.addr_wr = 0
 self.addr_rd = 0
 self.data_in = 0
 self.we = 0 # 3-bit

 def clock_posedge(self):
 """Simulate one rising clock edge."""
 # Write (all 3 channels simultaneously where WE asserted)
 for ch in range(3):
 we_bit = (self.we >> ch) & 1
 if we_bit:
 if self.mem_select == 0:
 self.ch_banks[ch][0][self.addr_wr] = self.data_in & self.mask
 else:
 self.ch_banks[ch][1][self.addr_wr] = self.data_in & self.mask

 # BRAM registered read (both banks always read addr_rd)
 for ch in range(3):
 self.dout_b0[ch] = self.ch_banks[ch][0][self.addr_rd]
 self.dout_b1[ch] = self.ch_banks[ch][1][self.addr_rd]

 # Registered output mux select
 self.mem_select_r = self.mem_select

 def data_out(self, ch):
 """Output mux: mem_select_r=0->bank1, mem_select_r=1->bank0."""
 if self.mem_select_r:
 return self.dout_b0[ch]
 else:
 return self.dout_b1[ch]


# ---------------------------------------------------------------------------
# Parse vector file and run simulation
# ---------------------------------------------------------------------------
def run:
 if not os.path.exists(VEC_FILE):
 print(f"ERROR: vector file not found: {VEC_FILE}")
 print("Run: python scripts/gen_photo_mem_vectors.py")
 sys.exit(1)

 mem = PhotoMem(DEPTH, DATA_W)
 n_checks = 0
 pass_count = 0
 fail_count = 0
 in_read_phase = False

 print("==============================================")
 print("photo_mem shadow simulator")
 print(f"IMG_W={IMG_W} IMG_H={IMG_H} DEPTH={DEPTH} DATA_W={DATA_W}")
 print("==============================================")

 with open(VEC_FILE) as f:
 for line in f:
 line = line.strip
 if not line or line.startswith("//"):
 continue
 parts = line.split
 if not parts:
 continue

 op = parts[0].upper

 if op == "W" and len(parts) == 5:
 addr = int(parts[1], 16)
 d1 = int(parts[2], 16)
 d2 = int(parts[3], 16)
 d3 = int(parts[4], 16)

 # Write ch1 (we=0b001)
 mem.addr_wr = addr
 mem.data_in = d1
 mem.we = 0b001
 mem.clock_posedge

 # Write ch2 (we=0b010)
 mem.data_in = d2
 mem.we = 0b010
 mem.clock_posedge

 # Write ch3 (we=0b100)
 mem.data_in = d3
 mem.we = 0b100
 mem.clock_posedge

 mem.we = 0
 in_read_phase = False

 elif op == "R" and len(parts) == 5:
 addr = int(parts[1], 16)
 e1 = int(parts[2], 16)
 e2 = int(parts[3], 16)
 e3 = int(parts[4], 16)

 if not in_read_phase:
 # First read: toggle mem_select, set addr_rd, clock once
 mem.mem_select = 1 - mem.mem_select
 mem.addr_rd = addr
 mem.we = 0
 mem.clock_posedge
 in_read_phase = True
 else:
 # Subsequent reads
 mem.addr_rd = addr
 mem.we = 0
 mem.clock_posedge

 got1 = mem.data_out(0)
 got2 = mem.data_out(1)
 got3 = mem.data_out(2)

 n_checks += 1
 if got1 == e1 and got2 == e2 and got3 == e3:
 pass_count += 1
 else:
 fail_count += 1
 if fail_count <= 10:
 print(f"FAIL addr={addr:04X}: got {got1:04X}/{got2:04X}/{got3:04X}"
 f" exp {e1:04X}/{e2:04X}/{e3:04X}")

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
