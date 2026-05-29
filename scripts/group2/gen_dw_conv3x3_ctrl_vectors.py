"""
gen_dw_conv3x3_ctrl_vectors.py
================================
Generate test vectors for dw_conv3x3_ctrl (Module 2.8).


Simulates dw_conv3x3_ctrl + group2_fifo_ctrl together and records per-cycle:
  start_fifo, en, data_valid, wr_addr, done

Vector format per case:
  Line 1: W H STRIDE  (3 decimal tokens -- same config as fifo_ctrl)
  Per cycle (after start posedge, until done):
    start_fifo en data_valid wr_addr done  (5 decimal tokens)
  Blank line between cases.

The first cycle recorded is AFTER the start posedge:
  - dw_ctrl transitions IDLE -> RUNNING, asserts start_fifo
  - fifo_ctrl IDLE -> LDROW
"""

import os
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT  = os.path.join(SCRIPT_DIR, "..", "..")

# ---- FIFO controller state constants (must match RTL) ----
S_IDLE    = 0
S_LDROW   = 1
S_LDWIN   = 2
S_PROCESS = 3
S_LASTPAD = 4

# ---- DW ctrl state constants ----
DW_IDLE    = 0
DW_RUNNING = 1


def simulate_fifo_ctrl(W, H, STRIDE, PAD=1):
    """Simulate group2_fifo_ctrl, return list of (sl, ps, state, rd, done)
    starting AFTER the start posedge (skipping the initial IDLE record).
    """
    PADDED_W      = W + 2 * PAD
    OUT_H         = (H + 2 * PAD - 3) // STRIDE + 1
    LDROW_LAST    = PADDED_W - 1
    PROC_LAST     = PADDED_W - 4
    NEED_LAST_PAD = 1 if STRIDE == 1 else (1 if H & 1 else 0)

    state = S_IDLE; col_cnt = 0; proc_cnt = 0; row_cnt = 0; rd_ptr = 0
    sl = 0; ps = 0; done_r = 0
    records = []
    started = False

    for _ in range(200000):
        records.append((sl, ps, state, rd_ptr, done_r))
        if done_r:
            break
        done_next = 0; sl_next = sl; ps_next = ps
        if state == S_IDLE:
            sl_next = 0; ps_next = 0
            col_cnt = 0; proc_cnt = 0; row_cnt = 0; rd_ptr = 0
            if not started:
                state = S_LDROW; started = True
        elif state == S_LDROW:
            sl_next = 1
            if col_cnt == 0 or col_cnt == LDROW_LAST:
                ps_next = 1
            else:
                ps_next = 0; rd_ptr += 1
            if col_cnt == LDROW_LAST:
                col_cnt = 0; state = S_LDWIN
            else:
                col_cnt += 1
        elif state == S_LDWIN:
            sl_next = 1
            if col_cnt == 0:
                ps_next = 1
            else:
                ps_next = 0; rd_ptr += 1
            if col_cnt == 2:
                col_cnt = 0; proc_cnt = 0; state = S_PROCESS
            else:
                col_cnt += 1
        elif state == S_PROCESS:
            sl_next = 1
            if proc_cnt == PROC_LAST:
                ps_next = 1
            else:
                ps_next = 0; rd_ptr += 1
            if proc_cnt == PROC_LAST:
                proc_cnt = 0
                if NEED_LAST_PAD:
                    if row_cnt == OUT_H - 2:
                        col_cnt = 0; state = S_LASTPAD
                    else:
                        row_cnt += 1; col_cnt = 0
                        state = S_LDWIN if STRIDE == 1 else S_LDROW
                else:
                    if row_cnt == OUT_H - 1:
                        state = S_IDLE; done_next = 1
                    else:
                        row_cnt += 1; col_cnt = 0; state = S_LDROW
            else:
                proc_cnt += 1
        elif state == S_LASTPAD:
            sl_next = 1; ps_next = 1
            if col_cnt == LDROW_LAST:
                col_cnt = 0; state = S_IDLE; done_next = 1
            else:
                col_cnt += 1
        sl = sl_next; ps = ps_next; done_r = done_next

    return records[1:]  # skip initial IDLE record


