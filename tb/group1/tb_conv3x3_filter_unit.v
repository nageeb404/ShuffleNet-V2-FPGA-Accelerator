// =============================================================================
// tb_conv3x3_filter_unit.v -- Self-checking testbench for Module 1.3a
// -----------------------------------------------------------------------------
// Thesis Sec 5.8.1 (Python golden -> hex file -> self-checking TB)
// Thesis Sec 5.3.2.1 (filter unit behaviour)
//
// Ch 6.2.5 + 6.2.8 update: data=IN_W=8, weights=W_W=12, bias=BIAS_WD=15,
//   result=OUT_W=10. Vector file must be regenerated in new bit widths.
//
// Vector file format (4 lines per test case):
//   Line 1: d[0..8] w[0..8]  -- row 0 data (8-bit) and weights (12-bit), 18 hex tokens
//   Line 2: d[0..8] w[0..8]  -- row 1
//   Line 3: d[0..8] w[0..8]  -- row 2
//   Line 4: bias  expected    -- 15-bit bias, 10-bit expected
//
// Pipeline timing (per test case):
//   negedge 0: drive row0,  en=1, acc_clr=1
//   negedge 1: drive row1,  en=1, acc_clr=1
//   negedge 2: drive row2,  en=1, acc_clr=0, drive bias
//   negedge 3: wait
//   negedge 4: CHECK result
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_conv3x3_filter_unit;

    localparam integer IN_W    = `PHOTO_W;    // 8  (Ch 6.2.8: photo pixel input)
    localparam integer W_W     = `G1_CONV_WW; // 12 (Ch 6.2.5: weight width)
    localparam integer BIAS_WD = `DATA_W;     // 15 (bias kept at original width)
    localparam integer OUT_W   = `G1_FM_W;   // 10 (Ch 6.2.8: G1 FM output)
    localparam integer MAX_CASES  = 512;

    // ---- Clock / reset / control ----
    reg clk, rst, en, acc_clr;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- DUT ports ----
    reg signed [IN_W-1:0]    dut_d0, dut_d1, dut_d2, dut_d3, dut_d4,
                              dut_d5, dut_d6, dut_d7, dut_d8;
    reg signed [W_W-1:0]     dut_w0, dut_w1, dut_w2, dut_w3, dut_w4,
                              dut_w5, dut_w6, dut_w7, dut_w8;
    reg  signed [BIAS_WD-1:0] dut_bias;
    wire signed [OUT_W-1:0]   dut_result;

    conv3x3_filter_unit dut (
        .clk    (clk),
        .rst    (rst),
        .en     (en),
        .acc_clr(acc_clr),
        .d0(dut_d0), .d1(dut_d1), .d2(dut_d2),
        .d3(dut_d3), .d4(dut_d4), .d5(dut_d5),
        .d6(dut_d6), .d7(dut_d7), .d8(dut_d8),
        .w0(dut_w0), .w1(dut_w1), .w2(dut_w2),
        .w3(dut_w3), .w4(dut_w4), .w5(dut_w5),
        .w6(dut_w6), .w7(dut_w7), .w8(dut_w8),
        .bias  (dut_bias),
        .result(dut_result)
    );

    // ---- Temporary parse registers for one test case ----
    // Row 0
    reg [IN_W-1:0]  p_r0d0, p_r0d1, p_r0d2, p_r0d3, p_r0d4,
                    p_r0d5, p_r0d6, p_r0d7, p_r0d8;
    reg [W_W-1:0]   p_r0w0, p_r0w1, p_r0w2, p_r0w3, p_r0w4,
                    p_r0w5, p_r0w6, p_r0w7, p_r0w8;
    // Row 1
    reg [IN_W-1:0]  p_r1d0, p_r1d1, p_r1d2, p_r1d3, p_r1d4,
                    p_r1d5, p_r1d6, p_r1d7, p_r1d8;
    reg [W_W-1:0]   p_r1w0, p_r1w1, p_r1w2, p_r1w3, p_r1w4,
                    p_r1w5, p_r1w6, p_r1w7, p_r1w8;
    // Row 2
    reg [IN_W-1:0]  p_r2d0, p_r2d1, p_r2d2, p_r2d3, p_r2d4,
                    p_r2d5, p_r2d6, p_r2d7, p_r2d8;
    reg [W_W-1:0]   p_r2w0, p_r2w1, p_r2w2, p_r2w3, p_r2w4,
                    p_r2w5, p_r2w6, p_r2w7, p_r2w8;
    // Bias + expected
    reg [BIAS_WD-1:0] p_bias;
    reg [OUT_W-1:0]   p_exp;

    // ---- Counters / file handle ----
    integer fd, r0_scan, r1_scan, r2_scan, r3_scan;
    integer n_vectors, pass_count, fail_count, dump_count;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    reg [8*1024-1:0] line0, line1, line2, line3;
    integer r;

    // ====================================================================
    initial begin
        n_vectors  = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;
        rst        = 1'b1;
        en         = 1'b0;
        acc_clr    = 1'b1;
        dut_d0 = {IN_W{1'b0}}; dut_d1 = {IN_W{1'b0}};
        dut_d2 = {IN_W{1'b0}}; dut_d3 = {IN_W{1'b0}};
        dut_d4 = {IN_W{1'b0}}; dut_d5 = {IN_W{1'b0}};
        dut_d6 = {IN_W{1'b0}}; dut_d7 = {IN_W{1'b0}};
        dut_d8 = {IN_W{1'b0}};
        dut_w0 = {W_W{1'b0}}; dut_w1 = {W_W{1'b0}};
        dut_w2 = {W_W{1'b0}}; dut_w3 = {W_W{1'b0}};
        dut_w4 = {W_W{1'b0}}; dut_w5 = {W_W{1'b0}};
        dut_w6 = {W_W{1'b0}}; dut_w7 = {W_W{1'b0}};
        dut_w8 = {W_W{1'b0}};
        dut_bias = {BIAS_WD{1'b0}};

        $display("=========================================================");
        $display("conv3x3_filter_unit Testbench (Thesis Sec 5.3.2.1)");
        $display("Ch 6.2.5+6.2.8: IN_W=%0d W_W=%0d BIAS_WD=%0d OUT_W=%0d",
                 IN_W, W_W, BIAS_WD, OUT_W);
        $display("=========================================================");

        // ---- Open vector file ----
        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/common/vectors/conv3x3_filter_unit_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/common/vectors/conv3x3_filter_unit_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./conv3x3_filter_unit_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open conv3x3_filter_unit_vectors.hex");
            $display("Hint: pass +VECTORS=/absolute/path/conv3x3_filter_unit_vectors.hex");
            $finish;
        end

        // ---- Reset sequence: 3 cycles ----
        #20;
        @(negedge clk);
        rst = 1'b0;
        en  = 1'b1;
        @(negedge clk);  // one settle cycle

        // ====================================================================
        // Main test loop
        // ====================================================================
        begin : main_loop
            while (!$feof(fd)) begin
                // ---- Read and parse row 0 ----
                r = $fgets(line0, fd);
                if (r == 0) disable main_loop;
                r0_scan = $sscanf(line0,
                    "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                    p_r0d0, p_r0d1, p_r0d2, p_r0d3, p_r0d4,
                    p_r0d5, p_r0d6, p_r0d7, p_r0d8,
                    p_r0w0, p_r0w1, p_r0w2, p_r0w3, p_r0w4,
                    p_r0w5, p_r0w6, p_r0w7, p_r0w8);
                if (r0_scan != 18) begin
                    // comment or blank line -- skip
                end else begin
                    // ---- Read row 1 ----
                    r = $fgets(line1, fd);
                    r1_scan = $sscanf(line1,
                        "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                        p_r1d0, p_r1d1, p_r1d2, p_r1d3, p_r1d4,
                        p_r1d5, p_r1d6, p_r1d7, p_r1d8,
                        p_r1w0, p_r1w1, p_r1w2, p_r1w3, p_r1w4,
                        p_r1w5, p_r1w6, p_r1w7, p_r1w8);

                    // ---- Read row 2 ----
                    r = $fgets(line2, fd);
                    r2_scan = $sscanf(line2,
                        "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                        p_r2d0, p_r2d1, p_r2d2, p_r2d3, p_r2d4,
                        p_r2d5, p_r2d6, p_r2d7, p_r2d8,
                        p_r2w0, p_r2w1, p_r2w2, p_r2w3, p_r2w4,
                        p_r2w5, p_r2w6, p_r2w7, p_r2w8);

                    // ---- Read bias + expected ----
                    r = $fgets(line3, fd);
                    r3_scan = $sscanf(line3, "%h %h", p_bias, p_exp);

                    if (r1_scan == 18 && r2_scan == 18 && r3_scan == 2) begin

                        // ---- Drive: negedge 0 -- row 0 ----
                        @(negedge clk);
                        acc_clr = 1'b1;
                        dut_d0 = $signed(p_r0d0); dut_d1 = $signed(p_r0d1);
                        dut_d2 = $signed(p_r0d2); dut_d3 = $signed(p_r0d3);
                        dut_d4 = $signed(p_r0d4); dut_d5 = $signed(p_r0d5);
                        dut_d6 = $signed(p_r0d6); dut_d7 = $signed(p_r0d7);
                        dut_d8 = $signed(p_r0d8);
                        dut_w0 = $signed(p_r0w0); dut_w1 = $signed(p_r0w1);
                        dut_w2 = $signed(p_r0w2); dut_w3 = $signed(p_r0w3);
                        dut_w4 = $signed(p_r0w4); dut_w5 = $signed(p_r0w5);
                        dut_w6 = $signed(p_r0w6); dut_w7 = $signed(p_r0w7);
                        dut_w8 = $signed(p_r0w8);

                        // ---- Drive: negedge 1 -- row 1, acc_clr=1 ----
                        @(negedge clk);
                        acc_clr = 1'b1;
                        dut_d0 = $signed(p_r1d0); dut_d1 = $signed(p_r1d1);
                        dut_d2 = $signed(p_r1d2); dut_d3 = $signed(p_r1d3);
                        dut_d4 = $signed(p_r1d4); dut_d5 = $signed(p_r1d5);
                        dut_d6 = $signed(p_r1d6); dut_d7 = $signed(p_r1d7);
                        dut_d8 = $signed(p_r1d8);
                        dut_w0 = $signed(p_r1w0); dut_w1 = $signed(p_r1w1);
                        dut_w2 = $signed(p_r1w2); dut_w3 = $signed(p_r1w3);
                        dut_w4 = $signed(p_r1w4); dut_w5 = $signed(p_r1w5);
                        dut_w6 = $signed(p_r1w6); dut_w7 = $signed(p_r1w7);
                        dut_w8 = $signed(p_r1w8);

                        // ---- Drive: negedge 2 -- row 2, acc_clr=0, bias ----
                        @(negedge clk);
                        acc_clr  = 1'b0;
                        dut_d0 = $signed(p_r2d0); dut_d1 = $signed(p_r2d1);
                        dut_d2 = $signed(p_r2d2); dut_d3 = $signed(p_r2d3);
                        dut_d4 = $signed(p_r2d4); dut_d5 = $signed(p_r2d5);
                        dut_d6 = $signed(p_r2d6); dut_d7 = $signed(p_r2d7);
                        dut_d8 = $signed(p_r2d8);
                        dut_w0 = $signed(p_r2w0); dut_w1 = $signed(p_r2w1);
                        dut_w2 = $signed(p_r2w2); dut_w3 = $signed(p_r2w3);
                        dut_w4 = $signed(p_r2w4); dut_w5 = $signed(p_r2w5);
                        dut_w6 = $signed(p_r2w6); dut_w7 = $signed(p_r2w7);
                        dut_w8 = $signed(p_r2w8);
                        dut_bias = $signed(p_bias);

                        // ---- Wait: negedge 3 ----
                        @(negedge clk);

                        // ---- Check: negedge 4 ----
                        @(negedge clk);
                        if (dut_result === $signed(p_exp)) begin
                            pass_count = pass_count + 1;
                        end else begin
                            fail_count = fail_count + 1;
                            if (dump_count < 10) begin
                                $display(
                                  "FAIL #%0d: bias=%0d got=%0d exp=%0d",
                                  n_vectors,
                                  $signed(p_bias), dut_result, $signed(p_exp));
                                dump_count = dump_count + 1;
                            end
                        end
                        n_vectors = n_vectors + 1;
                    end // if all rows parsed
                end // if row0 parsed
            end // while
        end // main_loop

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
// END tb_conv3x3_filter_unit.v
// =============================================================================
