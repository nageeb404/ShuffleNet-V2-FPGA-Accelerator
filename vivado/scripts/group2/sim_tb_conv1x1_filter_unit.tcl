# sim_tb_conv1x1_filter_unit.tcl -- Thesis Sec 5.4.1.2
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g2_dir     [file join $_proj_root rtl group2]
set tb_dir     [file join $_proj_root tb  group2]

sim_run_tb \
    tb_conv1x1_filter_unit \
    [list \
        [file join $common_dir Adder3.v] \
        [file join $common_dir adder_tree_29.v] \
        [file join $common_dir mac_unit.v] \
        [file join $common_dir quantizer.v] \
        [file join $g2_dir    conv1x1_filter_unit.v] \
    ] \
    [file join $tb_dir tb_conv1x1_filter_unit.v] \
    [file join $tb_dir vectors conv1x1_filter_unit_vectors.hex] \
    [list $common_dir $g2_dir]
