# run_real_image_csim.tcl -- Run HLS C simulation with real golden retriever image
# Expected: class 207 (golden retriever) matching Python Q6.8 model.
# Binary path is hardcoded as absolute in tb_shufflenet.cpp (TEST_IMAGE_PATH).
# Prereq: hls/tb/test_image.bin must exist (run preprocess_image.py first).
# Usage (from project root):
# vitis_hls -f hls/scripts/run_real_image_csim.tcl

open_project shufflenet_hls
set_top Shuffle_Model

add_files hls/src/shufflenet_hls.cpp \
 -cflags "-I hls/src -I hls/weights"

add_files -tb hls/tb/tb_shufflenet.cpp \
 -cflags "-I hls/src -I hls/weights -DUSE_SYNTHETIC_INPUT=0 -DEXPECTED_CLASS=207"

open_solution "solution_pipeline"
set_part xc7k160tfbg676-2
create_clock -period 10 -name default

puts "\n=== Running C Simulation with real image (golden retriever) ==="
puts " Image binary: N:/GP/shufflenet_rtl/hls/tb/test_image.bin"
puts " Expected class: 207 (golden retriever)"
puts " Python Q6.8 reference: class 207, score=3921\n"

catch {csim_design -clean}
puts "\nDone. See: shufflenet_hls/solution_pipeline/csim/report/Shuffle_Model_csim.log"
