set _this_script [file normalize [info script]]
set _script_dir  [file dirname $_this_script]
source [file join $_script_dir .. sim_common.tcl]
set _proj_root [file normalize [file join $_script_dir .. .. ..]]
set common_dir [file join $_proj_root rtl common]
set tb_dir  [file join $_proj_root tb  group2]
set rtl_dir [file join $_proj_root rtl group2]
set hex_dir [file join $_proj_root rtl group2 weights]
# Copy hex file to work dir so $readmemh finds it
set _work [file join $_proj_root vivado work tb_g2_dw_weight_rom]
file mkdir $_work
catch {file copy -force [file join $hex_dir g2_dw_weights.hex] $_work}
sim_run_tb tb_g2_dw_weight_rom \
    [list [file join $rtl_dir g2_dw_weight_rom.v]] \
    [file join $tb_dir tb_g2_dw_weight_rom.v] "" [list $common_dir $rtl_dir]
