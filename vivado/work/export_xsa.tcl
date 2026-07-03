# =============================================================================
# export_xsa.tcl -- export the .xsa from the already-routed checkpoint,
# without redoing synthesis/implementation.
# Usage: vivado -mode batch -source vivado/work/export_xsa.tcl
# =============================================================================

set script_dir [file normalize [file dirname [info script]]]
set proj_root  [file normalize [file join $script_dir .. ..]]
set ckpt       [file join $proj_root vivado shufflenet_routed.dcp]
set xsa_out    [file join $proj_root vivado shufflenet.xsa]

if {![file exists $ckpt]} {
    puts "ERROR: routed checkpoint not found: $ckpt"
    return -code error "checkpoint missing"
}

puts "\[XSA\] Opening routed checkpoint: $ckpt"
open_checkpoint $ckpt

puts "\[XSA\] Exporting hardware platform (no embedded bit -- use vivado/shufflenet.bit separately)..."
write_hw_platform -fixed -force -file $xsa_out

puts ""
puts "============================================================"
puts " DONE: hardware platform -> vivado/shufflenet.xsa"
puts "       bitstream (separate) -> vivado/shufflenet.bit"
puts "============================================================"
