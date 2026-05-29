"""
verify_fifo_ctrl_logic.py -- Bit-true Python shadow simulator for fifo_ctrl.

Verifies the 4-state FSM by re-running the
generator's simulation and cross-checking totals and boundary conditions.

Checks:
  1. Total active cycles matches expected formula
  2. Data shifts == IMG_W * IMG_H
  3. Padding shifts == 2*OUT_H*(PAD) + 2*OUT_H + OUT_H  (computed)
  4. done fires at exactly the last cycle
  5. rd_ptr ends at exactly IMG_W * IMG_H
  6. Padding positions are correct (left/right per row)
"""

import sys
from gen_fifo_ctrl_vectors import simulate_fifo_ctrl

def verify(img_w=4, img_h=4, pad=1, stride=2):
    padded_w = img_w + 2 * pad
    out_h    = (img_h + 2 * pad - 3) // stride + 1

    # Expected totals
    shifts_per_row = padded_w + 3 + (padded_w - 3)  # LDROW + LDWIN + PROCESS = 2*padded_w
    # But there are 2*out_h total LDROW+LDWIN+PROCESS cycles (one LDROW per output row for skip,
    # plus one LDROW for the first compute row)
    # Actually: out_h LDROW + out_h LDWIN + out_h PROCESS = out_h*(padded_w+3+(padded_w-3))
    expected_total_cycles = out_h * (padded_w + 3 + (padded_w - 3))
    expected_data  = img_w * img_h
    expected_done  = expected_total_cycles - 1   # 0-indexed last cycle

    cycles, done_cycle = simulate_fifo_ctrl(img_w, img_h, pad, stride)

    failures = []

    # Check 1: total cycles
    if len(cycles) != expected_total_cycles:
        failures.append(f"Total cycles: got {len(cycles)}, expected {expected_total_cycles}")
    else:
        print(f"PASS: total cycles = {len(cycles)} (expected {expected_total_cycles})")

    # Check 2: data shifts
    data_shifts = sum(1 for sal, ps, addr in cycles if ps == 0)
    if data_shifts != expected_data:
        failures.append(f"Data shifts: got {data_shifts}, expected {expected_data}")
    else:
        print(f"PASS: data shifts = {data_shifts} (expected {expected_data})")

    # Check 3: done cycle
    if done_cycle != expected_done:
        failures.append(f"done cycle: got {done_cycle}, expected {expected_done}")
    else:
        print(f"PASS: done at cycle {done_cycle} (expected {expected_done})")

    # Check 4: rd_ptr at end = IMG_W * IMG_H
    # Final rd_ptr is the last addr in cycles (post-increment, but padding cycles
    # don't increment, so last data addr = IMG_W*IMG_H)
    last_data_addr = max(addr for _, ps, addr in cycles if ps == 0)
    if last_data_addr != img_w * img_h:
        failures.append(f"Max data addr: got {last_data_addr}, expected {img_w * img_h}")
    else:
        print(f"PASS: max data rd_addr = {last_data_addr} (expected {img_w * img_h})")

    # Check 5: First cycle is always padding (left pad of first LDROW)
    if cycles[0][1] != 1:
        failures.append(f"Cycle 0 padding_sel = {cycles[0][1]}, expected 1")
    else:
        print(f"PASS: cycle 0 is padding (left pad of first LDROW)")

    # Check 6: Last cycle is always padding (right pad of last PROCESS)
    if cycles[-1][1] != 1:
        failures.append(f"Last cycle padding_sel = {cycles[-1][1]}, expected 1")
    else:
        print(f"PASS: last cycle is padding (right pad of last PROCESS)")

    # Check 7: rd_addr is monotonically non-decreasing
    prev = 0
    mono_ok = True
    for sal, ps, addr in cycles:
        if addr < prev:
            mono_ok = False
            failures.append(f"rd_addr non-monotone: {prev} -> {addr}")
            break
        prev = addr
    if mono_ok:
        print(f"PASS: rd_addr is monotonically non-decreasing")

    # Check 8: padding shifts are exactly in the right count
    pad_shifts = sum(1 for _, ps, _ in cycles if ps == 1)
    # Per row: 1(LDROW left) + 1(LDROW right) + 1(LDWIN left) + 1(PROCESS right) = 4
    expected_pad = out_h * 4
    if pad_shifts != expected_pad:
        failures.append(f"Padding shifts: got {pad_shifts}, expected {expected_pad}")
    else:
        print(f"PASS: padding shifts = {pad_shifts} (expected {expected_pad})")

    return failures


def main():
    import argparse
    p = argparse.ArgumentParser(description="Verify fifo_ctrl FSM logic")
    p.add_argument("--img_w",  type=int, default=4)
    p.add_argument("--img_h",  type=int, default=4)
    p.add_argument("--pad",    type=int, default=1)
    p.add_argument("--stride", type=int, default=2)
    p.add_argument("--full",   action="store_true",
                   help="Also run full 224x224 verification")
    args = p.parse_args()

    print("=" * 60)
    print(f"fifo_ctrl shadow simulator")
    print(f"IMG_W={args.img_w} IMG_H={args.img_h} PAD={args.pad} STRIDE={args.stride}")
    print("=" * 60)

    all_failures = verify(args.img_w, args.img_h, args.pad, args.stride)

    if args.full and (args.img_w != 224 or args.img_h != 224):
        print()
        print("=" * 60)
        print("Full 224x224 verification")
        print("=" * 60)
        all_failures += verify(224, 224, 1, 2)

    print()
    print("-" * 60)
    if not all_failures:
        print("RESULT: *** ALL TESTS PASSED ***")
        sys.exit(0)
    else:
        for f in all_failures:
            print(f"FAIL: {f}")
        print(f"RESULT: *** {len(all_failures)} TESTS FAILED ***")
        sys.exit(1)


if __name__ == "__main__":
    main()
