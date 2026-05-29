# sim_tb_avg_pool_core.tcl -- Module 3.2
set _this_script [file normalize [info script]]
set _script_dir [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g3_dir [file join $_proj_root rtl group3]
set tb_dir [file join $_proj_root tb group3]

sim_run_tb \
 tb_avg_pool_core \
 [list \
 [file join $g3_dir avg_pool_core.v] \
 ] \
 [file join $tb_dir tb_avg_pool_core.v] \
 [file join $tb_dir vectors avg_pool_vectors.hex] \
 [list $common_dir $g3_dir]
