# =============================================================================
# run_all_sims.tcl  -- Run all 48 testbenches and print PASS/FAIL summary
# Usage (Vivado Tcl Console):
#   source N:/GP/shufflenet_v2_fpga/vivado/scripts/run_all_sims.tcl
# =============================================================================

set sim_dir "N:/GP/shufflenet_v2_fpga/vivado/prj_zu19eg/shufflenet_zu19eg.sim/sim_1/behav/xsim"

set tb_list {
    tb_Adder3
    tb_adder_tree_9
    tb_adder_tree_29
    tb_adder_tree_32
    tb_adder_tree_12
    tb_fifo_3x3
    tb_fifo_ctrl
    tb_mac_unit
    tb_quantizer
    tb_bias_rom_3x3
    tb_conv3x3_core
    tb_conv3x3_filter_unit
    tb_fifo_pool
    tb_group1_ctrl
    tb_group1_top
    tb_maxpool_core
    tb_maxpool_mem
    tb_photo_mem
    tb_weights_rom_3x3
    tb_conv1x1_core
    tb_conv1x1_ctrl
    tb_conv1x1_filter_unit
    tb_dw_conv3x3_core
    tb_dw_conv3x3_ctrl
    tb_dw_conv3x3_filter_unit
    tb_g2_dw_bias_rom
    tb_g2_dw_weight_rom
    tb_g2_pw_bias_rom
    tb_g2_pw_weight_rom
    tb_group2_ctrl
    tb_group2_fifo
    tb_group2_fifo_ctrl
    tb_group2_top
    tb_avg_pool_core
    tb_conv1x1_g3_core
    tb_conv1x1_g3_filter_unit
    tb_fc_core
    tb_fc_filter_unit
    tb_g3_fc_bias_rom
    tb_g3_fc_weight_rom
    tb_g3_pw_bias_rom
    tb_g3_pw_weight_rom
    tb_group3_ctrl
    tb_group3_top
    tb_extra_mem
    tb_axi_photo_mem_slave
    tb_accelerator_ctrl
    tb_accelerator_top
}

set pass_list  {}
set fail_list  {}
set error_list {}
set total [llength $tb_list]
set idx 0

foreach tb $tb_list {
    incr idx
    puts "\n\[SIM $idx/$total\] Running $tb ..."

    # Close any open simulation
    catch {close_sim -quiet}

    # Set this TB as simulation top
    set_property top $tb [get_filesets sim_1]
    update_compile_order -fileset sim_1
    set_property -name xsim.simulate.runtime \
        -value {10ms} -objects [get_filesets sim_1]

    # Launch simulation; catch errors (compile/elab failures)
    if {[catch {launch_simulation} err]} {
        puts "  --> LAUNCH ERROR: $err"
        lappend error_list "$tb (launch failed)"
        continue
    }

    # Parse simulate.log for PASS/FAIL keywords
    set log "$sim_dir/simulate.log"
    set status "UNKNOWN"
    if {[file exists $log]} {
        set fh [open $log r]
        set content [read $fh]
        close $fh
        if {[string match "*ALL TESTS PASSED*" $content]} {
            set status "PASS"
        } elseif {[string match "*TESTS FAILED*" $content] ||
                  [string match "*FAIL*"         $content]} {
            set status "FAIL"
        } elseif {[string match "*ERROR*" $content]} {
            set status "ERROR"
        } elseif {[string match "*cannot open*" $content] ||
                  [string match "*could not be opened*" $content]} {
            set status "MISSING_HEX"
        }
    }

    puts "  --> $status"
    switch $status {
        "PASS"        { lappend pass_list  $tb }
        "FAIL"        { lappend fail_list  $tb }
        "MISSING_HEX" { lappend fail_list  "$tb (missing hex)" }
        default       { lappend error_list "$tb ($status)" }
    }
}

catch {close_sim -quiet}

# ---- Summary ----
puts "\n"
puts "============================================================"
puts "  SIMULATION SUMMARY  ($total TBs)"
puts "============================================================"
puts "  PASS  : [llength $pass_list]"
foreach tb $pass_list  { puts "    + $tb" }
puts "  FAIL  : [llength $fail_list]"
foreach tb $fail_list  { puts "    - $tb" }
puts "  ERROR : [llength $error_list]"
foreach tb $error_list { puts "    ! $tb" }
puts "============================================================"
