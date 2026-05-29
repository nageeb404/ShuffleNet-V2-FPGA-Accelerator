# sim_tb_fc_core.tcl -- Module 3.3
set _this_script [file normalize [info script]]
set _script_dir [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g3_dir [file join $_proj_root rtl group3]
set tb_dir [file join $_proj_root tb group3]

sim_run_tb \
 tb_fc_core \
 [list \
 [file join $common_dir Adder3.v] \
 [file join $common_dir quantizer.v] \
 [file join $common_dir mac_unit.v] \
 [file join $common_dir adder_tree_32.v] \
 [file join $g3_dir fc_filter_unit.v] \
 [file join $g3_dir fc_core.v] \
 ] \
 [file join $tb_dir tb_fc_core.v] \
 [file join $tb_dir vectors fc_core_vectors.hex] \
 [list $common_dir $g3_dir]
