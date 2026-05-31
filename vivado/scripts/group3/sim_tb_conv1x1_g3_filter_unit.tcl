set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g3_dir     [file join $_proj_root rtl group3]
set tb_dir     [file join $_proj_root tb  group3]

sim_run_tb \
    tb_conv1x1_g3_filter_unit \
    [list \
        [file join $common_dir Adder3.v] \
        [file join $common_dir adder_tree_29.v] \
        [file join $common_dir mac_unit.v] \
        [file join $common_dir quantizer.v] \
        [file join $g3_dir conv1x1_g3_filter_unit.v] \
    ] \
    [file join $tb_dir tb_conv1x1_g3_filter_unit.v] \
    "" \
    [list $common_dir $g3_dir]
