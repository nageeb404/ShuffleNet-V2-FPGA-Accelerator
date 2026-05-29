"""
verify_group1_ctrl_logic.py
============================
Shadow simulator for group1_ctrl (Module 1.12).

Reads the same vector file used by the Verilog TB and verifies all outputs.

"""

import os, sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT = os.path.join(SCRIPT_DIR, "..", "..")
VEC_FILE = os.path.join(PROJ_ROOT, "tb", "group1", "vectors",
 "group1_ctrl_tb_vectors.hex")

S_PROCESS = 3


def expected(fsm_state, col_cnt):
 in_proc = (fsm_state == S_PROCESS)
 en = 1 if in_proc else 0
 acc_clr = 1 if (in_proc and col_cnt <= 1) else 0
 addr = 0 if (col_cnt == 3) else col_cnt
 conv_valid = 1 if (in_proc and col_cnt == 3) else 0
 return en, acc_clr, addr, conv_valid


def next_col_cnt(fsm_state, col_cnt):
 if fsm_state == S_PROCESS:
 return (col_cnt + 1) & 0x3
 return 0


def run:
 if not os.path.exists(VEC_FILE):
 print(f"ERROR: {VEC_FILE} not found")
 print("Run: python scripts/gen_group1_ctrl_vectors.py")
 sys.exit(1)

 n_checks = 0
 pass_count = 0
 fail_count = 0
 col_cnt = 0

 print("==============================================")
 print("group1_ctrl shadow simulator")
 print("==============================================")

 with open(VEC_FILE) as f:
 for line in f:
 line = line.strip
 if not line or line.startswith("//"):
 continue
 parts = line.split
 if len(parts) != 5:
 continue
 fsm = int(parts[0])
 e_en, e_ac, e_ad, e_cv = int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])

 new_col_cnt = next_col_cnt(fsm, col_cnt)
 g_en, g_ac, g_ad, g_cv = expected(fsm, new_col_cnt)
 col_cnt = new_col_cnt

 n_checks += 1
 if g_en == e_en and g_ac == e_ac and g_ad == e_ad and g_cv == e_cv:
 pass_count += 1
 else:
 fail_count += 1
 if fail_count <= 10:
 print(f"FAIL fsm={fsm}: en={g_en}/{e_en} acc_clr={g_ac}/{e_ac} "
 f"addr={g_ad}/{e_ad} conv_valid={g_cv}/{e_cv}")

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
