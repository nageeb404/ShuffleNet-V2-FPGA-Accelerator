# run_csynth.tcl -- Run C Synthesis (Pipeline Model) for ShuffleNet V2 HLS
# Latency : ~237,717,509 clk cycles
# BRAMs : 99%
# DSPs : 0.008%
# LUTs : 2%
# FFs : 0.006%
# Usage (from project root N:\GP\shufflenet_rtl):
# vitis_hls -f hls/scripts/run_csynth.tcl
# Report written to:
# shufflenet_hls/solution_pipeline/syn/report/Shuffle_Model_csynth.rpt

open_project shufflenet_hls
set_top Shuffle_Model

add_files hls/src/shufflenet_hls.cpp \
 -cflags "-I hls/src -I hls/weights"

open_solution "solution_pipeline"
set_part xc7k160tfbg676-2
create_clock -period 10 -name default

puts "\n=== C Synthesis (Pipeline Model) ==="
puts "Target: xc7k160tfbg676-2, 100 MHz"
puts "Expected latency: ~237,717,509 cycles\n"

csynth_design

puts "\n=== Synthesis complete ==="
puts "Report: shufflenet_hls/solution_pipeline/syn/report/Shuffle_Model_csynth.rpt"
