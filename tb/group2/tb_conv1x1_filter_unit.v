`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for conv1x1_filter_unit (Module 2.4)
// Ch 6 adaptation: N_CHAN=12 (G2_PW_PAR_CHAN), DATA_W=G2_FM_W=12,
//                  W_W=G2_PW_WW=11, BIAS_WD=G2_BIAS_W=13, OUT_W=G2_FM_W=12.
// Accumulation over N_ACC steps. One-sided output (ReLU via MSB-check in parent).
// Timing per step: drive inputs, posedge (MAC latches), check after pipeline.

module tb_conv1x1_filter_unit;

    localparam N_CHAN   = `G2_PW_PAR_CHAN; // 12
    localparam DATA_W   = `G2_FM_W;        // 12
    localparam W_W      = `G2_PW_WW;       // 11
    localparam BIAS_WD  = `G2_BIAS_W;      // 13
    localparam DROP_LSB = 8;
    localparam OUT_W    = `G2_FM_W;        // 12
    localparam OUT_MAX  = (1<<(OUT_W-1))-1; // 2047

    reg clk=0; always #5 clk=~clk;
    reg rst=1;
    initial begin repeat(3) @(posedge clk); rst=0; end

    reg en=0, acc_clr=0;
    reg signed [DATA_W-1:0] d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11;
    reg signed [W_W-1:0]    w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10,w11;
    reg signed [BIAS_WD-1:0] bias;
    wire signed [OUT_W-1:0]  result;

    conv1x1_filter_unit dut(
        .clk(clk),.rst(rst),.en(en),.acc_clr(acc_clr),
        .d0(d0),.d1(d1),.d2(d2),.d3(d3),
        .d4(d4),.d5(d5),.d6(d6),.d7(d7),
        .d8(d8),.d9(d9),.d10(d10),.d11(d11),
        .w0(w0),.w1(w1),.w2(w2),.w3(w3),
        .w4(w4),.w5(w5),.w6(w6),.w7(w7),
        .w8(w8),.w9(w9),.w10(w10),.w11(w11),
        .bias(bias),.result(result));

    integer pass_cnt=0, fail_cnt=0, total=0;

    // Golden: N_CHAN identical inputs, N_ACC accumulation steps, one-sided
    function signed [OUT_W-1:0] golden;
        input signed [DATA_W-1:0]  dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        input integer nacc;
        reg signed [47:0] mac_v, acc_v;
        begin
            mac_v = ($signed(dv) * $signed(wv)) >>> DROP_LSB;
            acc_v = nacc * (N_CHAN * mac_v) + bv;
            if      (acc_v <= 0)       golden = {OUT_W{1'b0}};
            else if (acc_v >= OUT_MAX) golden = OUT_MAX[OUT_W-1:0];
            else                       golden = acc_v[OUT_W-1:0];
        end
    endfunction

    // Task: run N_ACC accumulation steps then check
    // acc_clr=1 for steps 0 and 1 (pipeline settle), 0 for rest
    task run_test;
        input signed [DATA_W-1:0]  dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        input integer nacc;
        input signed [OUT_W-1:0]   exp;
        integer s;
        begin
            for (s=0; s<=nacc; s=s+1) begin
                @(negedge clk);
                {d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11} = {12{dv}};
                {w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10,w11} = {12{wv}};
                bias=bv; en=1;
                acc_clr = (s<=1) ? 1'b1 : 1'b0;
            end
            // Stop accumulation: en=0 prevents the wait-cycle MAC from adding
            @(negedge clk); en=0; acc_clr=0;
            @(posedge clk); #1;
            total=total+1;
            if (result !== exp) begin
                $display("FAIL d=%0d w=%0d b=%0d nacc=%0d: got=%0d exp=%0d",
                    $signed(dv),$signed(wv),$signed(bv),nacc,$signed(result),$signed(exp));
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
            en=0; acc_clr=0;
            rst=1; repeat(2) @(posedge clk); rst=0; @(posedge clk);
        end
    endtask

    initial begin
        $display("=== tb_conv1x1_filter_unit ===");
        rst=1; repeat(4) @(posedge clk); rst=0; @(posedge clk);

        // N_ACC=2: simplest (config 0)
        run_test(0,    0, 0,    2, 0);
        run_test(256,  1, 0,    2, golden(256, 1, 0, 2));
        run_test(1,  256, 0,    2, golden(1, 256, 0, 2));
        run_test(100, 10, 500,  2, golden(100, 10, 500, 2));

        // N_ACC=5: config 1
        run_test(256,  1, 0,    5, golden(256, 1, 0, 5));

        // N_ACC=10: config 3
        run_test(128,  4, 0,   10, golden(128, 4, 0, 10));

        // Large values (within range)
        run_test(512,  10,   0,    5, golden(512, 10, 0, 5));

        // Negative → 0 (one-sided)
        run_test(-512, 100, 0, 2, golden(-512, 100, 0, 2));

        $display("---------------------------------------------------------");
        $display("PASS: %0d / %0d", pass_cnt, total);
        $display("FAIL: %0d / %0d", fail_cnt, total);
        if (fail_cnt==0) $display("RESULT: *** ALL TESTS PASSED ***");
        else             $display("RESULT: *** %0d TESTS FAILED ***", fail_cnt);
        $display("=========================================================");
        $finish;
    end
endmodule
`default_nettype wire
