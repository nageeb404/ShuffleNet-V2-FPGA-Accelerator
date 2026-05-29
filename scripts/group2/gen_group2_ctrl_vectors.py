"""
gen_group2_ctrl_vectors.py
==========================
Generate test vectors for group2_ctrl (Module 2.10).


group2_ctrl sequences 16 Shuffle blocks across 3 stages:
 Stage 2 (loops 0..3): 1 stride-2 block + 3 stride-1 blocks
 Stage 3 (loops 4..11): 1 stride-2 block + 7 stride-1 blocks
 Stage 4 (loops 12..15):1 stride-2 block + 3 stride-1 blocks

start encoding:
 2'b01 -- stride-2 block
 2'b11 -- stride-1 block

Width progression:
 loops=0 (stride-2): width=56, stride=1
 loops=1..3 (stride-1): width=28, stride=0
 loops=4 (stride-2): width=28, stride=1
 loops=5..11 (stride-1): width=14, stride=0
 loops=12 (stride-2): width=14, stride=1
 loops=13..15 (stride-1): width=7, stride=0

Vector format:
 Header line: NLOOPS (=16, total blocks)
 Per cycle: start[1:0] width[5:0] stride fsm_state[1:0] loops[4:0] group2_done
 Blank line at end.

Simulation model:
 We inject done_dw and done_1x1 after a fixed delay (DW_LAT cycles) to
 simulate sub-controller completion. Both arrive simultaneously for simplicity.
 Records start AFTER the start_group posedge.
"""

import os
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")

# FSM state encodings (match RTL localparams)
S_IDLE = 0
S_S2 = 1
S_S3 = 2
S_S4 = 3

LOOPS_S2_END = 4
LOOPS_S3_END = 12
LOOPS_S4_END = 16


def is_stride2(lp):
 return lp in (0, 4, 12)


def block_width(lp):
 """Return (width, stride) for the block starting at loop index lp."""
 if lp == 0:
 return (56, 1)
 elif 1 <= lp <= 3:
 return (28, 0)
 elif lp == 4:
 return (28, 1)
 elif 5 <= lp <= 11:
 return (14, 0)
 elif lp == 12:
 return (14, 1)
 else: # 13..15
 return (7, 0)


def block_start(lp):
 """Return 2-bit start code for block lp."""
 return 1 if is_stride2(lp) else 3 # 2'b01 or 2'b11


def fsm_for_loops(lp):
 """Return FSM state for loop lp."""
 if lp < LOOPS_S2_END:
 return S_S2
 elif lp < LOOPS_S3_END:
 return S_S3
 else:
 return S_S4


