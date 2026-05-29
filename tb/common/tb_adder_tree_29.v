// =============================================================================
// tb_adder_tree_29.v -- Self-checking testbench for adder_tree_29 (Module 2.3)
// -----------------------------------------------------------------------------
// Vector file format (2 lines per test case):
// Line 1: in0..in28 (29 x 6-hex 23-bit values)
// Line 2: expected (1 x 8-hex 31-bit value)
// DUT is purely combinational; drive inputs, wait #1, check output.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_adder_tree_29;

 localparam integer IN_W = `MUL_OUT_W; // 23
 localparam integer OUT_W = IN_W + 8; // 31

 // ---- DUT ports ----
 reg signed [IN_W-1:0] p_in0, p_in1, p_in2, p_in3, p_in4,
 p_in5, p_in6, p_in7, p_in8, p_in9,
 p_in10, p_in11, p_in12, p_in13, p_in14,
 p_in15, p_in16, p_in17, p_in18, p_in19,
 p_in20, p_in21, p_in22, p_in23, p_in24,
 p_in25, p_in26, p_in27, p_in28;
 wire signed [OUT_W-1:0] dut_out;

 adder_tree_29 #(.IN_W(IN_W), .OUT_W(OUT_W)) dut (
 .in0 (p_in0), .in1 (p_in1), .in2 (p_in2),
 .in3 (p_in3), .in4 (p_in4), .in5 (p_in5),
 .in6 (p_in6), .in7 (p_in7), .in8 (p_in8),
 .in9 (p_in9), .in10(p_in10), .in11(p_in11),
 .in12(p_in12), .in13(p_in13), .in14(p_in14),
 .in15(p_in15), .in16(p_in16), .in17(p_in17),
 .in18(p_in18), .in19(p_in19), .in20(p_in20),
 .in21(p_in21), .in22(p_in22), .in23(p_in23),
 .in24(p_in24), .in25(p_in25), .in26(p_in26),
 .in27(p_in27), .in28(p_in28),
 .sum_out(dut_out)
 );

 // ---- Parse temporaries ----
 reg [IN_W-1:0] p_i0, p_i1, p_i2, p_i3, p_i4,
 p_i5, p_i6, p_i7, p_i8, p_i9,
 p_i10, p_i11, p_i12, p_i13, p_i14,
 p_i15, p_i16, p_i17, p_i18, p_i19,
 p_i20, p_i21, p_i22, p_i23, p_i24,
 p_i25, p_i26, p_i27, p_i28;
 reg [OUT_W-1:0] p_exp;

 integer fd, r, scan1, scan2;
 integer n_vectors, pass_count, fail_count, dump_count;
 reg [8*512-1:0] path_arg;
 integer have_arg;
 reg [8*1024-1:0] line1, line2;

 // ====================================================================
 initial begin
 n_vectors = 0;
 pass_count = 0;
 fail_count = 0;
 dump_count = 0;

 $display("=========================================================");
 $display("adder_tree_29 Testbench");
 $display("=========================================================");

 // ---- Open vector file ----
 begin : open_file
 have_arg = $value$plusargs("VECTORS=%s", path_arg);
 if (have_arg)
 fd = $fopen(path_arg, "r");
 else
 fd = $fopen("tb/common/vectors/adder_tree_29_vectors.hex", "r");
 if (fd == 0)
 fd = $fopen("../tb/common/vectors/adder_tree_29_vectors.hex", "r");
 if (fd == 0)
 fd = $fopen("./adder_tree_29_vectors.hex", "r");
 end
 if (fd == 0) begin
 $display("ERROR: cannot open adder_tree_29_vectors.hex");
 $finish;
 end

 // ====================================================================
 // Main test loop -- read 2 lines per case
 // ====================================================================
 begin : main_loop
 while (!$feof(fd)) begin
 r = $fgets(line1, fd);
 if (r == 0) disable main_loop;
 scan1 = $sscanf(line1,
 "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
 p_i0, p_i1, p_i2, p_i3, p_i4,
 p_i5, p_i6, p_i7, p_i8, p_i9,
 p_i10, p_i11, p_i12, p_i13, p_i14,
 p_i15, p_i16, p_i17, p_i18, p_i19,
 p_i20, p_i21, p_i22, p_i23, p_i24,
 p_i25, p_i26, p_i27, p_i28);
 if (scan1 != 29) begin
 // comment or blank line -- skip
 end else begin
 r = $fgets(line2, fd);
 scan2 = $sscanf(line2, "%h", p_exp);
 if (scan2 == 1) begin
 // Drive inputs
 p_in0 = $signed(p_i0); p_in1 = $signed(p_i1);
 p_in2 = $signed(p_i2); p_in3 = $signed(p_i3);
 p_in4 = $signed(p_i4); p_in5 = $signed(p_i5);
 p_in6 = $signed(p_i6); p_in7 = $signed(p_i7);
 p_in8 = $signed(p_i8); p_in9 = $signed(p_i9);
 p_in10 = $signed(p_i10); p_in11 = $signed(p_i11);
 p_in12 = $signed(p_i12); p_in13 = $signed(p_i13);
 p_in14 = $signed(p_i14); p_in15 = $signed(p_i15);
 p_in16 = $signed(p_i16); p_in17 = $signed(p_i17);
 p_in18 = $signed(p_i18); p_in19 = $signed(p_i19);
 p_in20 = $signed(p_i20); p_in21 = $signed(p_i21);
 p_in22 = $signed(p_i22); p_in23 = $signed(p_i23);
 p_in24 = $signed(p_i24); p_in25 = $signed(p_i25);
 p_in26 = $signed(p_i26); p_in27 = $signed(p_i27);
 p_in28 = $signed(p_i28);
 #1; // combinational settle
 if (dut_out === $signed(p_exp)) begin
 pass_count = pass_count + 1;
 end else begin
 fail_count = fail_count + 1;
 if (dump_count < 10) begin
 $display("FAIL #%0d: got=%0d exp=%0d",
 n_vectors, dut_out, $signed(p_exp));
 dump_count = dump_count + 1;
 end
 end
 n_vectors = n_vectors + 1;
 end
 end
 end
 end

 $fclose(fd);
 $display("---------------------------------------------------------");
 $display("Tested %0d vectors", n_vectors);
 $display("PASS: %0d / %0d", pass_count, n_vectors);
 $display("FAIL: %0d / %0d", fail_count, n_vectors);
 if (fail_count == 0)
 $display("RESULT: *** ALL TESTS PASSED ***");
 else
 $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
 $display("=========================================================");
 $finish;
 end

endmodule

`default_nettype wire
// =============================================================================
// END tb_adder_tree_29.v
// =============================================================================
