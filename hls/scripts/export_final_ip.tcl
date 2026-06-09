# export_final_ip.tcl
# Quick sanity-check export of Model 4 (Final) HLS solution as RTL/IP.
# This does NOT run Vivado synthesis/implementation -- it just packages
# the already-synthesized RTL so we can inspect actual primitive counts
# before committing to a multi-hour Vivado P&R run.
#
# Usage (run from project root N:\GP\shufflenet_rtl\):
#   vitis_hls -f hls/scripts/export_final_ip.tcl

set project_name "shufflenet_hls_final"

open_project $project_name
open_solution "solution_final"

puts "\n=== Exporting RTL/IP (flow=syn, no Vivado synth/impl) ===\n"
export_design -flow syn -rtl verilog -format ip_catalog

puts "\n=== Export complete ==="
puts "IP location: $project_name/solution_final/impl/ip"
