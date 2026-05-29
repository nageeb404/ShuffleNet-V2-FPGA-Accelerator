# =============================================================================
# build_project.tcl -- Vivado project for ShuffleNet V2 on iWave ZU19EG
# -----------------------------------------------------------------------------
# Target : XCZU19EG-FFVC1760-2-I (Zynq UltraScale+ MPSoC)
# Flow : Block design (Zynq PS) + Module Reference (shufflenet_board_top)
# Vivado : 2024.2 or later
# Creates a block design containing:
# zynq_ultra_ps_e_0 -- Zynq MPSoC PS (100 MHz pl_clk0, AXI master HPM0 FPD)
# axi_interconnect -- Connects PS AXI master to shufflenet_board_top slave
# shufflenet_board_top -- RTL module reference (MMCM + AXI slave + accelerator)
# AXI base address: 0xA000_0000 (32 MB range)
# Pixel write region : base + [0x000000 .. 0x1FFFFF] (AWADDR[21]=0)
# CSR register : base + [0x200000 .. 0x3FFFFF] (AWADDR[21]=1)
# Usage (from project root):
# vivado -mode batch -source vivado/scripts/build_project.tcl
# vivado -mode tcl (then: source vivado/scripts/build_project.tcl; start_gui)
# =============================================================================

# ---- Paths ----
set script_path [file normalize [info script]]
set proj_root [file normalize [file join [file dirname $script_path] .. ..]]
set proj_dir [file join $proj_root vivado prj_zu19eg]
set proj_name "shufflenet_zu19eg"
set part  "xczu19eg-ffvc1760-1-i"
set board "iw-g35m-19eg-4e004g-e008g-lia:part0:1.0"

puts "\[INFO\] Project root : $proj_root"
puts "\[INFO\] Project dir : $proj_dir"
puts "\[INFO\] Part        : $part"
puts "\[INFO\] Board       : $board"

# ---- Clean previous project ----
catch {close_sim -quiet}
catch {close_project -quiet}
if {[file exists $proj_dir]} {
 if {[catch {file delete -force $proj_dir} err]} {
 puts "ERROR: cannot remove $proj_dir -- $err"
 puts " Close any open Vivado sessions and retry."
 return -code error "old project locked"
 }
}
file mkdir $proj_dir

# ---- Create project ----
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]
# Set board so IP Integrator applies iWave DDR4/MIO/clock presets to the Zynq PS
set_property board_part $board [current_project]

# =========================================================================
# Add RTL sources
# =========================================================================
proc add_rtl_dir {dir} {
 # Exclude _stub.v files (OOC synthesis black-boxes, not for full build)
 set all_vfiles [glob -nocomplain -directory $dir *.v]
 set vfiles {}
 foreach f $all_vfiles {
  if {![string match "*_stub.v" $f]} { lappend vfiles $f }
 }
 set vhfiles [glob -nocomplain -directory $dir *.vh]
 if {[llength $vfiles] > 0} { add_files -norecurse $vfiles }
 if {[llength $vhfiles] > 0} {
 add_files -norecurse $vhfiles
 foreach vh $vhfiles {
 set_property file_type "Verilog Header" [get_files [file tail $vh]]
 if {[string match "*shufflenet_pkg*" $vh]} {
 set_property is_global_include true [get_files [file tail $vh]]
 }
 }
 }
 puts "\[INFO\] Added [expr {[llength $vfiles]+[llength $vhfiles]}] file(s) from [file tail $dir]"
}

add_rtl_dir [file join $proj_root rtl common]
add_rtl_dir [file join $proj_root rtl memories]
add_rtl_dir [file join $proj_root rtl group1]
add_rtl_dir [file join $proj_root rtl group2]
add_rtl_dir [file join $proj_root rtl group3]
add_rtl_dir [file join $proj_root rtl axi]

# Top-level RTL files (accelerator_ctrl, accelerator_top, shufflenet_board_top)
foreach f [glob -nocomplain -directory [file join $proj_root rtl] *.v] {
 add_files -norecurse $f
}
puts "\[INFO\] Added top-level rtl/*.v"

# Weight ROM hex files (needed at synthesis/simulation time)
foreach hex_dir [list \
 [file join $proj_root rtl group2 weights] \
 [file join $proj_root rtl group3 weights] \
] {
 set hexfiles [glob -nocomplain -directory $hex_dir *.hex]
 foreach f $hexfiles {
 add_files -norecurse $f
 set_property file_type "Memory Initialization Files" [get_files [file tail $f]]
 }
 puts "\[INFO\] Added [llength $hexfiles] .hex from [file tail $hex_dir]"
}

# Include paths so xvlog finds shufflenet_pkg.vh and *_init.vh
set_property include_dirs [list \
 [file join $proj_root rtl common] \
 [file join $proj_root rtl group1] \
 [file join $proj_root rtl group2] \
 [file join $proj_root rtl group3] \
] [current_fileset]

# =========================================================================
# Block Design: Zynq PS + AXI interconnect + shufflenet_board_top
# =========================================================================
create_bd_design "system"
current_bd_design "system"

# ---- Zynq MPSoC PS ----
set ps [create_bd_cell -type ip \
 -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.3 zynq_ultra_ps_e_0]

