# sim_tb_group1_ctrl.tcl -- /
set _this_script [file normalize [info script]]
set _script_dir [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g1_dir [file join $_proj_root rtl group1]
set tb_dir [file join $_proj_root tb group1]

sim_run_tb \
 tb_group1_ctrl \
 [list \
 [file join $g1_dir group1_ctrl.v] \
 ] \
 [file join $tb_dir tb_group1_ctrl.v] \
 [file join $tb_dir vectors group1_ctrl_tb_vectors.hex] \
 [list $common_dir $g1_dir]
