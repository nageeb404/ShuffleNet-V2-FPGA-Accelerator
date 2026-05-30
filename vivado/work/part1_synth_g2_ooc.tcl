# =============================================================================
# part1_synth_g2_ooc.tcl -- OOC synthesis of group2_top
# Run from project root:
#   vivado.bat -mode batch -source vivado/work/part1_synth_g2_ooc.tcl \
#              -log vivado/work/log_g2_ooc.log -journal vivado/work/log_g2_ooc.jou
# Output: vivado/dcp/group2_top.dcp
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir .. ..]]
set part       "xczu19eg-ffvc1760-1-i"
set dcp_dir    [file join $proj_root vivado dcp]
set ooc_dir    [file join $proj_root vivado work ooc_g2]

file mkdir $dcp_dir
file mkdir $ooc_dir

puts "\[G2-OOC\] Project root : $proj_root"
puts "\[G2-OOC\] Output DCP   : $dcp_dir/group2_top.dcp"
puts "\[G2-OOC\] Working dir  : $ooc_dir"

# Copy hex weight files to working directory so $readmemh finds them
foreach f [glob -nocomplain [file join $proj_root rtl group2 weights *.hex]] {
    file copy -force $f $ooc_dir
    puts "\[G2-OOC\] Copied [file tail $f]"
}

# Change to OOC working directory so $readmemh("filename.hex"...) resolves
cd $ooc_dir

# ---- Read sources ----
set inc [list [file join $proj_root rtl common] [file join $proj_root rtl group2]]

# Common files (adders, mac_unit, etc.) -- skip any _bb.v
foreach f [glob -nocomplain [file join $proj_root rtl common *.v]] {
    read_verilog $f
}

# Group2 full RTL -- skip stub
foreach f [glob -nocomplain [file join $proj_root rtl group2 *.v]] {
    if {![string match "*_bb.v" $f]} {
        read_verilog $f
    }
}

puts "\[G2-OOC\] Starting synthesis..."
synth_design -top group2_top -part $part -mode out_of_context \
    -include_dirs $inc \
    -flatten_hierarchy rebuilt

write_checkpoint -force [file join $dcp_dir group2_top.dcp]
puts "\[G2-OOC\] DONE -- group2_top.dcp written"

report_utilization
