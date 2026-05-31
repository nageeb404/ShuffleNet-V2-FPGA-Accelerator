# sim_tb_accelerator_ctrl.tcl -- Thesis Sec 5.6 Module 4.1
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. ..]]
set common_dir [file join $_proj_root rtl common]
set rtl_dir    [file join $_proj_root rtl]
set tb_dir     [file join $_proj_root tb]

sim_run_tb \
    tb_accelerator_ctrl \
    [list \
        [file join $rtl_dir accelerator_ctrl.v] \
    ] \
    [file join $tb_dir tb_accelerator_ctrl.v] \
    "" \
    [list $common_dir $rtl_dir]
