# sim_tb_group3_top.tcl -- Thesis Sec 5.5 Group 3 top-level structural smoke test
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g2_dir     [file join $_proj_root rtl group2]
set g3_dir     [file join $_proj_root rtl group3]
set tb_dir     [file join $_proj_root tb  group3]
set _g3hex [file join $_proj_root rtl group3 weights]
set _work3 [file join $_proj_root vivado work tb_group3_top]
file mkdir $_work3
foreach _hf {g3_pw_weights.hex g3_pw_biases.hex g3_fc_weights.hex g3_fc_biases.hex} {
    catch {file copy -force [file join $_g3hex $_hf] $_work3}
}

sim_run_tb \
    tb_group3_top \
    [list \
        [file join $common_dir Adder3.v] \
        [file join $common_dir quantizer.v] \
        [file join $common_dir mac_unit.v] \
        [file join $common_dir adder_tree_12.v] \
        [file join $common_dir adder_tree_29.v] \
        [file join $common_dir adder_tree_32.v] \
        [file join $g3_dir conv1x1_g3_filter_unit.v] \
        [file join $g3_dir conv1x1_g3_core.v] \
        [file join $g3_dir g3_pw_weight_rom.v] \
        [file join $g3_dir g3_pw_bias_rom.v] \
        [file join $g3_dir g3_fc_weight_rom.v] \
        [file join $g3_dir g3_fc_bias_rom.v] \
        [file join $g3_dir avg_pool_core.v] \
        [file join $g3_dir fc_filter_unit.v] \
        [file join $g3_dir fc_core.v] \
        [file join $g3_dir group3_ctrl.v] \
        [file join $g3_dir group3_top.v] \
    ] \
    [file join $tb_dir tb_group3_top.v] \
    "" \
    [list $common_dir $g2_dir $g3_dir]
