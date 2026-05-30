# =============================================================================
# part2_synth_g3_ooc.tcl -- OOC synthesis of group3_top
# Run from project root:
#   vivado.bat -mode batch -source vivado/work/part2_synth_g3_ooc.tcl \
#              -log vivado/work/log_g3_ooc.log -journal vivado/work/log_g3_ooc.jou
# Output: vivado/dcp/group3_top.dcp
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir .. ..]]
set part       "xczu19eg-ffvc1760-1-i"
set dcp_dir    [file join $proj_root vivado dcp]
set ooc_dir    [file join $proj_root vivado work ooc_g3]

file mkdir $dcp_dir
file mkdir $ooc_dir

puts "\[G3-OOC\] Project root : $proj_root"
puts "\[G3-OOC\] Output DCP   : $dcp_dir/group3_top.dcp"
puts "\[G3-OOC\] Working dir  : $ooc_dir"

# Copy hex weight files to working directory so $readmemh finds them
foreach f [glob -nocomplain [file join $proj_root rtl group3 weights *.hex]] {
    file copy -force $f $ooc_dir
    puts "\[G3-OOC\] Copied [file tail $f]"
}

# Change to OOC working directory
cd $ooc_dir

# ---- Read sources ----
set inc [list [file join $proj_root rtl common] [file join $proj_root rtl group3]]

# Common files
foreach f [glob -nocomplain [file join $proj_root rtl common *.v]] {
    read_verilog $f
}

# Group3 full RTL -- skip stub and fc_core_stub.v
foreach f [glob -nocomplain [file join $proj_root rtl group3 *.v]] {
    if {![string match "*_bb.v" $f] && ![string match "*_stub.v" $f]} {
        read_verilog $f
    }
}

puts "\[G3-OOC\] Starting synthesis..."
synth_design -top group3_top -part $part -mode out_of_context \
    -include_dirs $inc \
    -flatten_hierarchy rebuilt

write_checkpoint -force [file join $dcp_dir group3_top.dcp]
puts "\[G3-OOC\] DONE -- group3_top.dcp written"

report_utilization
