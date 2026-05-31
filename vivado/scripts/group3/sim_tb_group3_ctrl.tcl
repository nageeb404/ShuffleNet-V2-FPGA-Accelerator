# sim_tb_group3_ctrl.tcl -- Thesis Sec 5.5 Module 3.4
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g3_dir     [file join $_proj_root rtl group3]
set tb_dir     [file join $_proj_root tb  group3]

sim_run_tb \
    tb_group3_ctrl \
    [list \
        [file join $g3_dir group3_ctrl.v] \
    ] \
    [file join $tb_dir tb_group3_ctrl.v] \
    "" \
    [list $common_dir $g3_dir]
