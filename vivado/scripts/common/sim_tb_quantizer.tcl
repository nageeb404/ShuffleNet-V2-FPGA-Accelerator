# sim_tb_quantizer.tcl -- Thesis Sec 5.4.1.1/5.4.1.2
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set tb_dir     [file join $_proj_root tb  common]

sim_run_tb \
    tb_quantizer \
    [list \
        [file join $common_dir quantizer.v] \
    ] \
    [file join $tb_dir tb_quantizer.v] \
    [file join $tb_dir vectors quantizer_vectors.hex] \
    [list $common_dir]
