// =============================================================================
// tb_conv3x3_core.v -- Self-checking testbench for Module 1.3b
// -----------------------------------------------------------------------------
// Ch 6.2.5 + 6.2.8 update: IN_W=8 (data), W_W=12 (weights), BIAS_WD=15,
// OUT_W=10 (results). Vector file must be regenerated in new bit widths.
// Vector file format: 123 lines per test case
// Row r (r=0,1,2): line 1 = 9 shared data values (hex, IN_W bits)
// lines 2-25 = 9 weights for filter 0..23 (W_W bits, one filter/line)
// Lines 76-99: one bias per filter (1 hex value per line, BIAS_WD bits)
// Lines 100-123: one expected result per filter (OUT_W bits)
// Pipeline timing (identical to conv3x3_filter_unit):
// negedge 0: drive row0 data + row0 weights, acc_clr=1
// negedge 1: drive row1 data + row1 weights, acc_clr=1, drive biases
// negedge 2: drive row2 data + row2 weights, acc_clr=0
// negedge 3: wait
// negedge 4: CHECK all 24 results
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_conv3x3_core;

 localparam integer N_FILT = `G1_CONV_PAR_FILT; // 24
 localparam integer IN_W = `PHOTO_W; // 8 (Ch 6.2.8)
 localparam integer W_W = `G1_CONV_WW; // 12 (Ch 6.2.5)
 localparam integer BIAS_WD = `DATA_W; // 15 (bias width)
 localparam integer OUT_W = `G1_FM_W; // 10 (Ch 6.2.8)
 localparam integer W_TOT = N_FILT * 9 * W_W; // 2592
 localparam integer B_TOT = N_FILT * BIAS_WD; // 360
 localparam integer R_TOT = N_FILT * OUT_W; // 240

 // ---- Clock / reset ----
 reg clk, rst, en, acc_clr;

 initial clk = 1'b0;
 always #5 clk = ~clk; // 100 MHz

 // ---- DUT ports ----
 reg signed [IN_W-1:0] dut_d0, dut_d1, dut_d2, dut_d3, dut_d4,
 dut_d5, dut_d6, dut_d7, dut_d8;
 reg [W_TOT-1:0] dut_weights;
 reg [B_TOT-1:0] dut_biases;
 wire [R_TOT-1:0] dut_results;

 conv3x3_core dut (
 .clk (clk),
 .rst (rst),
 .en (en),
 .acc_clr (acc_clr),
 .d0(dut_d0), .d1(dut_d1), .d2(dut_d2),
 .d3(dut_d3), .d4(dut_d4), .d5(dut_d5),
 .d6(dut_d6), .d7(dut_d7), .d8(dut_d8),
 .weights_flat(dut_weights),
 .biases_flat (dut_biases),
 .results_flat(dut_results)
 );

 // ---- Parse temporaries ----
 reg [IN_W-1:0] d_r0 [0:8];
 reg [IN_W-1:0] d_r1 [0:8];
 reg [IN_W-1:0] d_r2 [0:8];
 reg [W_W-1:0] tmp_w [0:8];
 reg [W_TOT-1:0] w_flat_r0, w_flat_r1, w_flat_r2;
 reg [BIAS_WD-1:0] tmp_bias [0:23];
 reg [OUT_W-1:0] tmp_exp [0:23];

 // ---- Miscellaneous ----
 integer fd, r, sc, flt, tidx, kidx;
 integer n_vectors, pass_count, fail_count, dump_count;
 reg [8*1024-1:0] line_buf;
 reg [8*512-1:0] path_arg;
 integer have_arg;
 reg [OUT_W-1:0] got_val;

 // ====================================================================
 initial begin
 n_vectors = 0;
 pass_count = 0;
 fail_count = 0;
 dump_count = 0;
 rst = 1'b1;
 en = 1'b0;
 acc_clr = 1'b1;
 dut_d0 = {IN_W{1'b0}}; dut_d1 = {IN_W{1'b0}};
 dut_d2 = {IN_W{1'b0}}; dut_d3 = {IN_W{1'b0}};
 dut_d4 = {IN_W{1'b0}}; dut_d5 = {IN_W{1'b0}};
 dut_d6 = {IN_W{1'b0}}; dut_d7 = {IN_W{1'b0}};
 dut_d8 = {IN_W{1'b0}};
 dut_weights = {W_TOT{1'b0}};
 dut_biases = {B_TOT{1'b0}};

 $display("=========================================================");
 $display("conv3x3_core Testbench");
 $display("24 parallel filter units, shared 9-element data bus");
 $display("Ch 6.2.5+6.2.8: IN_W=%0d W_W=%0d BIAS_WD=%0d OUT_W=%0d",
 IN_W, W_W, BIAS_WD, OUT_W);
 $display("=========================================================");

 // ---- Open vector file ----
 begin : open_file
 have_arg = $value$plusargs("VECTORS=%s", path_arg);
 if (have_arg)
 fd = $fopen(path_arg, "r");
 else
 fd = $fopen("tb/common/vectors/conv3x3_core_vectors.hex", "r");
 if (fd == 0)
 fd = $fopen("../tb/common/vectors/conv3x3_core_vectors.hex", "r");
 if (fd == 0)
 fd = $fopen("./conv3x3_core_vectors.hex", "r");
 end
 if (fd == 0) begin
 $display("ERROR: cannot open conv3x3_core_vectors.hex");
 $finish;
 end

 // ---- Reset sequence ----
 #20;
 @(negedge clk);
 rst = 1'b0;
 en = 1'b1;
 @(negedge clk);

 // ====================================================================
 // Main loop: each iteration reads 123 lines for one test case.
 // ====================================================================
 begin : main_loop
 while (!$feof(fd)) begin

 // ---- Try to read row0 data ----
 r = $fgets(line_buf, fd);
 if (r == 0) disable main_loop;
 sc = $sscanf(line_buf,
 "%h %h %h %h %h %h %h %h %h",
 d_r0[0], d_r0[1], d_r0[2],
 d_r0[3], d_r0[4], d_r0[5],
 d_r0[6], d_r0[7], d_r0[8]);
 if (sc != 9) begin
 // not a data line -- skip
 end else begin

 // ---- Row0 weights: 24 filters x 9 values ----
 for (flt = 0; flt < N_FILT; flt = flt + 1) begin
 r = $fgets(line_buf, fd);
 sc = $sscanf(line_buf,
 "%h %h %h %h %h %h %h %h %h",
 tmp_w[0], tmp_w[1], tmp_w[2],
 tmp_w[3], tmp_w[4], tmp_w[5],
 tmp_w[6], tmp_w[7], tmp_w[8]);
 for (tidx = 0; tidx < 9; tidx = tidx + 1)
 w_flat_r0[(flt*9 + tidx)*W_W +: W_W] = tmp_w[tidx];
 end

 // ---- Row1 data ----
 r = $fgets(line_buf, fd);
 sc = $sscanf(line_buf,
 "%h %h %h %h %h %h %h %h %h",
 d_r1[0], d_r1[1], d_r1[2],
 d_r1[3], d_r1[4], d_r1[5],
 d_r1[6], d_r1[7], d_r1[8]);

 // ---- Row1 weights ----
 for (flt = 0; flt < N_FILT; flt = flt + 1) begin
 r = $fgets(line_buf, fd);
 sc = $sscanf(line_buf,
 "%h %h %h %h %h %h %h %h %h",
 tmp_w[0], tmp_w[1], tmp_w[2],
 tmp_w[3], tmp_w[4], tmp_w[5],
 tmp_w[6], tmp_w[7], tmp_w[8]);
 for (tidx = 0; tidx < 9; tidx = tidx + 1)
 w_flat_r1[(flt*9 + tidx)*W_W +: W_W] = tmp_w[tidx];
 end

 // ---- Row2 data ----
 r = $fgets(line_buf, fd);
 sc = $sscanf(line_buf,
 "%h %h %h %h %h %h %h %h %h",
 d_r2[0], d_r2[1], d_r2[2],
 d_r2[3], d_r2[4], d_r2[5],
 d_r2[6], d_r2[7], d_r2[8]);

 // ---- Row2 weights ----
 for (flt = 0; flt < N_FILT; flt = flt + 1) begin
 r = $fgets(line_buf, fd);
 sc = $sscanf(line_buf,
 "%h %h %h %h %h %h %h %h %h",
 tmp_w[0], tmp_w[1], tmp_w[2],
 tmp_w[3], tmp_w[4], tmp_w[5],
 tmp_w[6], tmp_w[7], tmp_w[8]);
 for (tidx = 0; tidx < 9; tidx = tidx + 1)
 w_flat_r2[(flt*9 + tidx)*W_W +: W_W] = tmp_w[tidx];
 end

 // ---- Biases: 24 lines, 1 value each ----
 dut_biases = {B_TOT{1'b0}};
 for (flt = 0; flt < N_FILT; flt = flt + 1) begin
 r = $fgets(line_buf, fd);
 sc = $sscanf(line_buf, "%h", tmp_bias[flt]);
 dut_biases[flt*BIAS_WD +: BIAS_WD] = tmp_bias[flt];
 end

 // ---- Expected results: 24 lines, 1 value each ----
 for (flt = 0; flt < N_FILT; flt = flt + 1) begin
 r = $fgets(line_buf, fd);
 sc = $sscanf(line_buf, "%h", tmp_exp[flt]);
 end

 // ============================================================
 // Drive DUT through 5-negedge pipeline sequence
 // ============================================================

 // negedge 0: row0 data, row0 weights, acc_clr=1
 @(negedge clk);
 acc_clr = 1'b1;
 dut_weights = w_flat_r0;
 dut_d0 = $signed(d_r0[0]); dut_d1 = $signed(d_r0[1]);
 dut_d2 = $signed(d_r0[2]); dut_d3 = $signed(d_r0[3]);
 dut_d4 = $signed(d_r0[4]); dut_d5 = $signed(d_r0[5]);
 dut_d6 = $signed(d_r0[6]); dut_d7 = $signed(d_r0[7]);
 dut_d8 = $signed(d_r0[8]);

 // negedge 1: row1 data, row1 weights, acc_clr=1
 @(negedge clk);
 acc_clr = 1'b1;
 dut_weights = w_flat_r1;
 dut_d0 = $signed(d_r1[0]); dut_d1 = $signed(d_r1[1]);
 dut_d2 = $signed(d_r1[2]); dut_d3 = $signed(d_r1[3]);
 dut_d4 = $signed(d_r1[4]); dut_d5 = $signed(d_r1[5]);
 dut_d6 = $signed(d_r1[6]); dut_d7 = $signed(d_r1[7]);
 dut_d8 = $signed(d_r1[8]);

 // negedge 2: row2 data, row2 weights, acc_clr=0
 @(negedge clk);
 acc_clr = 1'b0;
 dut_weights = w_flat_r2;
 dut_d0 = $signed(d_r2[0]); dut_d1 = $signed(d_r2[1]);
 dut_d2 = $signed(d_r2[2]); dut_d3 = $signed(d_r2[3]);
 dut_d4 = $signed(d_r2[4]); dut_d5 = $signed(d_r2[5]);
 dut_d6 = $signed(d_r2[6]); dut_d7 = $signed(d_r2[7]);
 dut_d8 = $signed(d_r2[8]);

 // negedge 3: wait
 @(negedge clk);

 // negedge 4: check all 24 results
 @(negedge clk);
 begin : check_loop
 integer fail_this;
 fail_this = 0;
 for (kidx = 0; kidx < N_FILT; kidx = kidx + 1) begin
 got_val = dut_results[kidx*OUT_W +: OUT_W];
 if (got_val !== tmp_exp[kidx]) begin
 fail_this = fail_this + 1;
 if (dump_count < 10) begin
 $display(
 "FAIL case=%0d filter=%0d got=%0d exp=%0d",
 n_vectors, kidx,
 $signed(got_val), $signed(tmp_exp[kidx]));
 dump_count = dump_count + 1;
 end
 end
 end
 if (fail_this == 0)
 pass_count = pass_count + 1;
 else
 fail_count = fail_count + 1;
 end

 n_vectors = n_vectors + 1;

 end // if sc == 9

 end // while (!$feof)
 end // main_loop

 $fclose(fd);
 $display("---------------------------------------------------------");
 $display("Tested %0d vectors (%0d filter-results each)",
 n_vectors, N_FILT);
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
// END tb_conv3x3_core.v
// =============================================================================
