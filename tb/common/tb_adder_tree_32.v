// =============================================================================
// tb_adder_tree_32.v -- Self-checking testbench for adder_tree_32
// -----------------------------------------------------------------------------
// Vector format: 32 signed hex inputs (IN_W=23) + 1 expected output (OUT_W=30)
// Purely combinational DUT; checked with #1 settling delay.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_adder_tree_32;

 localparam IN_W = `MUL_OUT_W; // 23
 localparam OUT_W = IN_W + 7; // 30

 // 32 inputs
 reg signed [IN_W-1:0] i0,i1,i2,i3,i4,i5,i6,i7,
 i8,i9,i10,i11,i12,i13,i14,i15,
 i16,i17,i18,i19,i20,i21,i22,i23,
 i24,i25,i26,i27,i28,i29,i30,i31;
 wire signed [OUT_W-1:0] dut_out;

 adder_tree_32 dut (
 .in0(i0), .in1(i1), .in2(i2), .in3(i3),
 .in4(i4), .in5(i5), .in6(i6), .in7(i7),
 .in8(i8), .in9(i9), .in10(i10), .in11(i11),
 .in12(i12), .in13(i13), .in14(i14), .in15(i15),
 .in16(i16), .in17(i17), .in18(i18), .in19(i19),
 .in20(i20), .in21(i21), .in22(i22), .in23(i23),
 .in24(i24), .in25(i25), .in26(i26), .in27(i27),
 .in28(i28), .in29(i29), .in30(i30), .in31(i31),
 .sum_out(dut_out)
 );

 integer fd, r, scan_r;
 reg [8*2048-1:0] cur_line;
 reg [8*512-1:0] path_arg;
 integer have_arg;
 integer pass_count, fail_count, n_vec, dump_count;

 reg [IN_W-1:0] t0,t1,t2,t3,t4,t5,t6,t7,
 t8,t9,t10,t11,t12,t13,t14,t15,
 t16,t17,t18,t19,t20,t21,t22,t23,
 t24,t25,t26,t27,t28,t29,t30,t31;
 reg [OUT_W-1:0] t_exp;

 initial begin : sim_main
 pass_count = 0; fail_count = 0; n_vec = 0; dump_count = 0;
 {i0,i1,i2,i3,i4,i5,i6,i7,
 i8,i9,i10,i11,i12,i13,i14,i15,
 i16,i17,i18,i19,i20,i21,i22,i23,
 i24,i25,i26,i27,i28,i29,i30,i31} = {(32*IN_W){1'b0}};

 $display("=========================================================");
 $display("adder_tree_32 Testbench");
 $display("=========================================================");

 begin : open_file
 have_arg = $value$plusargs("VECTORS=%s", path_arg);
 if (have_arg) fd = $fopen(path_arg, "r");
 else fd = $fopen("tb/common/vectors/adder_tree_32_vectors.hex", "r");
 if (fd == 0) fd = $fopen("../tb/common/vectors/adder_tree_32_vectors.hex","r");
 if (fd == 0) fd = $fopen("./adder_tree_32_vectors.hex", "r");
 end
 if (fd == 0) begin $display("ERROR: cannot open vector file"); $finish; end

 begin : file_loop
 while (!$feof(fd)) begin
 r = $fgets(cur_line, fd);
 if (r == 0) disable file_loop;
 // skip comment/blank lines (starts with '/' or whitespace)
 scan_r = $sscanf(cur_line,
 "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
 t0,t1,t2,t3,t4,t5,t6,t7,
 t8,t9,t10,t11,t12,t13,t14,t15,
 t16,t17,t18,t19,t20,t21,t22,t23,
 t24,t25,t26,t27,t28,t29,t30,t31, t_exp);
 if (scan_r == 33) begin
 {i0,i1,i2,i3,i4,i5,i6,i7,
 i8,i9,i10,i11,i12,i13,i14,i15,
 i16,i17,i18,i19,i20,i21,i22,i23,
 i24,i25,i26,i27,i28,i29,i30,i31} =
 {t0,t1,t2,t3,t4,t5,t6,t7,
 t8,t9,t10,t11,t12,t13,t14,t15,
 t16,t17,t18,t19,t20,t21,t22,t23,
 t24,t25,t26,t27,t28,t29,t30,t31};
 #1;
 n_vec = n_vec + 1;
 if (dut_out === $signed(t_exp))
 pass_count = pass_count + 1;
 else begin
 fail_count = fail_count + 1;
 if (dump_count < 8) begin
 $display("FAIL vec=%0d: out=%0d exp=%0d",
 n_vec, dut_out, $signed(t_exp));
 dump_count = dump_count + 1;
 end
 end
 end
 end
 end // file_loop

 $fclose(fd);
 $display("---------------------------------------------------------");
 $display("Tested %0d vectors", pass_count + fail_count);
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
// END tb_adder_tree_32.v
// =============================================================================
