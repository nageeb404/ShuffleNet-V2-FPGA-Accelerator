# load_image.tcl — Load ShuffleNet test image into DDR via XSCT debugger
#
# Run this in XSCT while shufflenet_test_baremetal is waiting at the UART prompt.
#
# Usage:
#   xsct> connect
#   xsct> targets -set -filter {name =~ "Cortex-A53 #0"}
#   xsct> source <path>/load_image.tcl
#
# Optional overrides before sourcing:
#   set ::image_bin  "/path/to/image.bin"
#   set ::ddr_base   0x10000000
# ---------------------------------------------------------------------------

set script_dir [file dirname [file normalize [info script]]]

if {![info exists ::image_bin]} {
    set ::image_bin [file join $script_dir "image.bin"]
}
if {![info exists ::ddr_base]} {
    set ::ddr_base 0x10000000
}

# ---------------------------------------------------------------------------
# Validate file
# ---------------------------------------------------------------------------
if {![file exists $::image_bin]} {
    error "Image file not found: $::image_bin\nRun gen_test_image_baremetal.py first."
}

set file_size [file size $::image_bin]
if {$file_size != 150528} {
    error "Wrong file size: $file_size bytes (expected 150528 = 224x224x3)"
}

# ---------------------------------------------------------------------------
# Load raw binary into DDR using dow -data (fast — single JTAG bulk transfer)
# ---------------------------------------------------------------------------
puts "Loading $::image_bin ($file_size bytes) to [format 0x%08X $::ddr_base] ..."
dow -data $::image_bin $::ddr_base
puts "Load complete."

# ---------------------------------------------------------------------------
# Verify: read back first 8 bytes and display
# The first 4 bytes are R channel pixels 0-3 packed as a 32-bit little-endian word.
# ---------------------------------------------------------------------------
puts ""
puts "Verification — first 8 bytes of DDR (should match R channel pixels 0..7):"
mrd -size b $::ddr_base 8

puts ""
puts "Image loaded successfully."
puts "Return to the UART terminal and press ENTER to start inference."

# ---------------------------------------------------------------------------
# Alternative: word-by-word loading from image.coe (slow, ~37632 mwr calls)
# Uncomment and use only if dow -data is not available on your XSCT version.
#
# proc load_from_coe {coe_file base_addr} {
#     set fp [open $coe_file r]
#     set addr $base_addr
#     set count 0
#     while {[gets $fp line] >= 0} {
#         if {[string match "*=*" $line]} { continue }
#         set val [string trim $line ",; \r\n\t"]
#         if {$val eq ""} { continue }
#         mwr $addr 0x$val
#         incr addr 4
#         incr count
#         if {$count % 1000 == 0} { puts "$count / 37632 words written..." }
#     }
#     close $fp
#     puts "Loaded $count words from $coe_file"
# }
#
# set coe_file [file join $script_dir "image.coe"]
# load_from_coe $coe_file $::ddr_base
# ---------------------------------------------------------------------------
