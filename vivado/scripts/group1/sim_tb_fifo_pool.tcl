# sim_tb_fifo_pool.tcl -- Thesis Sec 5.3.3
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g1_dir     [file join $_proj_root rtl group1]
set tb_dir     [file join $_proj_root tb  group1]

sim_run_tb \
    tb_fifo_pool \
    [list \
        [file join $common_dir fifo_3x3.v] \
        [file join $g1_dir    fifo_pool.v] \
    ] \
    [file join $tb_dir tb_fifo_pool.v] \
    [file join $tb_dir vectors fifo_pool_vectors.hex] \
    [list $common_dir $g1_dir]
