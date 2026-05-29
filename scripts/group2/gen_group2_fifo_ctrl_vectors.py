"""
gen_group2_fifo_ctrl_vectors.py
================================
Generate test vectors for group2_fifo_ctrl (Module 2.7).


Simulates the FSM output sequence and verifies:
 - shift_and_load, padding_sel assertions per state
 - rd_ptr advance count (must equal W*H data reads total)
 - done pulse at end
 - fsm_state transitions

Vector format per case:
 Line 1: W H STRIDE (3 decimal tokens)
 One line per clock cycle until done:
 cycle shift_and_load padding_sel fsm_state rd_ptr done (6 decimal tokens)
 Blank line between cases.
"""

import os
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")

S_IDLE = 0
S_LDROW = 1
S_LDWIN = 2
S_PROCESS = 3
S_LASTPAD = 4


def simulate_ctrl(W, H, STRIDE, PAD=1, max_cycles=100000):
 """Simulate group2_fifo_ctrl and return list of (sl, ps, fsm_state, rd_ptr, done)."""
 PADDED_W = W + 2 * PAD
 OUT_H = (H + 2 * PAD - 3) // STRIDE + 1
 LDROW_LAST = PADDED_W - 1
 PROC_LAST = PADDED_W - 4
 NEED_LAST_PAD = 1 if (STRIDE == 1) else (1 if (H & 1) else 0)

 state = S_IDLE
 col_cnt = 0
 proc_cnt = 0
 row_cnt = 0
 rd_ptr = 0
 sl = 0
 ps = 0
 done_r = 0

 records = []
 started = False

 for cyc in range(max_cycles):
 # Record current outputs (combinational from registered state)
 records.append((sl, ps, state, rd_ptr, done_r))
 if done_r:
 break

 # Advance one clock (combinational outputs computed above, now update registers)
 done_next = 0
 sl_next = sl
 ps_next = ps

 if state == S_IDLE:
 sl_next = 0
 ps_next = 0
 col_cnt = 0
 proc_cnt = 0
 row_cnt = 0
 rd_ptr = 0
 if not started:
 # start signal arrives at cycle 0
 state = S_LDROW
 started = True

 elif state == S_LDROW:
 sl_next = 1
 if col_cnt == 0 or col_cnt == LDROW_LAST:
 ps_next = 1
 else:
 ps_next = 0
 rd_ptr += 1
 if col_cnt == LDROW_LAST:
 col_cnt = 0
 state = S_LDWIN
 else:
 col_cnt += 1

 elif state == S_LDWIN:
 sl_next = 1
 if col_cnt == 0:
 ps_next = 1
 else:
 ps_next = 0
 rd_ptr += 1
 if col_cnt == 2:
 col_cnt = 0
 proc_cnt = 0
 state = S_PROCESS
 else:
 col_cnt += 1

 elif state == S_PROCESS:
 sl_next = 1
 if proc_cnt == PROC_LAST:
 ps_next = 1
 else:
 ps_next = 0
 rd_ptr += 1
 if proc_cnt == PROC_LAST:
 proc_cnt = 0
 if NEED_LAST_PAD:
 if row_cnt == OUT_H - 2:
 col_cnt = 0
 state = S_LASTPAD
 else:
 row_cnt += 1
 col_cnt = 0
 state = S_LDWIN if STRIDE == 1 else S_LDROW
 else:
 if row_cnt == OUT_H - 1:
 state = S_IDLE
 done_next = 1
 else:
 row_cnt += 1
 col_cnt = 0
 state = S_LDROW # stride-2 only when !NEED_LAST_PAD
 else:
 proc_cnt += 1

 elif state == S_LASTPAD:
 sl_next = 1
 ps_next = 1
 if col_cnt == LDROW_LAST:
 col_cnt = 0
 state = S_IDLE
 done_next = 1
 else:
 col_cnt += 1

 sl = sl_next
 ps = ps_next
 done_r = done_next

 return records


def write_vectors(out_path):
 # Test configurations: (W, H, STRIDE)
 # Matching actual ShuffleNet V2 Group 2 usage:
 # stride-1 blocks: W=H=28, 14, 7 (all NEED_LAST_PAD=1)
 # stride-2 blocks: W=H=56, 28, 14 (all even H, NEED_LAST_PAD=0)
 configs = [
 (7, 7, 1), # stride-1, smallest block
 (14, 14, 1), # stride-1
 (28, 28, 1), # stride-1
 (14, 14, 2), # stride-2, W=14 (even H, NEED_LAST_PAD=0)
 (28, 28, 2), # stride-2, W=28
 (56, 56, 2), # stride-2, W=56 (max size)
 ]

 out_dir = Path(out_path).parent
 out_dir.mkdir(parents=True, exist_ok=True)

 total_cases = 0
 total_cycles = 0

 with open(out_path, "w") as f:
 f.write("// group2_fifo_ctrl test vectors\n")
 f.write("// Format per case:\n")
 f.write("// Line 1: W H STRIDE\n")
 f.write("// Per cycle: shift_load padding_sel fsm_state rd_ptr done\n")

 for (W, H, STRIDE) in configs:
 records = simulate_ctrl(W, H, STRIDE)
 # Skip the initial IDLE record; testbench starts checking after
 # the start posedge when the FSM has already entered LDROW.
 records = records[1:]
 PADDED_W = W + 2
 OUT_H = (H + 2 - 3) // STRIDE + 1
 exp_reads = W * H # total feature map data reads

 # Verify rd_ptr at end
 final_rd = records[-1][3]
 if final_rd != exp_reads:
 print(f"WARNING W={W} H={H} S={STRIDE}: "
 f"final rd_ptr={final_rd} expected={exp_reads}")

 f.write(f"\n// W={W} H={H} STRIDE={STRIDE} "
 f"OUT_H={OUT_H} cycles={len(records)}\n")
 f.write(f"{W} {H} {STRIDE}\n")
 for (sl, ps, st, rp, dn) in records:
 f.write(f"{sl} {ps} {st} {rp} {dn}\n")
 f.write("\n")

 total_cases += 1
 total_cycles += len(records)
 print(f"W={W:2d} H={H:2d} S={STRIDE}: {len(records):5d} cycles, "
 f"rd_ptr_final={records[-1][3]} (exp {exp_reads})")

 print(f"\nWritten {total_cases} cases, {total_cycles} total cycles to {out_path}")
 return total_cases


if __name__ == "__main__":
 out_path = os.path.join(PROJ_ROOT, "tb", "group2", "vectors",
 "group2_fifo_ctrl_vectors.hex")
 n = write_vectors(out_path)
 print(f"Done. {n} cases.")
