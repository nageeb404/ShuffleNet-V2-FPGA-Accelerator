# sim_tb_group2_fifo.tcl -- Thesis Sec 5.4.6
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g2_dir     [file join $_proj_root rtl group2]
set tb_dir     [file join $_proj_root tb  group2]

sim_run_tb \
    tb_group2_fifo \
    [list \
        [file join $g2_dir group2_fifo.v] \
    ] \
    [file join $tb_dir tb_group2_fifo.v] \
    [file join $tb_dir vectors group2_fifo_vectors.hex] \
    [list $common_dir $g2_dir]
