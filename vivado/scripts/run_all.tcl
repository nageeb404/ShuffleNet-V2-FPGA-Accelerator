# =============================================================================
# run_all.tcl -- Full build: project creation + synth + impl + bitstream
# -----------------------------------------------------------------------------
# Target : XCZU19EG-FFVC1760-2-I (iWave ZU19EG Dev Kit)
# Flow : 1) Source build_project.tcl to create project + block design
# 2) Launch synthesis, implementation, and write_bitstream in sequence
# Usage (from project root):
# vivado -mode batch -source vivado/scripts/run_all.tcl
# -log vivado/work/run_all.log
# -journal vivado/work/run_all.jou
# =============================================================================

set script_dir [file normalize [file dirname [info script]]]

# ---- Step 1: Create project + block design ----
puts "\[INFO\] ============================================================"
puts "\[INFO\] Step 1: Creating Vivado project + block design..."
puts "\[INFO\] ============================================================"
source [file join $script_dir build_project.tcl]

# ---- Step 2: Synthesis ----
puts ""
puts "\[INFO\] ============================================================"
puts "\[INFO\] Step 2: Launching synthesis (PerformanceOptimized)..."
puts "\[INFO\] ============================================================"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]
puts "\[INFO\] Synthesis STATUS=$synth_status PROGRESS=$synth_progress"

if {$synth_progress ne "100%"} {
 puts "ERROR: Synthesis did not reach 100%% -- aborting"
 return -code error "synthesis failed"
}

# Check for critical warnings / errors in synth run
open_run synth_1 -name synth_1
report_timing_summary -no_header -quiet -file [file join $script_dir .. work synth_timing_summary.rpt]
puts "\[INFO\] Synthesis timing summary written to vivado/work/synth_timing_summary.rpt"

# ---- Step 3: Implementation + write_bitstream ----
puts ""
puts "\[INFO\] ============================================================"
puts "\[INFO\] Step 3: Launching implementation + bitstream..."
puts "\[INFO\] Strategy: Performance_ExplorePostRoutePhysOpt"
puts "\[INFO\] ============================================================"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
puts "\[INFO\] Implementation STATUS=$impl_status PROGRESS=$impl_progress"

# ---- Step 4: Final timing report ----
open_run impl_1
report_timing_summary -no_header -quiet \
 -file [file join $script_dir .. work impl_timing_summary.rpt]
report_utilization -quiet \
 -file [file join $script_dir .. work impl_utilization.rpt]

puts ""
puts "\[INFO\] ============================================================"
if {$impl_progress eq "100%"} {
 # Locate bitstream
 set proj_root [file normalize [file join $script_dir .. ..]]
 set bit_candidates [glob -nocomplain \
 [file join $proj_root vivado prj_zu19eg shufflenet_zu19eg.runs impl_1 *.bit]]
 if {[llength $bit_candidates] > 0} {
 puts "\[INFO\] Bitstream: [lindex $bit_candidates 0]"
 }
 puts "\[INFO\] Build COMPLETE."
} else {
 puts "ERROR: Implementation did not reach 100%%"
 puts "\[INFO\] Check vivado/work/impl_timing_summary.rpt for details"
}
puts "\[INFO\] ============================================================"
