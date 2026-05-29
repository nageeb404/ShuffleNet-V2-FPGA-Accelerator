# run_synthesis.tcl -- Create project and run RTL synthesis for accelerator_top
# After synthesis completes, utilization report is written to:
# vivado/proj_shufflenet/shufflenet_rtl.runs/synth_1/
# build/rtl_synth_utilization.rpt
# build/rtl_synth_timing.rpt
# Usage (from project root N:\GP\shufflenet_rtl):
# vivado -mode batch -source vivado/scripts/run_synthesis.tcl 2>&1 | tee build/rtl_synth.log

# Step 1: create the project (adds all RTL files, sets top = accelerator_top)
source vivado/scripts/build_project.tcl

# Step 2: synthesise
puts "\n\[INFO\] ============================================"
puts "\[INFO\] Running RTL synthesis -- accelerator_top"
puts "\[INFO\] Target: [get_property part [current_project]]"
puts "\[INFO\] ============================================\n"

launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check result
set synth_status [get_property STATUS [get_runs synth_1]]
puts "\[INFO\] Synthesis status: $synth_status"

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
 puts "ERROR: Synthesis did not complete."
 return -code error "synthesis failed"
}

# Step 3: open synthesised design and write reports
open_run synth_1 -name synth_1

set build_dir [file join [file normalize [info script]] .. .. .. build]
set build_dir [file normalize $build_dir]

puts "\[INFO\] Writing reports to $build_dir"

report_utilization -file [file join $build_dir rtl_synth_utilization.rpt]
report_timing_summary -file [file join $build_dir rtl_synth_timing.rpt] -max_paths 10

puts "\n\[INFO\] ============================================"
puts "\[INFO\] Synthesis COMPLETE"
puts "\[INFO\] Utilization : build/rtl_synth_utilization.rpt"
puts "\[INFO\] Timing est. : build/rtl_synth_timing.rpt"
puts "\[INFO\] ============================================"
puts ""
puts "Expected (after optimizations, Virtex-7):"
puts " BRAM: 1098 / 1470 = 75%"
puts " DSP : 2885 / 3600 = 80%"
puts " LUT : 108638 / 433200 = 25%"
puts " FF : 106736 / 866400 = 12%"
