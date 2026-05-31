set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set mem_dir    [file join $_proj_root rtl memories]
set tb_dir     [file join $_proj_root tb  memories]

sim_run_tb tb_extra_mem \
    [list [file join $mem_dir extra_mem.v]] \
    [file join $tb_dir tb_extra_mem.v] "" \
    [list $common_dir $mem_dir]
