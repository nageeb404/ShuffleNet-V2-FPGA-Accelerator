# Model 4 (Final) — HLS C-Synthesis Results (achieved, 2026-06-08)

Source: `hls/src/shufflenet_hls_final.cpp`
Project script: `hls/scripts/create_final_project.tcl`
Report: `shufflenet_hls_final/solution_final/syn/report/Shuffle_Model_csynth.rpt`
Target device: **xczu19eg-ffvc1760-1-i** (Zynq UltraScale+ ZU19EG)

> NOTE: the thesis targets Virtex-7 XC7VX690T (not installed in this Vitis HLS
> setup), and Models 2/3 used Kintex-7 xc7k160t. ZU19EG was used for Model 4
> per `create_final_project.tcl`. Resource utilization **percentages** below
> are therefore not directly comparable across models/thesis — only the raw
> cycle counts and the architecture/pragma findings are.

## Achieved synthesis numbers

| Metric | Achieved | Thesis projection (HLS estimate, Sec 7.4.4) |
|---|---|---|
| Clock target | 7.00 ns | 7.00 ns |
| Clock achieved (HLS est.) | **5.106 ns** (~196 MHz), uncertainty 1.89 ns | — |
| Total latency | **21,815,375 cycles** | ~10,932,000 cycles |
| Absolute latency | **0.153 sec/frame** (~6.5 fps, pre-P&R HLS estimate) | — |
| BRAM_18K | 5,075 / 1,968 = **257%** | 80% (on Virtex-7) |
| DSP | 6,636 / 1,968 = **337%** | 54% (on Virtex-7) |
| LUT | 538,711 / 522,720 = **103%** | 46% (on Virtex-7) |
| FF | 280,881 / 1,045,440 = 26% | 11% (on Virtex-7) |
| URAM | 0 / 128 = 0% | — |

**Why our cycle count (21.8M) is ~2x the thesis HLS estimate (~10.9M):**
the thesis's projected UNROLL factors (16/32, full-width on several large loops)
caused the HLS scheduler/binder/RTL-generator to combinatorially explode on
this machine (3 separate hangs/crashes — see below). We reduced those factors
to `factor=4` to make synthesis tractable, which lowers parallel hardware width
and proportionally raises the cycle count. The thesis's lower number reflects
its (untested-by-us) higher-parallelism configuration.

**Why utilization is >100% on 3/5 categories:** this is the raw HLS C-synthesis
*pre-implementation estimate*, not a post-Vivado-place-and-route number. HLS
estimates do not reflect Vivado's resource sharing/binding optimizations —
Model 2's K7 run showed the same pattern (BRAM at 434% of K7 capacity, yet
matched the thesis's Virtex-7 number at 96% vs 99%). It is not evidence the
design "doesn't fit" a real device after Vivado synthesis.

## Per-instance latency breakdown (cycles)

| Instance | Cycles |
|---|---|
| `dataflow_parent_loop_proc2` | 307,217 |
| `max_pool_group1_quad` | 362,986 |
| `shuffle_block_s2_fin` (24→58→116) | 998,043 |
| `shuffle_block_s1_fin` (116) ×2 | 627,470 each |
| `shuffle_block_s2_fin` (116→232) | **8,132,045** (largest single block) |
| `shuffle_block_s1_fin` (232) ×2 | 356,283 each |
| `shuffle_block_s2_fin` (232→464) | 6,647,407 |
| `shuffle_block_s1_fin` (464) ×2 | 178,924 each |
| `conv5_avgpool_final` | 141,553 |
| `fc_classify_final` | 1,017 |

## Three combinatorial-explosion bugs found and fixed to reach this result

All three were instances of the same root cause — `#pragma HLS UNROLL` (full,
no factor limit) on wide loops causing combinatorial explosion in different
HLS compiler phases (scheduling, pipeline scheduling, RTL generation). All
fixed the same way: `#pragma HLS UNROLL` → `#pragma HLS UNROLL factor=4`.
This is a purely structural change — it does not affect computed values,
csim output, or the classification result, only parallel-hardware width /
DSP count / latency.

| # | Location | Symptom | Fix |
|---|---|---|---|
| 1 | `conv1x1_f116_fin`/`conv1x1_f232_fin` (lines ~348,355,377,384) | Scheduler **OOM crash** (4.3+ GB and climbing, log cut off mid-sentence) | `factor=16`/`factor=32` → `factor=4` |
| 2 | Inlined stride-2 PW1 in `shuffle_block_s1_fin`, IN_C==116/232 branches (lines ~574,579,595,600) | **4.5-hour scheduling hang** (0% progress, 100% CPU) on `VITIS_LOOP_569_10_...` — 116/232-wide loops nested in an ~11,368-iteration outer loop | full `UNROLL` → `factor=4` |
| 3 | `conv5_avgpool_final` 1×1 conv, 464→1024 channels (lines ~664,671) | **41-minute RTL-generation hang** on `conv5_avgpool_final_Pipeline_VITIS_LOOP_660_4...` — the single largest unroll width (464) in the entire design | full `UNROLL` → `factor=4` |

## Bottom line

These are the **first-ever real Model 4 (Final) HLS synthesis numbers**
produced for this project (replacing the thesis-projected placeholder table).
They are directly comparable to the thesis only at the "HLS C-synthesis
estimate" stage — not to the thesis's post-Vivado-P&R headline numbers
(24.84 fps, 3.828 W, 0.154 J/frame, "Real RTL latency ~3.2M cycles"), which
require a full Vivado synthesis+implementation (place-and-route) run.

## Why post-P&R ("Real RTL") numbers were not obtained — P&R feasibility test

We attempted the lightest possible step toward P&R: `export_design -flow syn
-rtl verilog -format ip_catalog` (repackages the *already-synthesized* RTL as
a Vivado IP — no synthesis or implementation, should take minutes). It instead
**hung after ~38 minutes**: CPU climbed continuously (+958 CPU-seconds in the
final 16-minute window — more than one full core continuously busy) while
**zero files were written anywhere in the solution directory** for 37+ minutes.
This is the exact same signature (heavy CPU burn, zero forward progress in
logs/files) as the three combinatorial-explosion hangs documented above —
the IP packager choking on the sheer scale of this design. Process killed
(PID 2340) after confirming the stall.

**Conclusion:** if merely *repackaging* the existing synthesis output hangs
after 38 minutes, a full Vivado synthesis+implementation pass — an order of
magnitude heavier, on a design whose HLS estimate already shows 257-337%
over device capacity on 3 of 5 resource categories — is **not practically
feasible** on this setup (hours-long runtime, high OOM risk per the 28GB
crash already seen on the much-smaller Group 3 OOC synthesis). The
HLS-C-synthesis-estimate numbers above are the most complete real results
obtainable for Model 4 here; the thesis's post-P&R figures remain projections.
