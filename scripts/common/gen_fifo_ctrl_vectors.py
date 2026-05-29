"""
gen_fifo_ctrl_vectors.py -- Generate expected control signal sequence for fifo_ctrl.

Simulates the 4-state FSM in Python and writes
the expected (shift_and_load, padding_sel, rd_addr) for every active clock cycle
to a hex vector file.

Vector file format (one line per active clock cycle, tab-separated):
 shift_and_load padding_sel rd_addr_hex
 1 1 0000
 1 0 0000
 ...

A separate "done_cycle" value is appended at the end (# comment line).

Usage:
 python3 scripts/gen_fifo_ctrl_vectors.py [--img_w W] [--img_h H] [--out PATH]
"""

import sys
import os
import argparse

def simulate_fifo_ctrl(img_w, img_h, pad=1, stride=2):
 """
 Returns list of (shift_and_load, padding_sel, rd_addr) tuples for each
 clock cycle from start=1 until done=1 (inclusive of the done cycle).
 Also returns the index (0-based) of the cycle where done=1.
 """
 padded_w = img_w + 2 * pad
 out_h = (img_h + 2 * pad - 3) // stride + 1
 proc_last = padded_w - 4 # = padded_w - 3 - 1

 IDLE = 0
 LDROW = 1
 LDWIN = 2
 PROCESS = 3

 state = LDROW # after start, immediately in LOAD_ROW
 col_cnt = 0
 proc_cnt = 0
 row_cnt = 0
 rd_ptr = 0

 cycles = []
 done_cycle = None

 for step in range(1_000_000): # safety limit
 sal = 1 # shift_and_load (always 1 outside IDLE)
 pad_sel = 0
 addr = rd_ptr # combinational: rd_addr = rd_ptr

 if state == LDROW:
 # padding at col 0 and last col (PADDED_W-1)
 if col_cnt == 0 or col_cnt == (padded_w - 1):
 pad_sel = 1
 else:
 pad_sel = 0

 # rd_ptr update BEFORE append so stored addr = post-increment value,
 # matching what testbench sees at @(posedge clk);#1 after NBAs fire.
 if 1 <= col_cnt <= img_w:
 rd_ptr += 1

 cycles.append((sal, pad_sel, rd_ptr))

 # counter/transition
 if col_cnt == padded_w - 1:
 col_cnt = 0
 state = LDWIN
 else:
 col_cnt += 1

 elif state == LDWIN:
 if col_cnt == 0:
 pad_sel = 1
 else:
 pad_sel = 0
 rd_ptr += 1 # advance for data positions 1,2

 cycles.append((sal, pad_sel, rd_ptr))

 if col_cnt == 2: # LDWIN_LAST = 2
 col_cnt = 0
 proc_cnt = 0
 state = PROCESS
 else:
 col_cnt += 1

 elif state == PROCESS:
 if proc_cnt == proc_last:
 pad_sel = 1
 else:
 pad_sel = 0
 rd_ptr += 1

 cycles.append((sal, pad_sel, rd_ptr))

 if proc_cnt == proc_last:
 proc_cnt = 0
 if row_cnt == out_h - 1:
 # done
 done_cycle = len(cycles) - 1
 break
 else:
 row_cnt += 1
 col_cnt = 0
 state = LDROW
 else:
 proc_cnt += 1

 return cycles, done_cycle


def main:
 p = argparse.ArgumentParser(description="Generate fifo_ctrl golden vectors")
 p.add_argument("--img_w", type=int, default=4, help="Unpadded image width")
 p.add_argument("--img_h", type=int, default=4, help="Unpadded image height")
 p.add_argument("--pad", type=int, default=1, help="Zero-padding per side")
 p.add_argument("--stride",type=int, default=2, help="Row skip stride")
 p.add_argument("--out", type=str, default=None, help="Output vector file path")
 args = p.parse_args

 if args.out is None:
 # Default location matching testbench convention
 script_dir = os.path.dirname(os.path.abspath(__file__))
 proj_root = os.path.dirname(os.path.dirname(script_dir))
 args.out = os.path.join(proj_root, "tb", "common", "vectors",
 "fifo_ctrl_vectors.hex")

 os.makedirs(os.path.dirname(args.out), exist_ok=True)

 cycles, done_cycle = simulate_fifo_ctrl(
 args.img_w, args.img_h, args.pad, args.stride)

 padded_w = args.img_w + 2 * args.pad
 out_h = (args.img_h + 2 * args.pad - 3) // args.stride + 1
 proc_last = padded_w - 4

 # Expected counts
 total_cycles = len(cycles)
 total_shifts = sum(s for s, _, _ in cycles) # all 1 outside IDLE
 total_pad = sum(ps for _, ps, _ in cycles)
 total_data = total_shifts - total_pad
 expected_data = args.img_w * args.img_h # = IMG_W * IMG_H

 print(f"fifo_ctrl vector generator")
 print(f" IMG_W={args.img_w} IMG_H={args.img_h} PAD={args.pad} "
 f"STRIDE={args.stride}")
 print(f" PADDED_W={padded_w} OUT_H={out_h} PROC_LAST={proc_last}")
 print(f" Total active cycles : {total_cycles}")
 print(f" Total shift pulses : {total_shifts}")
 print(f" Padding shifts : {total_pad}")
 print(f" Data shifts : {total_data} (expected {expected_data})")
 print(f" done at cycle index : {done_cycle}")

 if total_data != expected_data:
 print(f"ERROR: data shift count mismatch! got {total_data}, "
 f"expected {expected_data}")
 sys.exit(1)

 with open(args.out, "w") as f:
 f.write(f"# fifo_ctrl vectors: img_w={args.img_w} img_h={args.img_h} "
 f"pad={args.pad} stride={args.stride}\n")
 f.write(f"# total_cycles={total_cycles} done_cycle={done_cycle}\n")
 f.write(f"# format: shift_and_load padding_sel rd_addr(4-hex-digits)\n")
 for sal, ps, addr in cycles:
 f.write(f"{sal} {ps} {addr:04X}\n")

 print(f" Written {total_cycles} vectors to {args.out}")


if __name__ == "__main__":
 main
