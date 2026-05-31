# =============================================================================
# sim_common.tcl - Shared helpers for the Vivado XSim runner Tcl scripts
# -----------------------------------------------------------------------------
# Design principle: NEVER call `exit` in these scripts. Reason:
#   - In batch mode (`vivado -mode batch -source ...`), Vivado exits
#     automatically when the script finishes, so `exit` is redundant.
#   - In interactive mode (`source ...` from the Tcl Console), `exit` would
#     kill the entire Vivado application -- which is exactly the bug we are
#     fixing here.
#
# For errors, we use `return -code error "..."`, which:
#   - In batch  : causes Vivado to terminate with a non-zero exit code.
#   - Interactive: prints the error in red and returns control to the Tcl
#                  Console without killing Vivado.
# =============================================================================

# -----------------------------------------------------------------------------
# sim_run_tb : run one self-checking testbench through xvlog/xelab/xsim.
#
# Arguments:
#   tb_name   : top-level TB module name (e.g. tb_mac_unit)
#   rtl_files : list of paths to RTL source files needed by the TB
#   tb_file   : path to the TB source file
#   vec_file  : path to the .hex vector file (passed via +VECTORS=...); "" = none
#   inc_dirs  : list of include directories (each added as -i <dir> to xvlog).
#               Always pass at least rtl/common/ for shufflenet_pkg.vh.
#               Add rtl/group1/ when group1 init .vh files are needed.
# -----------------------------------------------------------------------------
proc sim_run_tb {tb_name rtl_files tb_file vec_file inc_dirs} {
    # Resolve project root: two levels above vivado/scripts/ (or three if in
    # vivado/scripts/common/ or vivado/scripts/group1/).
    set this_script [file normalize [info script]]
    set script_dir  [file dirname $this_script]
    # Walk up until we reach the project root (identified by CLAUDE.md).
    # sim_common.tcl is always at vivado/scripts/sim_common.tcl; project root
    # is two levels up from that directory.
    set proj_root   [file normalize [file join $script_dir .. ..]]
    set work_dir    [file join $proj_root vivado work $tb_name]
    file mkdir $work_dir

    puts "\[INFO\] Project root: $proj_root"
    puts "\[INFO\] Working dir : $work_dir"
    puts "\[INFO\] TB          : $tb_name"
    puts "\[INFO\] Vectors     : $vec_file"

    # Move into the work directory so XSim artifacts land there.
    cd $work_dir

    # ---- 1) Compile ----
    puts "\n\[INFO\] xvlog: compiling sources..."
    set xvlog_args {}
    # Add all include directories
    foreach d $inc_dirs { lappend xvlog_args -i $d }
    # Add all RTL source files
    foreach f $rtl_files { lappend xvlog_args $f }
    # Add testbench
    lappend xvlog_args $tb_file
    if {[catch {eval exec xvlog $xvlog_args} msg]} {
        puts $msg
        return -code error "xvlog failed"
    }
    puts $msg

    # ---- 2) Elaborate ----
    puts "\n\[INFO\] xelab: elaborating $tb_name..."
    set snap "${tb_name}_snap"
    if {[catch {exec xelab -debug typical -L work $tb_name -snapshot $snap} msg]} {
        puts $msg
        return -code error "xelab failed"
    }
    puts $msg

    # ---- 3) Simulate ----
    puts "\n\[INFO\] xsim: running simulation..."
    if {[catch {exec xsim $snap -R -testplusarg "VECTORS=$vec_file"} msg]} {
        puts $msg
        return -code error "xsim failed"
    }
    puts $msg

    puts "\n\[INFO\] Simulation completed. See messages above for PASS/FAIL summary."
}
