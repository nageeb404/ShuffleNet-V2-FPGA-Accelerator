// =============================================================================
// tb_group2_ctrl.v -- Self-checking testbench for Module 2.10
// -----------------------------------------------------------------------------
// Vector file format per case:
// Line 1: NLOOPS DONE_LAT
// NLOOPS = 16 (total Shuffle blocks)
// DONE_LAT = number of cycles after a start pulse until done fires
// Per cycle (after start_group posedge):
// start[1:0] width[5:0] stride fsm_state[1:0] loops[4:0] group2_done
// done_dw / done_1x1 injection:
// After each non-zero start pulse the TB counts DONE_LAT cycles, then
// asserts both done signals for 1 posedge so the DUT advances to the next
// block. This exactly mirrors the Python golden model.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_group2_ctrl;

 // ---- Clock / reset ----
 reg clk, rst;
 initial clk = 1'b0;
 always #5 clk = ~clk;

 // ---- DUT ----
 reg start_group;
 reg done_dw, done_1x1;
 wire [1:0] start_out;
 wire [5:0] width_out;
 wire stride_out;
 wire [1:0] fsm_state_out;
 wire [4:0] loops_out;
 wire group2_done_out;

 group2_ctrl dut (
 .clk (clk),
 .rst (rst),
 .start_group(start_group),
 .done_dw (done_dw),
 .done_1x1 (done_1x1),
 .start (start_out),
 .width (width_out),
 .stride (stride_out),
 .fsm_state (fsm_state_out),
 .loops (loops_out),
 .group2_done(group2_done_out)
 );

 // ---- Test infrastructure ----
 integer fd, r, scan_r;
 reg [8*1024-1:0] cur_line;
 integer pass_count, fail_count, n_cases, dump_count, cyc;
 reg [8*512-1:0] path_arg;
 integer have_arg;
 integer rd_nloops, rd_lat;
 integer e_start, e_width, e_stride, e_fsm, e_loops, e_done;
 integer step_pass;
 integer countdown, pending;

 initial begin
 pass_count = 0; fail_count = 0; n_cases = 0; dump_count = 0;
 rst = 1'b1;
 start_group = 1'b0;
 done_dw = 1'b0;
 done_1x1 = 1'b0;

 $display("=========================================================");
 $display("group2_ctrl Testbench");
 $display("=========================================================");

 begin : open_file
 have_arg = $value$plusargs("VECTORS=%s", path_arg);
 if (have_arg) fd = $fopen(path_arg, "r");
 else fd = $fopen("tb/group2/vectors/group2_ctrl_vectors.hex", "r");
 if (fd == 0) fd = $fopen("../tb/group2/vectors/group2_ctrl_vectors.hex","r");
 if (fd == 0) fd = $fopen("./group2_ctrl_vectors.hex", "r");
 end
 if (fd == 0) begin $display("ERROR: cannot open vector file"); $finish; end

 #20; @(negedge clk); rst = 1'b0;
 @(negedge clk);

 begin : test_loop
 while (!$feof(fd)) begin

 // ---- Find header: NLOOPS DONE_LAT ----
 begin : find_header
 while (!$feof(fd)) begin
 r = $fgets(cur_line, fd);
 if (r == 0) disable test_loop;
 scan_r = $sscanf(cur_line, "%d %d", rd_nloops, rd_lat);
 if (scan_r == 2 && rd_nloops == 16) disable find_header;
 end
 end
 if ($feof(fd)) disable test_loop;

 // ---- Reset DUT ----
 @(negedge clk); rst = 1'b1;
 @(negedge clk); rst = 1'b0;
 @(negedge clk);

 // ---- Assert start_group for 1 posedge ----
 done_dw = 1'b0;
 done_1x1 = 1'b0;
 start_group = 1'b1;
 @(posedge clk); #1;
 start_group = 1'b0;

 countdown = rd_lat; // start counting from block 0
 pending = 1; // block 0 is in flight
 cyc = 0;

 // ---- Data loop ----
 // At this point we are 1ns after the start_group posedge.
 // cycle 0 outputs are already stable on the DUT ports.
 begin : data_loop
 while (!$feof(fd)) begin
 r = $fgets(cur_line, fd);
 if (r == 0) disable data_loop;
 scan_r = $sscanf(cur_line, "%d %d %d %d %d %d",
 e_start, e_width, e_stride, e_fsm, e_loops, e_done);
 if (scan_r != 6) begin
 if (cyc > 0) disable data_loop;
 end else begin

 // ---- Check DUT outputs ----
 step_pass = 1;
 if (start_out !== e_start[1:0]) step_pass = 0;
 if (width_out !== e_width[5:0]) step_pass = 0;
 if (stride_out !== e_stride[0]) step_pass = 0;
 if (fsm_state_out !== e_fsm[1:0]) step_pass = 0;
 if (loops_out !== e_loops[4:0]) step_pass = 0;
 if (group2_done_out !== e_done[0]) step_pass = 0;

 if (step_pass)
 pass_count = pass_count + 1;
 else begin
 fail_count = fail_count + 1;
 if (dump_count < 8) begin
 $display("FAIL case=%0d cyc=%0d", n_cases, cyc);
 $display(
 " start:%b/%b w:%0d/%0d s:%0d/%0d",
 start_out, e_start,
 width_out, e_width,
 stride_out, e_stride);
 $display(
 " fsm:%0d/%0d loops:%0d/%0d done:%0d/%0d",
 fsm_state_out, e_fsm,
 loops_out, e_loops,
 group2_done_out, e_done);
 dump_count = dump_count + 1;
 end
 end

 if (e_done) disable data_loop;

 // ---- Drive done_dw / done_1x1 for next posedge ----
 // Step 1: clear any previous done assertion
 done_dw = 1'b0;
 done_1x1 = 1'b0;

 // Step 2: if new start pulse seen, restart countdown
 if (e_start != 0) begin
 pending = 1;
 countdown = rd_lat;
 end

 // Step 3: countdown and fire when it hits 0
 if (pending) begin
 countdown = countdown - 1;
 if (countdown == 0) begin
 done_dw = 1'b1;
 done_1x1 = 1'b1;
 pending = 0;
 end
 end

 cyc = cyc + 1;
 @(posedge clk); #1;
 // DUT now shows outputs for next cycle
 end
 end
 end

 n_cases = n_cases + 1;
 done_dw = 1'b0;
 done_1x1 = 1'b0;
 @(negedge clk);
 end
 end

 $fclose(fd);
 $display("---------------------------------------------------------");
 $display("Tested %0d cases, %0d total checks", n_cases,
 pass_count + fail_count);
 $display("PASS: %0d / %0d", pass_count, pass_count + fail_count);
 $display("FAIL: %0d / %0d", fail_count, pass_count + fail_count);
 if (fail_count == 0) $display("RESULT: *** ALL TESTS PASSED ***");
 else $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
 $display("=========================================================");
 $finish;
 end

endmodule

`default_nettype wire
// =============================================================================
// END tb_group2_ctrl.v
// =============================================================================
