// =============================================================================
// tb_conv1x1_g3_core.v -- Smoke test for Module 3.1 (conv1x1_g3_core)
// -----------------------------------------------------------------------------
// / Table 5.9
//
// Ch 6.2.5 + 6.2.8 update: IN_W=12 (G2_FM_W), W_W=9 (G3_PW_WW),
// BIAS_WD=15, BIAS_OUT_W=27 (G3_CONV_OUT_W).
//
// This testbench verifies: compilation, reset, and zero-input -> zero-output.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_conv1x1_g3_core;

    localparam integer N_FILT    = `G3_PW_PAR_FILT;  // 16
    localparam integer N_CHAN    = `G3_PW_PAR_CHAN;   // 29
    localparam integer IN_W      = `G2_FM_W;           // 12 (Ch 6.2.8)
    localparam integer W_W       = `G3_PW_WW;          // 9 (Ch 6.2.5)
    localparam integer BIAS_WD   = `DATA_W;            // 15
    localparam integer BIAS_OUT_W = `G3_CONV_OUT_W;   // 27 (Ch 6.2.5+6.2.8)

    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg en, acc_clr;
    reg signed [IN_W-1:0]       d [0:28];
    reg  [N_FILT*N_CHAN*W_W-1:0]    weights_flat;
    reg  [N_FILT*BIAS_WD-1:0]       biases_flat;
    wire [N_FILT*BIAS_OUT_W-1:0]    results_flat;

    conv1x1_g3_core #(
        .N_FILT     (N_FILT),
        .N_CHAN     (N_CHAN),
        .IN_W      (IN_W),
        .W_W       (W_W),
        .BIAS_WD   (BIAS_WD),
        .BIAS_OUT_W(BIAS_OUT_W)
    ) dut (
        .clk(clk), .rst(rst), .en(en), .acc_clr(acc_clr),
        .d0(d[0]),   .d1(d[1]),   .d2(d[2]),   .d3(d[3]),   .d4(d[4]),
        .d5(d[5]),   .d6(d[6]),   .d7(d[7]),   .d8(d[8]),   .d9(d[9]),
        .d10(d[10]), .d11(d[11]), .d12(d[12]), .d13(d[13]), .d14(d[14]),
        .d15(d[15]), .d16(d[16]), .d17(d[17]), .d18(d[18]), .d19(d[19]),
        .d20(d[20]), .d21(d[21]), .d22(d[22]), .d23(d[23]), .d24(d[24]),
        .d25(d[25]), .d26(d[26]), .d27(d[27]), .d28(d[28]),
        .weights_flat(weights_flat),
        .biases_flat (biases_flat),
        .results_flat(results_flat)
    );

    integer i, pass_count, fail_count;

    task check;
        input integer cond;
        input [8*64-1:0] msg;
        begin
            if (cond) pass_count = pass_count + 1;
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s", msg);
            end
        end
    endtask

    initial begin
        pass_count   = 0; fail_count = 0;
        rst          = 1'b1;
        en           = 1'b0;
        acc_clr      = 1'b0;
        weights_flat = {(N_FILT*N_CHAN*W_W){1'b0}};
        biases_flat  = {(N_FILT*BIAS_WD){1'b0}};
        for (i = 0; i < 29; i = i+1) d[i] = {IN_W{1'b0}};

        $display("=========================================================");
        $display("conv1x1_g3_core Testbench (N_FILT=%0d N_CHAN=%0d)", N_FILT, N_CHAN);
        $display("Ch 6.2.5+6.2.8: IN_W=%0d W_W=%0d BIAS_WD=%0d BIAS_OUT_W=%0d",
                 IN_W, W_W, BIAS_WD, BIAS_OUT_W);
        $display("=========================================================");

        // ---- Test 1: all-zero weights/data -> results = 0 after reset ----
        #20; @(negedge clk); rst = 1'b0;
        @(posedge clk); #1;

        check((results_flat === {(N_FILT*BIAS_OUT_W){1'b0}}),
              "all-zero: results=0 after reset");

        // Run 10 cycles with en=1 acc_clr=1 (all-zero inputs)
        en = 1'b1; acc_clr = 1'b1;
        repeat(10) @(posedge clk);
        #1;
        check((results_flat === {(N_FILT*BIAS_OUT_W){1'b0}}),
              "all-zero inputs: results=0 after 10 en cycles");

        // ---- Test 2: Reset restores zero outputs ----
        @(negedge clk); rst = 1'b1;
        en = 1'b0; acc_clr = 1'b0;
        @(negedge clk); rst = 1'b0;
        @(posedge clk); #1;
        check((results_flat === {(N_FILT*BIAS_OUT_W){1'b0}}),
              "results=0 after second reset");

        // ---- Summary ----
        $display("---------------------------------------------------------");
        $display("Tested %0d checks", pass_count + fail_count);
        $display("PASS: %0d / %0d", pass_count, pass_count + fail_count);
        $display("FAIL: %0d / %0d", fail_count, pass_count + fail_count);
        if (fail_count == 0) $display("RESULT: *** ALL TESTS PASSED ***");
        else                 $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
        $display("=========================================================");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_conv1x1_g3_core.v
// =============================================================================
