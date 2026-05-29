# sim_tb_fifo_3x3.tcl -- /
set _this_script [file normalize [info script]]
set _script_dir [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set tb_dir [file join $_proj_root tb common]

sim_run_tb \
 tb_fifo_3x3 \
 [list \
 [file join $common_dir fifo_3x3.v] \
 ] \
 [file join $tb_dir tb_fifo_3x3.v] \
 [file join $tb_dir vectors fifo_3x3_vectors.hex] \
 [list $common_dir]