def simulate_combined(W, H, STRIDE):
    """Simulate dw_conv3x3_ctrl + group2_fifo_ctrl together.
    Returns list of (start_fifo, en, data_valid, wr_addr, done) per cycle,
    starting from the posedge where start=1 (dw_ctrl IDLE->RUNNING).

    Timing note: start_fifo is a REGISTERED output of dw_conv3x3_ctrl.
    At the start posedge: dw_ctrl transitions IDLE->RUNNING and registers
    start_fifo=1. The fifo_ctrl sees start_fifo=1 only ONE posedge later
    (non-blocking assignment semantics). So:
      result[0]: dw_ctrl=RUNNING, start_fifo=1, fifo_ctrl still IDLE
      result[1]: dw_ctrl=RUNNING, start_fifo=0, fifo_ctrl just entered LDROW
      result[2+]: fifo_ctrl progressing through LDROW/LDWIN/PROCESS...
    """
    fifo_records = simulate_fifo_ctrl(W, H, STRIDE)

    wr = 0
    result = []

    # Cycle 0: start_fifo=1, fifo_ctrl still in IDLE (registered start_fifo
    # hasn't reached fifo_ctrl yet -- it transitions at the NEXT posedge).
    result.append((1, 0, 0, 0, 0))

    # Cycle 1 onwards: fifo_ctrl is active (start_fifo back to 0)
    for sl, ps, fifo_st, rd, done_fifo in fifo_records:
        sf = 0
        en = 1 if fifo_st != S_IDLE and sl else 0
        dv = 1 if fifo_st == S_PROCESS else 0
        wa = wr
        if dv:
            wr += 1

        if done_fifo:
            # When fifo_ctrl asserts done=1 (and sl=1 from LASTPAD/PROCESS),
            # dw_ctrl is still RUNNING -- it processes done_fifo at the NEXT posedge.
            # So there are TWO additional cycles:
            # 1) Transition cycle: fifo_ctrl IDLE(done=1, sl=1), dw_ctrl RUNNING
            #    -> en=1 (RUNNING && sl=1), dn=0
            result.append((0, 1, 0, wr, 0))
            # 2) Done cycle: dw_ctrl sees done_fifo=1 -> state=IDLE, done=1.
            #    fifo_ctrl IDLE applies sl<-0 at this posedge.
            #    -> en=0 (dw_ctrl IDLE now), dn=1
            result.append((0, 0, 0, wr, 1))
            break
        else:
            result.append((sf, en, dv, wa, 0))

    return result


def write_vectors(out_path):
    configs = [
        (7,  7,  1),
        (14, 14, 1),
        (28, 28, 2),
        (56, 56, 2),
    ]

    out_dir = Path(out_path).parent
    out_dir.mkdir(parents=True, exist_ok=True)

    total_cases  = 0
    total_cycles = 0

    with open(out_path, "w") as f:
        f.write("// dw_conv3x3_ctrl test vectors\n")
        f.write("// Format per case:\n")
        f.write("//   Line 1: W H STRIDE\n")
        f.write("//   Per cycle: start_fifo en data_valid wr_addr done\n")

        for (W, H, STRIDE) in configs:
            records = simulate_combined(W, H, STRIDE)
            total_dv  = sum(r[2] for r in records)
            PADDED_W  = W + 2
            OUT_H     = (H + 2 - 3) // STRIDE + 1
            PROC_LAST = PADDED_W - 4

            print(f"W={W:2d} H={H:2d} S={STRIDE}: {len(records):5d} cycles, "
                  f"data_valid_total={total_dv}  "
                  f"(PROC_LAST+1)*(OUT_H)={(PROC_LAST+1)*OUT_H}")

            f.write(f"\n// W={W} H={H} STRIDE={STRIDE} OUT_H={OUT_H}"
                    f" total_dv={total_dv}\n")
            f.write(f"{W} {H} {STRIDE}\n")
            for (sf, en, dv, wa, dn) in records:
                f.write(f"{sf} {en} {dv} {wa} {dn}\n")
            f.write("\n")

            total_cases  += 1
            total_cycles += len(records)

    print(f"\nWritten {total_cases} cases, {total_cycles} total cycles to {out_path}")
    return total_cases


if __name__ == "__main__":
    out_path = os.path.join(PROJ_ROOT, "tb", "group2", "vectors",
                            "dw_conv3x3_ctrl_vectors.hex")
    n = write_vectors(out_path)
    print(f"Done. {n} cases.")
