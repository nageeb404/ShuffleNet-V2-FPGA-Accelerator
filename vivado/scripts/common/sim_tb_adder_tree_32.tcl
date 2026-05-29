# sim_tb_adder_tree_32.tcl -- FC layer adder tree
set _this_script [file normalize [info script]]
set _script_dir [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set tb_dir [file join $_proj_root tb common]

sim_run_tb \
 tb_adder_tree_32 \
 [list \
 [file join $common_dir Adder3.v] \
 [file join $common_dir adder_tree_32.v] \
 ] \
 [file join $tb_dir tb_adder_tree_32.v] \
 [file join $tb_dir vectors adder_tree_32_vectors.hex] \
 [list $common_dir]
