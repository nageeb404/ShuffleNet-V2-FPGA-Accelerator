# sim_tb_mac_unit.tcl -- Thesis Sec 5.3.2.1
set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set tb_dir     [file join $_proj_root tb  common]

sim_run_tb \
    tb_mac_unit \
    [list \
        [file join $common_dir mac_unit.v] \
    ] \
    [file join $tb_dir tb_mac_unit.v] \
    [file join $tb_dir vectors mac_unit_vectors.hex] \
    [list $common_dir]
