# sim_tb_bias_rom_3x3.tcl -- /
set _this_script [file normalize [info script]]
set _script_dir [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set g1_dir [file join $_proj_root rtl group1]
set tb_dir [file join $_proj_root tb group1]

sim_run_tb \
 tb_bias_rom_3x3 \
 [list \
 [file join $g1_dir bias_rom_3x3.v] \
 ] \
 [file join $tb_dir tb_bias_rom_3x3.v] \
 [file join $tb_dir vectors bias_rom_3x3_tb_vectors.hex] \
 [list $common_dir $g1_dir]
