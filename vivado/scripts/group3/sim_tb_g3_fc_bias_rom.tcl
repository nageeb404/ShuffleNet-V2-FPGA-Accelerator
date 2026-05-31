set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set tb_dir  [file join $_proj_root tb  group3]
set rtl_dir [file join $_proj_root rtl group3]
set hex_dir [file join $_proj_root rtl group3 weights]
set _work [file join $_proj_root vivado work tb_g3_fc_bias_rom]
file mkdir $_work
catch {file copy -force [file join $hex_dir g3_fc_biases.hex] $_work}
sim_run_tb tb_g3_fc_bias_rom \
    [list [file join $rtl_dir g3_fc_bias_rom.v]] \
    [file join $tb_dir tb_g3_fc_bias_rom.v] "" [list $common_dir $rtl_dir]
