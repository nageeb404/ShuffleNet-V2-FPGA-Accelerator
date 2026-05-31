# sim_tb_group2_top.tcl -- Thesis Sec 5.4 Group 2 top-level structural smoke test
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g2_dir     [file join $_proj_root rtl group2]
set tb_dir     [file join $_proj_root tb  group2]
# Copy hex files so $readmemh finds them in work dir
set _g2hex [file join $_proj_root rtl group2 weights]
set _work2 [file join $_proj_root vivado work tb_group2_top]
file mkdir $_work2
foreach _hf {g2_dw_weights.hex g2_dw_biases.hex g2_pw_weights.hex g2_pw_biases.hex} {
    catch {file copy -force [file join $_g2hex $_hf] $_work2}
}

sim_run_tb \
    tb_group2_top \
    [list \
        [file join $common_dir Adder3.v] \
        [file join $common_dir quantizer.v] \
        [file join $common_dir mac_unit.v] \
        [file join $common_dir adder_tree_9.v] \
        [file join $common_dir adder_tree_12.v] \
        [file join $common_dir adder_tree_29.v] \
        [file join $g2_dir dw_conv3x3_filter_unit.v] \
        [file join $g2_dir dw_conv3x3_core.v] \
        [file join $g2_dir conv1x1_filter_unit.v] \
        [file join $g2_dir conv1x1_core.v] \
        [file join $g2_dir group2_fifo.v] \
        [file join $g2_dir group2_fifo_ctrl.v] \
        [file join $g2_dir dw_conv3x3_ctrl.v] \
        [file join $g2_dir conv1x1_ctrl.v] \
        [file join $g2_dir group2_ctrl.v] \
        [file join $g2_dir g2_dw_weight_rom.v] \
        [file join $g2_dir g2_dw_bias_rom.v] \
        [file join $g2_dir g2_pw_weight_rom.v] \
        [file join $g2_dir g2_pw_bias_rom.v] \
        [file join $g2_dir group2_top.v] \
    ] \
    [file join $tb_dir tb_group2_top.v] \
    "" \
    [list $common_dir $g2_dir]
