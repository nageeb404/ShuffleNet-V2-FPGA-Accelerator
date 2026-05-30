# =============================================================================
# part0_synth_g1_ooc.tcl -- OOC synthesis of group1_top
# Run from project root:
#   vivado.bat -mode batch -source vivado/work/part0_synth_g1_ooc.tcl \
#              -log vivado/work/log_g1_ooc.log -journal vivado/work/log_g1_ooc.jou
# Output: vivado/dcp/group1_top.dcp
# Note: group1 ROMs have inline weights (no hex files needed)
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir .. ..]]
set part       "xczu19eg-ffvc1760-1-i"
set dcp_dir    [file join $proj_root vivado dcp]

file mkdir $dcp_dir

puts "\[G1-OOC\] Project root : $proj_root"
puts "\[G1-OOC\] Output DCP   : $dcp_dir/group1_top.dcp"

# ---- Read sources ----
set inc [list [file join $proj_root rtl common] [file join $proj_root rtl group1]]

foreach f [glob -nocomplain [file join $proj_root rtl common *.v]] {
    read_verilog $f
}
foreach f [glob -nocomplain [file join $proj_root rtl group1 *.v]] {
    if {![string match "*_bb.v" $f]} {
        read_verilog $f
    }
}

puts "\[G1-OOC\] Starting synthesis..."
synth_design -top group1_top -part $part -mode out_of_context \
    -include_dirs $inc \
    -flatten_hierarchy rebuilt

write_checkpoint -force [file join $dcp_dir group1_top.dcp]
puts "\[G1-OOC\] DONE -- group1_top.dcp written"

report_utilization
