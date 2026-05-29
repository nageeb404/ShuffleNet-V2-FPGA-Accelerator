// =============================================================================
// tb_dw_conv3x3_filter_unit.v -- Self-checking testbench for Module 2.1
// -----------------------------------------------------------------------------
// / Figure 5.17
//
// Ch 6.2.5 + 6.2.8 update: data=IN_W=10 (G1_FM_W), weights=W_W=15 (G2_DW_WW),
// bias=BIAS_WD=15 (DATA_W), result=OUT_W=12 (G2_FM_W).
// Vector file must be regenerated in new bit widths.
//
// Vector file format (2 lines per test case):
// Line 1: d0..d8 w0..w8 (9 x IN_W-bit + 9 x W_W-bit hex values)
// Line 2: bias expected (BIAS_WD-bit bias, OUT_W-bit expected)
//
// Pipeline timing (per test case):
// negedge 0: drive d0..d8, w0..w8, en=1 [posedge 0: MAC latches]
// negedge 1: drive bias
// negedge 2: CHECK result
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_dw_conv3x3_filter_unit;

    localparam integer IN_W    = `G1_FM_W;  // 10 (Ch 6.2.8: maxpool output)
    localparam integer W_W     = `G2_DW_WW; // 15 (unchanged)
    localparam integer BIAS_WD = `DATA_W;   // 15
    localparam integer OUT_W   = `G2_FM_W;  // 12 (Ch 6.2.8: DW conv output)

    // ---- Clock / reset ----
    reg clk, rst, en;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- DUT ports ----
    reg signed [IN_W-1:0]    dut_d0, dut_d1, dut_d2, dut_d3, dut_d4,
                              dut_d5, dut_d6, dut_d7, dut_d8;
    reg signed [W_W-1:0]     dut_w0, dut_w1, dut_w2, dut_w3, dut_w4,
                              dut_w5, dut_w6, dut_w7, dut_w8;
    reg  signed [BIAS_WD-1:0] dut_bias;
    wire signed [OUT_W-1:0]   dut_result;

    dw_conv3x3_filter_unit dut (
        .clk (clk),
        .rst (rst),
        .en  (en),
        .d0(dut_d0), .d1(dut_d1), .d2(dut_d2),
        .d3(dut_d3), .d4(dut_d4), .d5(dut_d5),
        .d6(dut_d6), .d7(dut_d7), .d8(dut_d8),
        .w0(dut_w0), .w1(dut_w1), .w2(dut_w2),
        .w3(dut_w3), .w4(dut_w4), .w5(dut_w5),
        .w6(dut_w6), .w7(dut_w7), .w8(dut_w8),
        .bias  (dut_bias),
        .result(dut_result)
    );

    // ---- Parse temporaries ----
    reg [IN_W-1:0]    p_d0, p_d1, p_d2, p_d3, p_d4,
                      p_d5, p_d6, p_d7, p_d8;
    reg [W_W-1:0]     p_w0, p_w1, p_w2, p_w3, p_w4,
                      p_w5, p_w6, p_w7, p_w8;
    reg [BIAS_WD-1:0] p_bias;
    reg [OUT_W-1:0]   p_exp;

    // ---- File / counters ----
    integer fd, scan1, scan2;
    integer n_vectors, pass_count, fail_count, dump_count;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    reg [8*1024-1:0] line1, line2;
    integer r;

    // ====================================================================
    initial begin
        n_vectors  = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;
        rst = 1'b1;
        en  = 1'b0;
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
        $display("dw_conv3x3_filter_unit Testbench");
        $display("Ch 6.2.5+6.2.8: IN_W=%0d W_W=%0d BIAS_WD=%0d OUT_W=%0d",
                 IN_W, W_W, BIAS_WD, OUT_W);
        $display("=========================================================");

        // ---- Open vector file ----
        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/group2/vectors/dw_conv3x3_filter_unit_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/group2/vectors/dw_conv3x3_filter_unit_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./dw_conv3x3_filter_unit_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open dw_conv3x3_filter_unit_vectors.hex");
            $display("Hint: pass +VECTORS=/absolute/path/dw_conv3x3_filter_unit_vectors.hex");
            $finish;
        end

        // ---- Reset: 2 cycles ----
        #20;
        @(negedge clk);
        rst = 1'b0;
        en  = 1'b1;
        @(negedge clk);   // one settle cycle

        // ====================================================================
        // Main test loop -- read 2 lines per case
        // ====================================================================
        begin : main_loop
            while (!$feof(fd)) begin
                // ---- Line 1: d0..d8 w0..w8 ----
                r = $fgets(line1, fd);
                if (r == 0) disable main_loop;
                scan1 = $sscanf(line1,
                    "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                    p_d0, p_d1, p_d2, p_d3, p_d4,
                    p_d5, p_d6, p_d7, p_d8,
                    p_w0, p_w1, p_w2, p_w3, p_w4,
                    p_w5, p_w6, p_w7, p_w8);
                if (scan1 != 18) begin
                    // comment or blank line -- skip
                end else begin
                    // ---- Line 2: bias expected ----
                    r = $fgets(line2, fd);
                    scan2 = $sscanf(line2, "%h %h", p_bias, p_exp);

                    if (scan2 == 2) begin
                        // ---- negedge 0: drive data + weights ----
                        @(negedge clk);
                        dut_d0 = $signed(p_d0); dut_d1 = $signed(p_d1);
                        dut_d2 = $signed(p_d2); dut_d3 = $signed(p_d3);
                        dut_d4 = $signed(p_d4); dut_d5 = $signed(p_d5);
                        dut_d6 = $signed(p_d6); dut_d7 = $signed(p_d7);
                        dut_d8 = $signed(p_d8);
                        dut_w0 = $signed(p_w0); dut_w1 = $signed(p_w1);
                        dut_w2 = $signed(p_w2); dut_w3 = $signed(p_w3);
                        dut_w4 = $signed(p_w4); dut_w5 = $signed(p_w5);
                        dut_w6 = $signed(p_w6); dut_w7 = $signed(p_w7);
                        dut_w8 = $signed(p_w8);

                        // ---- negedge 1: drive bias ----
                        @(negedge clk);
                        dut_bias = $signed(p_bias);

                        // ---- negedge 2: CHECK result ----
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
                    end // scan2==2
                end // scan1==18
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
// END tb_dw_conv3x3_filter_unit.v
// =============================================================================