def simulate_group2_ctrl(done_latency=3, max_cycles=1000):
 """
 RTL-accurate simulation of group2_ctrl.
 done_latency: number of cycles from start pulse until both done_dw and
 done_1x1 arrive (simulates sub-controller work).
 Returns list of (start[1:0], width[5:0], stride, fsm_state[1:0],
 loops[4:0], group2_done) per cycle,
 starting AFTER the start_group posedge.
 """
 # Register state immediately after start_group posedge:
 # state=S_S2, loops_r=0, start=2'b01, waiting=1, width=56, stride=1
 state = S_S2
 loops_r = 0
 got_dw = 0
 got_1x1 = 0
 waiting = 1
 start_r = 1 # 2'b01, sent at the start_group posedge
 width_r = 56
 stride_r = 1
 done_r = 0

 # Track when to inject done signals
 # done_latency cycles after each start pulse -> both done_dw and done_1x1
 done_countdown = done_latency # starts counting from cycle 0 (after start)
 pending_done = True # we have a block in flight

 result = []
 cycle = 0

 while cycle < max_cycles:
 # Capture outputs this cycle (after the posedge that just happened)
 result.append((start_r, width_r, stride_r, state, loops_r, done_r))

 if done_r:
 break

 # Determine inputs for this cycle (what arrives at posedge+1)
 done_dw_in = 0
 done_1x1_in = 0
 if pending_done:
 done_countdown -= 1
 if done_countdown <= 0:
 done_dw_in = 1
 done_1x1_in = 1
 pending_done = False

 # Simulate the next posedge (RTL sequential logic)
 start_next = 0
 width_next = width_r
 stride_next = stride_r
 state_next = state
 loops_next = loops_r
 got_dw_next = got_dw
 got_1x1_next = got_1x1
 waiting_next = waiting
 done_next = 0

 if state in (S_S2, S_S3, S_S4):
 if done_dw_in: got_dw_next = 1
 if done_1x1_in: got_1x1_next = 1

 both = (got_dw_next or done_dw_in) and (got_1x1_next or done_1x1_in)
 if waiting and both:
 got_dw_next = 0
 got_1x1_next = 0
 new_loops = loops_r + 1
 loops_next = new_loops

 if new_loops == LOOPS_S4_END:
 # All done
 waiting_next = 0
 state_next = S_IDLE
 done_next = 1

 elif new_loops == LOOPS_S2_END:
 state_next = S_S3
 width_next = 28
 stride_next = 1
 start_next = 1 # 2'b01
 waiting_next = 1
 pending_done = True
 done_countdown = done_latency

 elif new_loops == LOOPS_S3_END:
 state_next = S_S4
 width_next = 14
 stride_next = 1
 start_next = 1 # 2'b01
 waiting_next = 1
 pending_done = True
 done_countdown = done_latency

 else:
 # More blocks in current stage
 if is_stride2(new_loops):
 # Should only happen at stage transitions (handled above)
 stride_next = 1
 start_next = 1
 else:
 stride_next = 0
 if new_loops == 1:
 width_next = 28
 elif new_loops == 5:
 width_next = 14
 elif new_loops == 13:
 width_next = 7
 start_next = 3 # 2'b11
 waiting_next = 1
 pending_done = True
 done_countdown = done_latency

 # Advance registers
 start_r = start_next
 width_r = width_next
 stride_r = stride_next
 state = state_next
 loops_r = loops_next
 got_dw = got_dw_next
 got_1x1 = got_1x1_next
 waiting = waiting_next
 done_r = done_next

 cycle += 1

 return result


def write_vectors(out_path):
 # Test with two done_latency values to exercise different interleaving
 configs = [
 ("done_lat=3", 3),
 ("done_lat=1", 1),
 ("done_lat=5", 5),
 ]

 out_dir = Path(out_path).parent
 out_dir.mkdir(parents=True, exist_ok=True)

 total_cases = 0
 total_cycles = 0

 with open(out_path, "w") as f:
 f.write("// group2_ctrl test vectors\n")
 f.write("// Format per case:\n")
 f.write("// Line 1: NLOOPS DONE_LAT\n")
 f.write("// Per cycle: start width stride fsm_state loops group2_done\n")

 for (desc, lat) in configs:
 records = simulate_group2_ctrl(done_latency=lat)
 n_done = sum(1 for r in records if r[5])
 print(f"{desc}: {len(records)} cycles, group2_done pulses={n_done}")

 f.write(f"\n// {desc}\n")
 # Header: NLOOPS DONE_LAT (TB uses DONE_LAT for injection countdown)
 f.write(f"16 {lat}\n")
 for (st, w, s, fsm, lp, gd) in records:
 f.write(f"{st} {w} {s} {fsm} {lp} {gd}\n")
 f.write("\n")

 total_cases += 1
 total_cycles += len(records)

 print(f"\nWritten {total_cases} cases, {total_cycles} total cycles to {out_path}")
 return total_cases


if __name__ == "__main__":
 out_path = os.path.join(PROJ_ROOT, "tb", "group2", "vectors",
 "group2_ctrl_vectors.hex")
 n = write_vectors(out_path)
 print(f"Done. {n} cases.")
