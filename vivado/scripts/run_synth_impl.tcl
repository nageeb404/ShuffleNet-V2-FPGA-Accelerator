# Run synthesis + implementation for shufflenet_impl project
# Re-run after terminal crash; resets synth_1 to clear stale __synthesis_is_running__ flag

set_param general.maxThreads 1

set proj_path "N:/GP/shufflenet_rtl/vivado/proj_impl/shufflenet_impl.xpr"
set report_dir "N:/GP/shufflenet_rtl/vivado/reports"

open_project $proj_path

# Reset both runs so Vivado clears the stale is_running flag
reset_run synth_1
reset_run impl_1

# --- Synthesis ---
puts "\[INFO\] Launching synthesis..."
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
 puts "\[ERROR\] Synthesis did not complete. Check Vivado logs."
 close_project
 return -code error "Synthesis failed"
}
puts "\[INFO\] Synthesis complete."

open_run synth_1 -name synth_1
report_utilization -file $report_dir/utilization_synth.rpt
report_timing_summary -file $report_dir/timing_synth.rpt -max_paths 10

# --- Implementation ---
puts "\[INFO\] Launching implementation (place + route)..."
launch_runs impl_1 -jobs 1
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
 puts "\[ERROR\] Implementation did not complete. Check Vivado logs."
 close_project
 return -code error "Implementation failed"
}
puts "\[INFO\] Implementation complete."

open_run impl_1 -name impl_1
report_utilization -file $report_dir/utilization_impl.rpt
report_timing_summary -file $report_dir/timing_summary_impl.rpt -max_paths 10
report_power -file $report_dir/power_impl.rpt
report_drc -file $report_dir/drc_impl.rpt

puts "\[INFO\] All reports saved to $report_dir"
puts "\[INFO\] Done."
close_project
