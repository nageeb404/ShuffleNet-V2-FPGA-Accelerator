set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set axi_dir    [file join $_proj_root rtl axi]
set tb_dir     [file join $_proj_root tb  axi]

sim_run_tb tb_axi_photo_mem_slave \
    [list [file join $axi_dir axi_photo_mem_slave.v]] \
    [file join $tb_dir tb_axi_photo_mem_slave.v] "" \
    [list $common_dir $axi_dir]
