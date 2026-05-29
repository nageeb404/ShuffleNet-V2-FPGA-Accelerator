// =============================================================================
// tb_fc_core.v -- Self-checking testbench for Module 3.3 (fc_core)
// -----------------------------------------------------------------------------
// Ch 6.2.5 + 6.2.8 update: DATA_W=9 (G3_FM_W), W_W=9 (FC_WW),
// BIAS_WD=11 (FC_BIAS_W). Vector file must be regenerated in new bit widths.
// Vector file format per case:
// Comment: // Case N
// Header: N_PAR N_ACC (32 32)
// Per step (N_ACC+1 steps including wait step):
// acc_clr en
// d0..d31 (32 hex values, DATA_W bits)
// w0..w31 (32 hex values, W_W bits)
// bias (1 hex value, BIAS_WD bits)
// result (1 hex expected, DATA_W bits)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_fc_core;

 localparam N_PAR = `G3_FC_PAR_CHAN; // 32
 localparam DATA_W = `G3_FM_W; // 9 (Ch 6.2.8)
 localparam W_W = `FC_WW; // 9 (Ch 6.2.5)
 localparam BIAS_WD = `FC_BIAS_W; // 11 (Ch 6.2.5)

 reg clk, rst;
 initial clk = 1'b0;
 always #5 clk = ~clk;

 reg en, acc_clr;
 reg signed [DATA_W-1:0] d [0:31];
 reg signed [W_W-1:0] w [0:31];
 reg signed [BIAS_WD-1:0] bias_in;
 wire signed [DATA_W-1:0] result;

 fc_core #(.N_PAR(N_PAR), .DATA_W(DATA_W), .W_W(W_W), .BIAS_WD(BIAS_WD)) dut (
 .clk(clk), .rst(rst), .en(en), .acc_clr(acc_clr),
 .d0(d[0]), .d1(d[1]), .d2(d[2]), .d3(d[3]),
 .d4(d[4]), .d5(d[5]), .d6(d[6]), .d7(d[7]),
 .d8(d[8]), .d9(d[9]), .d10(d[10]), .d11(d[11]),
 .d12(d[12]), .d13(d[13]), .d14(d[14]), .d15(d[15]),
 .d16(d[16]), .d17(d[17]), .d18(d[18]), .d19(d[19]),
 .d20(d[20]), .d21(d[21]), .d22(d[22]), .d23(d[23]),
 .d24(d[24]), .d25(d[25]), .d26(d[26]), .d27(d[27]),
 .d28(d[28]), .d29(d[29]), .d30(d[30]), .d31(d[31]),
 .w0(w[0]), .w1(w[1]), .w2(w[2]), .w3(w[3]),
 .w4(w[4]), .w5(w[5]), .w6(w[6]), .w7(w[7]),
 .w8(w[8]), .w9(w[9]), .w10(w[10]), .w11(w[11]),
 .w12(w[12]), .w13(w[13]), .w14(w[14]), .w15(w[15]),
 .w16(w[16]), .w17(w[17]), .w18(w[18]), .w19(w[19]),
 .w20(w[20]), .w21(w[21]), .w22(w[22]), .w23(w[23]),
 .w24(w[24]), .w25(w[25]), .w26(w[26]), .w27(w[27]),
 .w28(w[28]), .w29(w[29]), .w30(w[30]), .w31(w[31]),
 .bias(bias_in),
 .result(result)
 );

 integer fd, r, scan_r;
 reg [8*2048-1:0] cur_line;
 reg [8*512-1:0] path_arg;
 integer have_arg;
 integer pass_count, fail_count, n_cases, dump_count, step_idx;
 integer rd_npar, rd_nacc;

 reg [DATA_W-1:0] td0,td1,td2,td3,td4,td5,td6,td7,
 td8,td9,td10,td11,td12,td13,td14,td15,
 td16,td17,td18,td19,td20,td21,td22,td23,
 td24,td25,td26,td27,td28,td29,td30,td31;
 reg [W_W-1:0] tw0,tw1,tw2,tw3,tw4,tw5,tw6,tw7,
 tw8,tw9,tw10,tw11,tw12,tw13,tw14,tw15,
 tw16,tw17,tw18,tw19,tw20,tw21,tw22,tw23,
 tw24,tw25,tw26,tw27,tw28,tw29,tw30,tw31;
 reg [BIAS_WD-1:0] t_bias;
 reg [DATA_W-1:0] t_exp;
 integer rd_acc_clr, rd_en;
 integer i;

 initial begin
 pass_count = 0; fail_count = 0; n_cases = 0; dump_count = 0;
 rst = 1'b1;
 en = 1'b0; acc_clr = 1'b0;
 bias_in = {BIAS_WD{1'b0}};
 for (i = 0; i < 32; i = i+1) begin
 d[i] = {DATA_W{1'b0}};
 w[i] = {W_W{1'b0}};
 end

 $display("=========================================================");
 $display("fc_core Testbench (N_PAR=%0d)", N_PAR);
 $display("Ch 6.2.5+6.2.8: DATA_W=%0d W_W=%0d BIAS_WD=%0d",
 DATA_W, W_W, BIAS_WD);
 $display("=========================================================");

 begin : open_file
 have_arg = $value$plusargs("VECTORS=%s", path_arg);
 if (have_arg) fd = $fopen(path_arg, "r");
 else fd = $fopen("tb/group3/vectors/fc_core_vectors.hex", "r");
 if (fd == 0) fd = $fopen("../tb/group3/vectors/fc_core_vectors.hex","r");
 if (fd == 0) fd = $fopen("./fc_core_vectors.hex", "r");
 end
 if (fd == 0) begin $display("ERROR: cannot open vector file"); $finish; end

 #20; @(negedge clk); rst = 1'b0;
 @(negedge clk);

 begin : test_loop
 while (!$feof(fd)) begin

 // Find header: N_PAR N_ACC
 begin : find_header
 while (!$feof(fd)) begin
 r = $fgets(cur_line, fd);
 if (r == 0) disable test_loop;
 scan_r = $sscanf(cur_line, "%d %d", rd_npar, rd_nacc);
 if (scan_r == 2 && rd_npar == N_PAR) disable find_header;
 end
 end
 if ($feof(fd)) disable test_loop;

 // Reset between cases
 @(negedge clk); rst = 1'b1;
 @(negedge clk); rst = 1'b0;
 @(negedge clk);

 // Drive N_ACC+1 steps
 for (step_idx = 0; step_idx <= rd_nacc; step_idx = step_idx+1) begin
 // Read acc_clr en
 r = $fgets(cur_line, fd);
 scan_r = $sscanf(cur_line, "%d %d", rd_acc_clr, rd_en);
 // Read data (DATA_W bits)
 r = $fgets(cur_line, fd);
 scan_r = $sscanf(cur_line,
 "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
 td0,td1,td2,td3,td4,td5,td6,td7,td8,td9,td10,td11,td12,td13,td14,td15,
 td16,td17,td18,td19,td20,td21,td22,td23,td24,td25,td26,td27,td28,td29,td30,td31);
 d[ 0]=td0; d[ 1]=td1; d[ 2]=td2; d[ 3]=td3;
 d[ 4]=td4; d[ 5]=td5; d[ 6]=td6; d[ 7]=td7;
 d[ 8]=td8; d[ 9]=td9; d[10]=td10; d[11]=td11;
 d[12]=td12; d[13]=td13; d[14]=td14; d[15]=td15;
 d[16]=td16; d[17]=td17; d[18]=td18; d[19]=td19;
 d[20]=td20; d[21]=td21; d[22]=td22; d[23]=td23;
 d[24]=td24; d[25]=td25; d[26]=td26; d[27]=td27;
 d[28]=td28; d[29]=td29; d[30]=td30; d[31]=td31;
 // Read weights (W_W bits)
 r = $fgets(cur_line, fd);
 scan_r = $sscanf(cur_line,
 "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
 tw0,tw1,tw2,tw3,tw4,tw5,tw6,tw7,tw8,tw9,tw10,tw11,tw12,tw13,tw14,tw15,
 tw16,tw17,tw18,tw19,tw20,tw21,tw22,tw23,tw24,tw25,tw26,tw27,tw28,tw29,tw30,tw31);
 w[ 0]=tw0; w[ 1]=tw1; w[ 2]=tw2; w[ 3]=tw3;
 w[ 4]=tw4; w[ 5]=tw5; w[ 6]=tw6; w[ 7]=tw7;
 w[ 8]=tw8; w[ 9]=tw9; w[10]=tw10; w[11]=tw11;
 w[12]=tw12; w[13]=tw13; w[14]=tw14; w[15]=tw15;
 w[16]=tw16; w[17]=tw17; w[18]=tw18; w[19]=tw19;
 w[20]=tw20; w[21]=tw21; w[22]=tw22; w[23]=tw23;
 w[24]=tw24; w[25]=tw25; w[26]=tw26; w[27]=tw27;
 w[28]=tw28; w[29]=tw29; w[30]=tw30; w[31]=tw31;
 // Drive control
 acc_clr = rd_acc_clr[0];
 en = rd_en[0];
 @(posedge clk); #1;
 acc_clr = 1'b0;
 en = 1'b0;
 end

 // Read bias (BIAS_WD bits) and expected (DATA_W bits)
 r = $fgets(cur_line, fd);
 scan_r = $sscanf(cur_line, "%h", t_bias);
 bias_in = t_bias;
 r = $fgets(cur_line, fd);
 scan_r = $sscanf(cur_line, "%h", t_exp);

 // Check result
 if (result === $signed(t_exp))
 pass_count = pass_count + 1;
 else begin
 fail_count = fail_count + 1;
 if (dump_count < 8) begin
 $display("FAIL case=%0d: got=%0d exp=%0d",
 n_cases, result, $signed(t_exp));
 dump_count = dump_count + 1;
 end
 end

 n_cases = n_cases + 1;
 @(negedge clk);
 end
 end

 $fclose(fd);
 $display("---------------------------------------------------------");
 $display("Tested %0d cases", n_cases);
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
// END tb_fc_core.v
// =============================================================================
