"""
gen_conv1x1_ctrl_vectors.py
============================
Generate test vectors for conv1x1_ctrl (Module 2.9).


Per output pixel: N_ACC+1 cycles.
 step 0 : acc_clr=1, en=1 (MAC pipeline settling)
 step 1 : acc_clr=1, en=1
 steps 2..N_ACC-1: acc_clr=0, en=1
 step N_ACC: acc_clr=0, en=1, we=1, wr_addr=pix_cnt (wait/write cycle)

Vector format per case:
 Line 1: W H N_ACC (3 decimal tokens)
 Per cycle (after start posedge, until done): en acc_clr we wr_addr step done
 Blank line between cases.

Timing notes (RTL-accurate):
 - start fires at the start posedge. Result[0] is state AFTER that posedge.
 - The combinational signals (we, wr_addr, step_out) update immediately after
 the step_cnt/pix_cnt registers change.
 - done is a 1-cycle pulse REGISTERED at the last pixel's wait posedge.
 It appears 1 cycle AFTER the last we=1 (since at the we=1 posedge,
 done is also registered but... actually: at the last wait posedge, pix_cnt
 reaches W*H-1, state<-IDLE, done<-1. After this posedge: done=1, we=0,
 en=0. THEN at the next posedge: done<-0 (default).
"""

import os
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")


def simulate_conv1x1_ctrl(W, H, N_ACC, max_cycles=100000):
 """RTL-accurate simulation. Returns list of
 (en, acc_clr, we, wr_addr, step_out, done) per cycle,
 starting AFTER the start posedge."""
 STEP_MAX = N_ACC
 # Register state (values after posedge)
 state = 1 # RUNNING (start just fired)
 step_cnt = 0
 pix_cnt = 0
 en_r = 0
 acc_clr_r = 0
 done_r = 0

 result = []

 for _ in range(max_cycles):
 # Compute combinational outputs from current register state
 we_c = 1 if (state == 1 and step_cnt == STEP_MAX) else 0
 wr_addr_c = pix_cnt
 step_c = step_cnt # raw step_cnt matches RTL assign step_out = step_cnt[2:0]

 result.append((en_r, acc_clr_r, we_c, wr_addr_c, step_c, done_r))

 if done_r:
 break

 # Compute next register values (simulate posedge)
 en_next = en_r
 acc_clr_next = acc_clr_r
 done_next = 0
 state_next = state
 step_next = step_cnt
 pix_next = pix_cnt

 if state == 0: # IDLE
 en_next = 0; acc_clr_next = 0; step_next = 0; pix_next = 0
 else: # RUNNING
 en_next = 1
 acc_clr_next = 1 if (step_cnt == 0 or step_cnt == 1) else 0

 if step_cnt == STEP_MAX:
 # Wait cycle: increment pix, reset step
 step_next = 0
 if pix_cnt == W * H - 1:
 state_next = 0 # IDLE
 pix_next = 0
 done_next = 1
 en_next = 0
 acc_clr_next = 0
 else:
 pix_next = pix_cnt + 1
 else:
 step_next = step_cnt + 1

 en_r = en_next
 acc_clr_r = acc_clr_next
 done_r = done_next
 state = state_next
 step_cnt = step_next
 pix_cnt = pix_next

 return result


def write_vectors(out_path, n_acc=7):
 # Test configs: (W, H) -- small enough to simulate quickly
 configs = [
 (7, 7, n_acc), # 49 pixels x 8 cycles = 392 cycles
 (14, 14, n_acc), # 196 x 8 = 1568 cycles
 (28, 28, n_acc), # 784 x 8 = 6272 cycles
 ]

 out_dir = Path(out_path).parent
 out_dir.mkdir(parents=True, exist_ok=True)

 total_cases = 0
 total_cycles = 0

 with open(out_path, "w") as f:
 f.write("// conv1x1_ctrl test vectors\n")
 f.write("// Format per case:\n")
 f.write("// Line 1: W H N_ACC\n")
 f.write("// Per cycle: en acc_clr we wr_addr step_out done\n")

 for (W, H, N_ACC) in configs:
 records = simulate_conv1x1_ctrl(W, H, N_ACC)
 total_we = sum(r[2] for r in records)

 print(f"W={W:2d} H={H:2d} N_ACC={N_ACC}: {len(records):6d} cycles, "
 f"we_total={total_we} (exp {W*H})")

 f.write(f"\n// W={W} H={H} N_ACC={N_ACC} we_total={total_we}\n")
 f.write(f"{W} {H} {N_ACC}\n")
 for (en, ac, we, wa, st, dn) in records:
 f.write(f"{en} {ac} {we} {wa} {st} {dn}\n")
 f.write("\n")

 total_cases += 1
 total_cycles += len(records)

 print(f"\nWritten {total_cases} cases, {total_cycles} total cycles to {out_path}")
 return total_cases


if __name__ == "__main__":
 out_path = os.path.join(PROJ_ROOT, "tb", "group2", "vectors",
 "conv1x1_ctrl_vectors.hex")
 n = write_vectors(out_path)
 print(f"Done. {n} cases.")
