# =============================================================================
# run_implementation.tcl
# Run full synthesis + implementation for accelerator_top on Kintex-7
# (Virtex-7 xc7vx690t not installed; Kintex-7 is architecturally identical
# 7-series silicon -- resource/timing numbers scale the same way)
# Usage (from project root N:\GP\shufflenet_rtl):
# vivado -mode batch -source vivado/scripts/run_implementation.tcl \
# -log build/rtl_impl.log -nojournal
# =============================================================================

# Limit threads: i5-11400H has 6 cores, default Vivado threads=8 saturates system
set_param general.maxThreads 4

set PART "xc7k160tfbg676-2"
set TOP "accelerator_top"
set XDC [file normalize "vivado/constraints/shufflenet.xdc"]
set PROJ_DIR [file normalize "vivado/proj_impl"]
set PROJ_NAME "shufflenet_impl"
set BUILD_DIR [file normalize "build"]

# ---- Collect RTL sources ----
proc glob_rtl {dir} {
 set files {}
 foreach pat {*.v *.vh} {
 set found [glob -nocomplain -directory $dir $pat]
 set files [concat $files $found]
 }
 return $files
}

set rtl_root [file normalize "rtl"]
set src_files {}
foreach sub {common group1 group2 group3} {
 set sub_dir [file join $rtl_root $sub]
 if {[file isdirectory $sub_dir]} {
 set files [glob_rtl $sub_dir]
 set src_files [concat $src_files $files]
 puts "\[INFO\] $sub: [llength $files] files"
 }
}
# top-level rtl/*.v
set top_files [glob -nocomplain -directory $rtl_root *.v]
set src_files [concat $src_files $top_files]
puts "\[INFO\] Total RTL files: [llength $src_files]"

# ---- Create fresh project ----
catch {close_project -quiet}
if {[file exists $PROJ_DIR]} {
 file delete -force $PROJ_DIR
}

create_project $PROJ_NAME $PROJ_DIR -part $PART -force
puts "\[INFO\] Project created: part=$PART"

# ---- Add sources ----
foreach f $src_files {
 if {[string match "*.vh" $f]} {
 add_files -norecurse $f
 set_property file_type "Verilog Header" [get_files $f]
 if {[string match "*shufflenet_pkg*" $f]} {
 set_property is_global_include true [get_files $f]
 }
 } else {
 add_files -norecurse $f
 }
}

# ---- Add constraints ----
if {[file exists $XDC]} {
 add_files -fileset constrs_1 -norecurse $XDC
 puts "\[INFO\] Added XDC: $XDC"
}

# ---- Set top ----
set_property top $TOP [current_fileset]
update_compile_order -fileset sources_1
puts "\[INFO\] Top module: $TOP"

# =============================================================================
# Ch 6.2.1 -- Powerful implementation directives
# the speed of the design at synthesis and implementation stages."
# =============================================================================

# --- Synthesis directives ---
# PerformanceOptimized: enables retiming and more aggressive logic mapping
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE PerformanceOptimized \
 [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

# =============================================================================
# SYNTHESIS
# =============================================================================
puts "\n\[INFO\] === SYNTHESIS START ==="
puts "\[INFO\] Part: $PART"

launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]
puts "\[INFO\] Synthesis: status=$synth_status progress=$synth_progress"

if {$synth_progress ne "100%"} {
 puts "ERROR: Synthesis did not complete (progress=$synth_progress)"
 return -code error "synthesis failed"
}

open_run synth_1 -name synth_1

# Write post-synthesis reports
set util_synth [file join $BUILD_DIR rtl_synth_utilization.rpt]
set time_synth [file join $BUILD_DIR rtl_synth_timing.rpt]
report_utilization -file $util_synth
report_timing_summary -file $time_synth -max_paths 10
puts "\[INFO\] Synth utilization : $util_synth"
puts "\[INFO\] Synth timing est. : $time_synth"

# =============================================================================
# IMPLEMENTATION
# =============================================================================
puts "\n\[INFO\] === IMPLEMENTATION START ==="

# --- Implementation directives (Ch 6.2.1) ---
# Performance_ExplorePostRoutePhysOpt: aggressive timing closure with
# post-route physical optimization (Vivado's best single-pass strategy).
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreWithRemap \
 [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraNetDelay_high \
 [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore \
 [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE NoTimingRelaxation \
 [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true \
 [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore \
 [get_runs impl_1]

launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
puts "\[INFO\] Implementation: status=$impl_status progress=$impl_progress"

if {$impl_progress ne "100%"} {
 puts "ERROR: Implementation did not complete (progress=$impl_progress)"
 return -code error "implementation failed"
}

open_run impl_1 -name impl_1

# Write post-implementation reports
set util_impl [file join $BUILD_DIR rtl_impl_utilization.rpt]
set time_impl [file join $BUILD_DIR rtl_impl_timing.rpt]
set wns_rpt [file join $BUILD_DIR rtl_impl_timing_wns.rpt]

set pwr_impl [file join $BUILD_DIR rtl_impl_power.rpt]

report_utilization -file $util_impl
report_timing_summary -file $time_impl -max_paths 20
report_timing -file $wns_rpt -max_paths 5 -sort_by slack
report_power -file $pwr_impl

puts "\[INFO\] Impl utilization : $util_impl"
puts "\[INFO\] Impl timing : $time_impl"
puts "\[INFO\] Impl power : $pwr_impl"

# =============================================================================
# SUMMARY
# =============================================================================
puts "\n\[INFO\] =================================================="
puts "\[INFO\] IMPLEMENTATION COMPLETE"
puts "\[INFO\] =================================================="
puts ""
puts "Expected utilization (Virtex-7 xc7vx690t):"
puts " BRAM_18K: 1098 / 2940 = 37%"
puts " DSP48 : 2885 / 3600 = 80%"
puts " LUT : 108638 / 693120 = 16%"
puts " FF : 106736 / 1386240 = 8%"
puts ""
puts "Scale our Kintex-7 numbers to Virtex-7 for comparison:"
puts " BRAM_18K available on V7: 2940"
puts " DSP48 available on V7: 3600"
puts " LUT available on V7: 693120"
puts " FF available on V7: 1386240"
puts ""
puts "Reports written to: $BUILD_DIR"
