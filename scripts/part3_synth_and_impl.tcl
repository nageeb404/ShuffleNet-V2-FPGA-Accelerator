# =============================================================================
# part3_synth_and_impl.tcl -- Project synthesis (light) + fill black boxes + P&R
#
# Prerequisites:
#   1. build_project.tcl has been run once (project exists with stubs)
#   2. vivado/dcp/group2_top.dcp exists (from part1)
#   3. vivado/dcp/group3_top.dcp exists (from part2)
#
# Run from project root:
#   vivado.bat -mode batch -source vivado/work/part3_synth_and_impl.tcl \
#              -log vivado/work/log_synth_impl.log -journal vivado/work/log_synth_impl.jou
# =============================================================================

set script_dir [file normalize [file dirname [info script]]]
set proj_root  [file normalize [file join $script_dir .. ..]]
set dcp_dir    [file join $proj_root vivado dcp]
set proj_file  [file join $proj_root vivado prj_zu19eg shufflenet_zu19eg.xpr]
set rpt_dir    [file join $proj_root vivado reports]

file mkdir $rpt_dir

# ---- Sanity checks ----
foreach {label f} [list \
    "Project"       $proj_file \
    "group1 DCP"    [file join $dcp_dir group1_top.dcp] \
    "group2 DCP"    [file join $dcp_dir group2_top.dcp] \
    "group3 DCP"    [file join $dcp_dir group3_top.dcp] \
] {
    if {![file exists $f]} {
        puts "ERROR: $label not found: $f"
        return -code error "prerequisite missing"
    }
}

puts "\[SYNTH\] Opening project: $proj_file"
open_project $proj_file

# ---- Synthesis (group2/group3 are black-box stubs -- very light) ----
puts "\[SYNTH\] Resetting and launching synth_1 (group1/2/3 are black boxes)..."
reset_run synth_1

# CRITICAL: set flatten_hierarchy=none on the OOC sub-run for our module.
# With flatten_hierarchy=rebuilt (the default), empty black-box stub modules
# have no internal primitives to rebuild and are silently removed from the
# post-synthesis netlist. With none, all hierarchy boundaries -- including
# empty black boxes -- are preserved exactly as written.
set ooc_run [get_runs -quiet system_shufflenet_board_top_0_0_synth_1]
if {[llength $ooc_run] > 0} {
    set_property -name {steps.synth_design.args.flatten_hierarchy} \
        -value {none} -objects $ooc_run
    puts "\[SYNTH\] OOC run flatten_hierarchy forced to 'none' (preserves black box cells)"
} else {
    puts "WARNING: OOC run not found -- black box cells may be lost after synthesis"
}

launch_runs synth_1 -jobs 1
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "ERROR: synth_1 failed. Check the synthesis log."
    return -code error "synthesis failed"
}
puts "\[SYNTH\] synth_1 complete."

# ---- Open synthesis result ----
open_run synth_1 -name synth_1

# ---- Fill black boxes with pre-synthesized DCPs ----
# Vivado OOC synthesis prepends the OOC wrapper name to black-box cell refs,
# e.g. group1_top becomes system_shufflenet_board_top_0_0_group1_top.
# Use wildcard =~ match so we find them regardless of prefix.
set g1_cells [get_cells -hierarchical -filter {REF_NAME =~ *group1_top*}]
set g2_cells [get_cells -hierarchical -filter {REF_NAME =~ *group2_top*}]
set g3_cells [get_cells -hierarchical -filter {REF_NAME =~ *group3_top*}]

if {[llength $g1_cells] == 0} { puts "ERROR: group1_top cell not found in netlist!"; return -code error }
if {[llength $g2_cells] == 0} { puts "ERROR: group2_top cell not found in netlist!"; return -code error }
if {[llength $g3_cells] == 0} { puts "ERROR: group3_top cell not found in netlist!"; return -code error }

# Extract cell paths as plain Tcl strings NOW, before any read_checkpoint -cell call.
# After read_checkpoint -cell, all Vivado design object handles become invalid
# (Vivado warning 12-12435). Plain strings (from get_property NAME) survive.
set g1_path [get_property NAME [lindex $g1_cells 0]]
set g2_path [get_property NAME [lindex $g2_cells 0]]
set g3_path [get_property NAME [lindex $g3_cells 0]]

puts "\[IMPL\] group1_top path: $g1_path"
puts "\[IMPL\] group2_top path: $g2_path"
puts "\[IMPL\] group3_top path: $g3_path"

puts "\[IMPL\] Reading group1_top DCP..."
read_checkpoint -cell $g1_path [file join $dcp_dir group1_top.dcp]

puts "\[IMPL\] Reading group2_top DCP..."
read_checkpoint -cell $g2_path [file join $dcp_dir group2_top.dcp]

puts "\[IMPL\] Reading group3_top DCP..."
read_checkpoint -cell $g3_path [file join $dcp_dir group3_top.dcp]

puts "\[IMPL\] Black boxes filled. Starting implementation..."

# ---- Implementation ----
opt_design
place_design
phys_opt_design
route_design

# ---- Reports ----
report_timing_summary  -file [file join $rpt_dir impl_timing.rpt]
report_utilization     -file [file join $rpt_dir impl_utilization.rpt]
report_power           -file [file join $rpt_dir impl_power.rpt]

# Check timing
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "\[IMPL\] WNS = $wns ns"
if {$wns < 0} {
    puts "WARNING: Timing NOT closed (WNS=$wns). Bitstream will still be generated."
} else {
    puts "\[IMPL\] Timing CLOSED."
}

# ---- Bitstream ----
write_bitstream -force [file join $proj_root vivado shufflenet.bit]

puts ""
puts "============================================================"
puts " DONE: bitstream -> vivado/shufflenet.bit"
puts " Timing:      vivado/reports/impl_timing.rpt"
puts " Utilization: vivado/reports/impl_utilization.rpt"
puts "============================================================"