# Configure PS:
# - Enable AXI master HPM0 FPD (32-bit data, used for pixel + CSR writes)
# - Enable PL clock 0 at 100 MHz
# - Enable PL reset 0
set_property -dict [list \
 CONFIG.PSU__USE__M_AXI_GP0 {1} \
 CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
 CONFIG.PSU__FPGA_PL0_ENABLE {1} \
 CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] $ps

# Apply BD automation with iWave board preset.
# This configures the PS DDR4, MIO (eMMC/UART/I2C), and fixed-IO connections
# automatically from the iWave board definition loaded above.
apply_bd_automation \
 -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
 -config {apply_board_preset 1} \
 [get_bd_cells zynq_ultra_ps_e_0]

# ---- AXI SmartConnect (PS master -> our slave) ----
set sc [create_bd_cell -type ip \
 -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0]
set_property CONFIG.NUM_SI {1} $sc
set_property CONFIG.NUM_MI {1} $sc

# ---- shufflenet_board_top (Module Reference) ----
# Vivado reads shufflenet_board_top.v from the sources and creates an IP block.
# All s_axi_* ports are auto-mapped to an AXI4-Lite slave interface.
set sn [create_bd_cell -type module \
 -reference shufflenet_board_top shufflenet_board_top_0]

# ---- Connections ----
# Clock: PS pl_clk0 -> smartconnect ACLK, shufflenet ACLK
connect_bd_net \
 [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
 [get_bd_pins smartconnect_0/aclk]
connect_bd_net \
 [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
 [get_bd_pins shufflenet_board_top_0/s_axi_aclk]

# Reset: PS pl_resetn0 -> smartconnect, shufflenet
connect_bd_net \
 [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
 [get_bd_pins smartconnect_0/aresetn]
connect_bd_net \
 [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
 [get_bd_pins shufflenet_board_top_0/s_axi_aresetn]

# AXI: PS master -> smartconnect -> shufflenet slave
connect_bd_intf_net \
 [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
 [get_bd_intf_pins smartconnect_0/S00_AXI]
connect_bd_intf_net \
 [get_bd_intf_pins smartconnect_0/M00_AXI] \
 [get_bd_intf_pins shufflenet_board_top_0/S_AXI]

# ---- Address assignment ----
# Base address 0xA000_0000, range 32 MB (covers pixel region + CSR)
assign_bd_address \
 [get_bd_addr_segs shufflenet_board_top_0/S_AXI/reg0]
set_property offset 0xA0000000 \
 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_shufflenet_board_top_0_reg0}]
set_property range 32M \
 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_shufflenet_board_top_0_reg0}]

# ---- Validate and generate wrapper ----
puts "\[INFO\] Validating block design..."
validate_bd_design
save_bd_design

puts "\[INFO\] Generating HDL wrapper..."
make_wrapper -files [get_files system.bd] -top -force
set wrapper [glob -nocomplain \
 [file join $proj_dir $proj_name.gen sources_1 bd system hdl system_wrapper.v]]
if {[llength $wrapper] == 0} {
 # Vivado 2024 sometimes places the wrapper here instead
 set wrapper [glob -nocomplain \
 [file join $proj_dir $proj_name.srcs sources_1 bd system hdl system_wrapper.v]]
}
if {[llength $wrapper] > 0} {
 add_files -norecurse [lindex $wrapper 0]
 puts "\[INFO\] Added wrapper: [lindex $wrapper 0]"
} else {
 puts "WARNING: could not find system_wrapper.v -- add it manually after opening the GUI"
}

set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

# =========================================================================
# Constraints
# =========================================================================
set xdc [file join $proj_root vivado constraints shufflenet.xdc]
if {[file exists $xdc]} {
 add_files -fileset constrs_1 -norecurse $xdc
 puts "\[INFO\] Added constraints: $xdc"
}

# =========================================================================
# Synthesis settings (Performance-oriented for timing closure)
# =========================================================================
set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
set_property -name steps.synth_design.args.directive \
 -value "PerformanceOptimized" \
 -objects [get_runs synth_1]
set_property -name steps.synth_design.args.flatten_hierarchy \
 -value "rebuilt" \
 -objects [get_runs synth_1]

# =========================================================================
# Implementation settings (timing closure on ZU19EG)
# =========================================================================
set_property strategy "Performance_ExplorePostRoutePhysOpt" [get_runs impl_1]
set_property -name steps.phys_opt_design.is_enabled \
 -value true \
 -objects [get_runs impl_1]
set_property -name steps.post_route_phys_opt_design.is_enabled \
 -value true \
 -objects [get_runs impl_1]

# =========================================================================
# Done
# =========================================================================
puts ""
puts "\[INFO\] ============================================================"
puts "\[INFO\] Project ready: $proj_dir"
puts "\[INFO\] Top module : system_wrapper (BD) -> shufflenet_board_top"
puts "\[INFO\] AXI base : 0xA0000000 (32 MB)"
puts "\[INFO\] Next steps:"
puts "\[INFO\] 1. Verify block design in GUI: start_gui"
puts "\[INFO\] 2. Check LED pin assignments in shufflenet.xdc"
puts "\[INFO\] 3. Run synthesis: launch_runs synth_1 -jobs 4"
puts "\[INFO\] 4. Run impl + bitstream:"
puts "\[INFO\] launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "\[INFO\] wait_on_run impl_1"
puts "\[INFO\] ============================================================"
