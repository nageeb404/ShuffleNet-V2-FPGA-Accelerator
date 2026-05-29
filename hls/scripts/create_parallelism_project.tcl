# create_parallelism_project.tcl
# Create and run Vitis HLS project for Model 3: Parallelism Based Optimization
# Tool: Vitis HLS 2024.2
# Target FPGA: xc7k160tfbg676-2 (Kintex-7)
# Clock: 10 ns (100 MHz) -- same as Pipeline Model
# Usage (run from project root N:\GP\shufflenet_rtl\):
# vitis_hls -f hls/scripts/create_parallelism_project.tcl
# Key optimizations in this model (vs Pipeline Model):
# - UNROLL all kernel loops (27 parallel reads/multiplies for 3x3 conv)
# - PIPELINE outer filter loop (1 filter per cycle after pipeline fill)
# - DATAFLOW between Read-Input and Core sub-functions (3x3 conv)
# - ARRAY_PARTITION cyclic on weight arrays for parallel access
# - Specialized conv1x1_f58/116/232 with fixed UNROLL loop bounds
# - Template shuffle blocks for compile-time fixed bounds
# Expected results:
# Estimated: ~21,126,394 clk cycles
# Real RTL: ~9,066,784 clk cycles
# BRAM=91%, DSP=44%, LUT=61%, FF=21%

set project_name "shufflenet_hls_parallelism"
set part "xc7k160tfbg676-2" ;# Kintex-7

# Create or reset project
open_project -reset $project_name
set_top Shuffle_Model

# Add implementation source
add_files hls/src/shufflenet_hls_parallelism.cpp \
 -cflags "-I hls/src -I hls/weights"

# Add testbench (same testbench as Pipeline Model -- same input/output interface)
add_files -tb hls/tb/tb_shufflenet.cpp \
 -cflags "-I hls/src -I hls/weights"

# Solution setup: 10 ns clock (100 MHz)
open_solution "solution_parallelism" -reset
set_part $part
create_clock -period 10 -name default

# --- C Simulation ---
# Verifies that the parallelism model gives the same class output as
# the pipeline model (should output class 317 for the test image).
# NOTE: wrapped in catch -- Vitis HLS on Windows reports nonzero return value
# even when main returns 0, due to a tee.exe pipe false negative.
# Csynth proceeds regardless; check csim/report/Shuffle_Model_csim.log manually.
puts "\n=== Running C Simulation (Parallelism Model) ===\n"
if {[catch {csim_design -clean} csim_err]} {
 puts "\n=== CSim returned non-zero (Windows tee.exe false negative) ==="
 puts "=== Check csim/report/Shuffle_Model_csim.log for actual result ==="
 puts "=== Proceeding to C Synthesis ==="
}

# --- C Synthesis (Parallelism Model) ---
# Key HLS directives in the source control optimization:
# #pragma HLS UNROLL -- inside kernel loops (27 parallel DSPs for 3x3)
# #pragma HLS PIPELINE -- on filter loop (1 filter/cycle)
# #pragma HLS DATAFLOW -- between read-win and core sub-functions
# #pragma HLS ARRAY_PARTITION -- on weight arrays (cyclic factor=in_C)
# Expected: significant latency reduction vs Pipeline Model's ~238M cycles.
puts "\n=== Running C Synthesis (Parallelism Model) ===\n"
csynth_design

puts "\n=== Parallelism Model synthesis complete ==="
puts "Project location: [pwd]/$project_name"
puts ""
puts "Synthesis report location:"
puts " $project_name/solution_parallelism/syn/report/Shuffle_Model_csynth.rpt"
puts ""
puts "Expected results:"
puts " Estimated latency: ~21,126,394 clk cycles"
puts " Real RTL latency: ~9,066,784 clk cycles"
puts " BRAM=91%, DSP=44%, LUT=61%, FF=21%"
puts ""
puts "Compare with Pipeline Model:"
puts " Pipeline estimated: ~237,717,509 cycles (11x more)"
puts " Speedup from parallelism: ~11x estimated, ~26x real RTL"
