# fix_sim_setup.tcl
# Run once in Vivado Tcl Console:
#   source N:/GP/shufflenet_v2_fpga/vivado/scripts/fix_sim_setup.tcl

set proj_root "N:/GP/shufflenet_v2_fpga"

# 1. Exclude black-box stubs from simulation
foreach f [get_files -filter {NAME =~ *_bb.v}] {
    set_property USED_IN_SIMULATION false $f
    puts "\[INFO\] Excluded from sim: [file tail $f]"
}

# 2. Add full group1/2/3 RTL to sim_1 (skip stubs)
foreach grp {group1 group2 group3} {
    foreach f [glob -nocomplain $proj_root/rtl/$grp/*.v] {
        if {[string match *_bb.v $f]} continue
        if {[string match *_stub.v $f]} continue
        add_files -fileset sim_1 -norecurse $f
        puts "\[INFO\] Added to sim_1: [file tail $f]"
    }
}

# 3. Refresh compile order
update_compile_order -fileset sim_1

puts ""
puts "\[DONE\] Simulation sources fixed. You can now run any TB."
