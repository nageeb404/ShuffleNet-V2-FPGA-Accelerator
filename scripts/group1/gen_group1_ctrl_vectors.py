"""
gen_group1_ctrl_vectors.py
==========================
Generates testbench vectors for group1_ctrl (Module 1.12).

The testbench simulates the following sequence:
 - IDLE (a few cycles)
 - Start received
 - LDROW state (a few cycles -- col_cnt should stay 0)
 - LDWIN state (a few cycles -- col_cnt should stay 0)
 - PROCESS state (16 cycles = 4 output pixels x 4 clocks each)
 - IDLE again

Vector format: one line per clock
 fsm_state exp_en exp_acc_clr exp_addr exp_conv_valid

fsm_state: 0=IDLE, 1=LDROW, 2=LDWIN, 3=PROCESS
All output fields are 1-bit except addr (2-bit).

"""

import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")
VEC_OUT = os.path.join(PROJ_ROOT, "tb", "group1", "vectors",
 "group1_ctrl_tb_vectors.hex")

S_IDLE = 0
S_LDROW = 1
S_LDWIN = 2
S_PROCESS = 3

# Simulate group1_ctrl logic in Python
def expected(fsm_state, col_cnt):
 in_process = (fsm_state == S_PROCESS)
 en = 1 if in_process else 0
 acc_clr = 1 if (in_process and col_cnt <= 1) else 0
 addr = 0 if (col_cnt == 3) else col_cnt
 conv_valid = 1 if (in_process and col_cnt == 3) else 0
 return en, acc_clr, addr, conv_valid

# Simulate col_cnt counter
def next_col_cnt(fsm_state, col_cnt):
 if fsm_state == S_PROCESS:
 return (col_cnt + 1) & 0x3 # 2-bit wrapping
 return 0

# Build the sequence
sequence = []
# a few IDLE cycles
for _ in range(3):
 sequence.append(S_IDLE)
# LDROW
for _ in range(5):
 sequence.append(S_LDROW)
# LDWIN
for _ in range(3):
 sequence.append(S_LDWIN)
# PROCESS (4 pixels x 4 cycles = 16)
for _ in range(16):
 sequence.append(S_PROCESS)
# IDLE again
for _ in range(2):
 sequence.append(S_IDLE)

# Generate expected outputs
lines = []
lines.append("// group1_ctrl testbench vectors")
lines.append("// / Figure 5.4")
lines.append("// Format: fsm_state exp_en exp_acc_clr exp_addr exp_conv_valid")

col_cnt = 0
for fsm in sequence:
 # At posedge: col_cnt advances based on current fsm and col_cnt.
 # TB checks outputs AFTER posedge, so expected = f(fsm, new_col_cnt).
 new_col_cnt = next_col_cnt(fsm, col_cnt)
 en, acc_clr, addr, conv_valid = expected(fsm, new_col_cnt)
 lines.append(f"{fsm} {en} {acc_clr} {addr} {conv_valid}")
 col_cnt = new_col_cnt

os.makedirs(os.path.dirname(VEC_OUT), exist_ok=True)
with open(VEC_OUT, "w") as f:
 f.write("\n".join(lines) + "\n")

n_checks = len(sequence)
print(f"Written {n_checks} vector lines to {VEC_OUT}")
print("Done.")
