# create_hls_project.tcl -- Create and run Vitis HLS project for ShuffleNet V2
# Tool: Vitis HLS 2024.2 at N:\Xilinx\Vitis_HLS\2024.2
# Target FPGA: Xilinx Virtex-7 XC7VX690T-2FFG1761C
# Target clock: 100 MHz (10 ns period)
# Usage (run from project root N:\GP\shufflenet_rtl\):
# vitis_hls -f hls/scripts/create_hls_project.tcl
# Or open Vitis HLS GUI and use: File > Open Project, then source this file.
# Steps performed:
# 1. Create/open project
# 2. Add source files
# 3. Set top-level function
# 4. Run C simulation (csim_design)
# 5. Run C synthesis (csynth_design) -- estimates latency & resources
# 6. Export RTL as IP (optional, commented out)

# --- Project setup ---
set project_name "shufflenet_hls"
set project_dir "[pwd]/hls/vivado_project"
set part "xc7k160tfbg676-2" ;# Kintex-7 (closest installed to VC709 Virtex-7)

# Create or open project
open_project -reset $project_name
set_top Shuffle_Model

# --- Add source files ---
# Main implementation
add_files hls/src/shufflenet_hls.cpp \
 -cflags "-I hls/src -I hls/weights"

# --- Add testbench ---
add_files -tb hls/tb/tb_shufflenet.cpp \
 -cflags "-I hls/src -I hls/weights"

# --- Solution setup ---
open_solution "solution_pipeline" -reset
set_part $part
create_clock -period 10 -name default

# --- C Simulation ---
# Verifies functional correctness before synthesis.
puts "\n=== Running C Simulation ===\n"
csim_design -clean

# --- C Synthesis (Pipeline Model) ---
# Synthesises with #pragma HLS PIPELINE directives already in code.
# Expected results:
# Latency: ~237,717,509 clk cycles
# Resources: 99% BRAMs, 0.008% DSPs, 2% LUTs, 0.006% FFs
puts "\n=== Running C Synthesis (Pipeline Model) ===\n"
csynth_design

# --- Print key synthesis results ---
puts "\n=== Synthesis Report Summary ===\n"
# The full report is in:
# hls/vivado_project/shufflenet_hls/solution_pipeline/syn/report/
# Open Shuffle_Model_csynth.rpt for latency and resource estimates.

# --- Optional: RTL Simulation (C/RTL co-simulation) ---
# NOTE: This can take very long (the mentions hours for full model).
# Uncomment to run:
# puts "\n=== Running C/RTL Co-simulation ===\n"
# cosim_design -rtl verilog -trace_level port

# --- Optional: Export RTL as Packaged IP ---
# Uncomment after synthesis is verified:
# export_design -format ip_catalog -output hls/ip_export

puts "\n=== HLS project setup complete ==="
puts "Project location: $project_dir"
puts "Open Vitis HLS GUI and load: $project_name"
puts ""
puts "Next steps:"
puts " 1. Check C simulation output (should show valid class 0-999)"
puts " 2. Review synthesis report for latency and resource estimates"
puts " 3. Compare with RTL implementation results"
