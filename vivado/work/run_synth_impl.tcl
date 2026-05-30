# run_synth_impl.tcl -- full flow: synthesis + implementation + bitstream

set_param general.maxThreads 1

open_project {N:/GP/shufflenet_v2_fpga/vivado/prj_zu19eg/shufflenet_zu19eg.xpr}

# ---- Synthesis ----
puts {[INFO] Resetting synth_1...}
reset_run synth_1
puts {[INFO] Starting synthesis (1 thread)...}
launch_runs synth_1 -jobs 1
wait_on_run synth_1

set prog [get_property PROGRESS [get_runs synth_1]]
set stat [get_property STATUS   [get_runs synth_1]]
puts "Synthesis: $stat  $prog"

if {$prog ne "100%"} {
    puts {ERROR: Synthesis failed}
    exit 1
}

# Synthesis reports
file mkdir {N:/GP/shufflenet_v2_fpga/vivado/reports}
open_run synth_1
report_utilization    -file {N:/GP/shufflenet_v2_fpga/vivado/reports/synth_utilization.rpt}
report_timing_summary -file {N:/GP/shufflenet_v2_fpga/vivado/reports/synth_timing.rpt} -max_paths 10
puts {[INFO] Synthesis reports written.}

# ---- Implementation + bitstream ----
puts {[INFO] Starting implementation + bitstream (1 thread)...}
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1

set prog [get_property PROGRESS [get_runs impl_1]]
set stat [get_property STATUS   [get_runs impl_1]]
puts "Implementation: $stat  $prog"

open_run impl_1
report_utilization    -file {N:/GP/shufflenet_v2_fpga/vivado/reports/impl_utilization.rpt}
report_timing_summary -file {N:/GP/shufflenet_v2_fpga/vivado/reports/impl_timing.rpt} -max_paths 10

set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "WNS = $wns ns    WHS = $whs ns"

if {[expr {$wns >= 0.0}]} {
    puts {[INFO] TIMING PASSED}
} else {
    puts "WARNING: TIMING VIOLATION WNS = $wns ns"
}

# Copy bitstream
set bits [glob -nocomplain {N:/GP/shufflenet_v2_fpga/vivado/prj_zu19eg/shufflenet_zu19eg.runs/impl_1/*.bit}]
if {[llength $bits] > 0} {
    set dst {N:/GP/shufflenet_v2_fpga/vivado/work/shufflenet_zu19eg.bit}
    file copy -force [lindex $bits 0] $dst
    puts "Bitstream copied to $dst"
} else {
    puts {WARNING: .bit file not found in impl_1}
}

puts {[INFO] ============================}
puts {[INFO] FLOW COMPLETE}
puts {[INFO] ============================}
