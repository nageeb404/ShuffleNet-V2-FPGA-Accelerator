# sim_tb_dw_conv3x3_core.tcl -- Thesis Sec 5.4.1.1 / Table 5.3
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g2_dir     [file join $_proj_root rtl group2]
set tb_dir     [file join $_proj_root tb  group2]

sim_run_tb \
    tb_dw_conv3x3_core \
    [list \
        [file join $common_dir Adder3.v] \
        [file join $common_dir adder_tree_9.v] \
        [file join $common_dir mac_unit.v] \
        [file join $common_dir quantizer.v] \
        [file join $g2_dir    dw_conv3x3_filter_unit.v] \
        [file join $g2_dir    dw_conv3x3_core.v] \
    ] \
    [file join $tb_dir tb_dw_conv3x3_core.v] \
    [file join $tb_dir vectors dw_conv3x3_core_vectors.hex] \
    [list $common_dir $g2_dir]
