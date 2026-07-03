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
set board "iwavesystems.com:iw-g35m-19eg-4e004g-e008g-lia:part0:1.0"

puts "\[INFO\] Project root : $proj_root"
puts "\[INFO\] Project dir : $proj_dir"
puts "\[INFO\] Part        : $part"
puts "\[INFO\] Board       : $board"

# ---- Retry helper ----
# IP customization/GUI files (both project-generated module-reference metadata
# and Vivado's own installed IP catalog .tcl files) are occasionally reported
# missing on first read on this machine (antivirus real-time scanning racing
# ahead of/behind the actual file access). Retrying a few seconds later clears
# it every time observed so far, so any step that touches IP customization
# data goes through this wrapper instead of failing the whole build.
proc with_retry {desc body_script {max_attempts 4} {delay_ms 4000}} {
 for {set attempt 1} {$attempt <= $max_attempts} {incr attempt} {
  if {[catch {uplevel 1 $body_script} err]} {
   puts "WARNING: $desc attempt $attempt failed: $err"
   if {$attempt == $max_attempts} {
    error "$desc failed after $max_attempts attempts: $err"
   }
   after $delay_ms
  } else {
   return
  }
 }
}

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
  if {![string match "*_stub.v" $f] && ![string match "*_bb.v" $f]} { lappend vfiles $f }
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
# group1/2/3: black-box stubs only. OOC synthesis needs a module definition to
# avoid "module not found" errors; empty bodies with (* black_box *) tell
# Vivado not to generate logic. The OOC run must use flatten_hierarchy=none so
# these empty cells are not optimized away (see part3_synth_and_impl.tcl).
# Real netlists are injected via read_checkpoint -cell at implementation time.
add_files -norecurse [file join $proj_root rtl group1 group1_top_bb.v]
add_files -norecurse [file join $proj_root rtl group2 group2_top_bb.v]
add_files -norecurse [file join $proj_root rtl group3 group3_top_bb.v]
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
with_retry "create zynq_ultra_ps_e_0" {
 catch {remove_bd_objs [get_bd_cells -quiet zynq_ultra_ps_e_0]}
 set ::ps [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0]
}
set ps $::ps

# Step 1: Apply iWave board preset first.
# This sets DDR4 timing, MIO (UART/eMMC/Ethernet/I2C), fixed-IO, and
# connects DDR/FIXED_IO ports automatically. Must come BEFORE our property
# overrides because apply_bd_automation resets properties to preset defaults.
with_retry "apply_bd_automation zynq_ultra_ps_e" {
 apply_bd_automation \
  -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
  -config {apply_board_preset 1} \
  [get_bd_cells zynq_ultra_ps_e_0]
}

# Step 2: Override / add our specific settings on top of the board preset.
# Enable AXI master HPM0 FPD for pixel writes and CSR access from PS,
# confirm PL clock 0 at 100 MHz.
set_property -dict [list \
 CONFIG.PSU__USE__M_AXI_GP0 {1} \
 CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
 CONFIG.PSU__USE__M_AXI_GP1 {0} \
 CONFIG.PSU__FPGA_PL0_ENABLE {1} \
 CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] $ps

# ---- AXI SmartConnect (PS master -> our slave) ----
with_retry "create smartconnect_0" {
 catch {remove_bd_objs [get_bd_cells -quiet smartconnect_0]}
 set ::sc [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0]
}
set sc $::sc
set_property CONFIG.NUM_SI {1} $sc
set_property CONFIG.NUM_MI {1} $sc

# ---- shufflenet_board_top (Module Reference) ----
# Vivado reads shufflenet_board_top.v from the sources and creates an IP block.
# All s_axi_* ports are auto-mapped to an AXI4-Lite slave interface.
with_retry "create shufflenet_board_top_0" {
 catch {remove_bd_objs [get_bd_cells -quiet shufflenet_board_top_0]}
 set ::sn [create_bd_cell -type module \
  -reference shufflenet_board_top shufflenet_board_top_0]
}
set sn $::sn
# Synthesize our RTL globally (with synth_1) instead of as a separate OOC
# sub-process. This avoids two concurrent synthesis processes competing for RAM.
set_property SYNTH_CHECKPOINT_MODE None [get_bd_cells shufflenet_board_top_0]

# ---- Processor System Reset (synchronized reset for the 100 MHz PL domain) ----
with_retry "create rst_system_100M" {
 catch {remove_bd_objs [get_bd_cells -quiet rst_system_100M]}
 set ::rst [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_system_100M]
}
set rst $::rst

