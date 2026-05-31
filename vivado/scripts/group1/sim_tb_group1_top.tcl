# sim_tb_group1_top.tcl -- Thesis Sec 5.3 / Fig 5.4
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g1_dir     [file join $_proj_root rtl group1]
set tb_dir     [file join $_proj_root tb  group1]

sim_run_tb \
    tb_group1_top \
    [list \
        [file join $common_dir Adder3.v] \
        [file join $common_dir adder_tree_9.v] \
        [file join $common_dir mac_unit.v] \
        [file join $common_dir quantizer.v] \
        [file join $common_dir fifo_3x3.v] \
        [file join $common_dir fifo_ctrl.v] \
        [file join $g1_dir    conv3x3_filter_unit.v] \
        [file join $g1_dir    conv3x3_core.v] \
        [file join $g1_dir    maxpool_core.v] \
        [file join $g1_dir    fifo_pool.v] \
        [file join $g1_dir    weights_rom_3x3.v] \
        [file join $g1_dir    bias_rom_3x3.v] \
        [file join $g1_dir    photo_mem.v] \
        [file join $g1_dir    maxpool_mem.v] \
        [file join $g1_dir    group1_ctrl.v] \
        [file join $g1_dir    group1_top.v] \
    ] \
    [file join $tb_dir tb_group1_top.v] \
    "" \
    [list $common_dir $g1_dir]