# ---- System ILA (debug: watch both AXI4-Lite interfaces on hardware) ----
# Slot 0: smartconnect -> shufflenet_board_top (accelerator's own AXI slave port)
# Slot 1: PS M_AXI_HPM0_FPD -> smartconnect (PS master side)
with_retry "create system_ila_0" {
 catch {remove_bd_objs [get_bd_cells -quiet system_ila_0]}
 set ::ila [create_bd_cell -type ip \
  -vlnv xilinx.com:ip:system_ila:1.1 system_ila_0]
}
set ila $::ila
set_property -dict [list \
 CONFIG.C_MON_TYPE {INTERFACE} \
 CONFIG.C_NUM_MONITOR_SLOTS {2} \
 CONFIG.C_DATA_DEPTH {2048} \
 CONFIG.C_EN_STRG_QUAL {1} \
 CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:aximm_rtl:1.0} \
 CONFIG.C_SLOT_1_INTF_TYPE {xilinx.com:interface:aximm_rtl:1.0} \
] $ila

# ---- Connections ----
# Clock: PS pl_clk0 -> smartconnect, shufflenet, PS HPM0 FPD clock input,
# the reset block's sync clock, and the ILA's sample clock.
# maxihpm0_fpd_aclk must be driven (required by PS IP for the AXI master port).
connect_bd_net \
 [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
 [get_bd_pins smartconnect_0/aclk] \
 [get_bd_pins shufflenet_board_top_0/s_axi_aclk] \
 [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
 [get_bd_pins rst_system_100M/slowest_sync_clk] \
 [get_bd_pins system_ila_0/clk]

# Reset: PS pl_resetn0 -> rst_system_100M -> smartconnect, shufflenet, ILA.
# (Routed through proc_sys_reset instead of driving peripherals directly, for
# a properly synchronized reset release.)
connect_bd_net \
 [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
 [get_bd_pins rst_system_100M/ext_reset_in]
connect_bd_net \
 [get_bd_pins rst_system_100M/peripheral_aresetn] \
 [get_bd_pins smartconnect_0/aresetn] \
 [get_bd_pins shufflenet_board_top_0/s_axi_aresetn] \
 [get_bd_pins system_ila_0/resetn]

# AXI: PS master -> smartconnect -> shufflenet slave.
# Both interfaces are also tapped by the ILA as monitor-only connections
# (mode=Monitor on the ILA's SLOT_0_AXI / SLOT_1_AXI ports). Vivado cannot
# resolve a 3-way connect_bd_intf_net when one pin is Monitor-mode, so the
# real master/slave pair is connected first, then the ILA tap is added onto
# the existing net in a second call.
connect_bd_intf_net \
 [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
 [get_bd_intf_pins smartconnect_0/S00_AXI]
connect_bd_intf_net \
 [get_bd_intf_pins smartconnect_0/S00_AXI] \
 [get_bd_intf_pins system_ila_0/SLOT_1_AXI]

connect_bd_intf_net \
 [get_bd_intf_pins smartconnect_0/M00_AXI] \
 [get_bd_intf_pins shufflenet_board_top_0/S_AXI]
connect_bd_intf_net \
 [get_bd_intf_pins smartconnect_0/M00_AXI] \
 [get_bd_intf_pins system_ila_0/SLOT_0_AXI]

# ---- Address assignment ----
# Use create_bd_addr_seg directly: auto-assign tries 4G which exceeds the
# 256M aperture at 0xA0000000 on M_AXI_HPM0_FPD. 32M fits fine.
create_bd_addr_seg \
 -range 32M -offset 0xA0000000 \
 [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
 [get_bd_addr_segs shufflenet_board_top_0/S_AXI/reg0] \
 SEG_shufflenet_board_top_0_reg0
puts "\[INFO\] Address: shufflenet at 0xA0000000, range 32M"

# ---- Validate and generate wrapper ----
# validate_bd_design triggers internal IP elaboration (e.g. smartconnect's
# sub-cells) which reads more IP-catalog customization files, so it goes
# through the same retry wrapper as the explicit create_bd_cell calls above.
puts "\[INFO\] Validating block design..."
with_retry "validate_bd_design" { validate_bd_design }
save_bd_design

puts "\[INFO\] Generating HDL wrapper..."
with_retry "make_wrapper" {
 make_wrapper -files [get_files system.bd] -top -force
}

# ---- Generate IP output products ----
# Without this, every cell in the block design (Zynq PS, SmartConnect, System
# ILA, proc_sys_reset, and the shufflenet_board_top module reference) has no
# synthesizable netlist available and synth_design silently drops in an empty
# black box for each one instead of erroring -- the run reports "0 errors" but
# produces a near-empty checkpoint. This step must run before synth_1.
puts "\[INFO\] Generating IP output products..."
with_retry "generate_target" {
 generate_target all [get_files system.bd]
}
with_retry "export_ip_user_files" {
 export_ip_user_files -of_objects [get_files system.bd] -no_script -sync -force -quiet
}
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
