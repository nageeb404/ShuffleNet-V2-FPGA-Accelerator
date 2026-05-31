`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for conv3x3_filter_unit (Module 1.3a)
// Ch 6.2.5/6.2.8: PHOTO_W=8 data, G1_CONV_WW=12 weights, G1_FM_W=10 output.
// Timing per case: row0(acc_clr=1) → row1(acc_clr=1) → row2(acc_clr=0) → wait → check.

module tb_conv3x3_filter_unit;

    localparam DATA_W   = `PHOTO_W;
    localparam W_W      = `G1_CONV_WW;
    localparam BIAS_WD  = `DATA_W;
    localparam DROP_LSB = 5;
    localparam OUT_W    = `G1_FM_W;
    localparam OUT_MAX  = (1 << (OUT_W-1)) - 1; // 511

    reg clk=0; always #5 clk=~clk;
    reg rst=1;
    reg en=0, acc_clr=0;
    reg signed [DATA_W-1:0]  d0,d1,d2,d3,d4,d5,d6,d7,d8;
    reg signed [W_W-1:0]     w0,w1,w2,w3,w4,w5,w6,w7,w8;
    reg signed [BIAS_WD-1:0] bias;
    wire signed [OUT_W-1:0]  result;

    conv3x3_filter_unit dut(
        .clk(clk),.rst(rst),.en(en),.acc_clr(acc_clr),
        .d0(d0),.d1(d1),.d2(d2),.d3(d3),.d4(d4),
        .d5(d5),.d6(d6),.d7(d7),.d8(d8),
        .w0(w0),.w1(w1),.w2(w2),.w3(w3),.w4(w4),
        .w5(w5),.w6(w6),.w7(w7),.w8(w8),
        .bias(bias),.result(result));

    integer pass_cnt=0, fail_cnt=0, total=0;

    // Golden model: 9 identical taps, 3 acc rows (one-sided/ReLU output)
    function signed [OUT_W-1:0] golden9;
        input signed [DATA_W-1:0]  dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        reg signed [47:0] mac_v, acc_v;
        begin
            mac_v = ($signed(dv) * $signed(wv)) >>> DROP_LSB;
            acc_v = 3 * (9 * mac_v) + bv;
            if      (acc_v <= 0)        golden9 = {OUT_W{1'b0}};
            else if (acc_v >= OUT_MAX)  golden9 = OUT_MAX[OUT_W-1:0];
            else                        golden9 = acc_v[OUT_W-1:0];
        end
    endfunction

    task do_reset;
        begin rst=1; repeat(3) @(posedge clk); rst=0; @(posedge clk); end
    endtask

    task run_test;
        input signed [DATA_W-1:0]  dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        input signed [OUT_W-1:0]   exp;
        begin
            @(negedge clk);
            {d0,d1,d2,d3,d4,d5,d6,d7,d8} = {9{dv}};
            {w0,w1,w2,w3,w4,w5,w6,w7,w8} = {9{wv}};
            bias=bv; en=1; acc_clr=1;           // row 0
            @(negedge clk); acc_clr=1;           // row 1
            @(negedge clk); acc_clr=0;           // row 2
            @(negedge clk);                      // wait
            @(posedge clk); #1;
            total = total + 1;
            if (result !== exp) begin
                $display("FAIL d=%0d w=%0d b=%0d: got=%0d exp=%0d",
                    $signed(dv),$signed(wv),$signed(bv),$signed(result),$signed(exp));
                fail_cnt = fail_cnt + 1;
            end else pass_cnt = pass_cnt + 1;
            en=0; acc_clr=0; do_reset;
        end
    endtask

    initial begin
        $display("=== tb_conv3x3_filter_unit ===");
        do_reset;
        // Tests use in-range values only (acc_v < OUT_MAX=511)
        run_test(  0,    0,    0,  0);
        run_test( 32,    1,    0, 27);   // MAC=1, tree=9, acc=27
        run_test(  1,   32,    0, 27);   // same
        run_test( 32,    4,    0, golden9(32,4,0));     // acc=108
        run_test(  4,   32,    0, golden9(4,32,0));     // same
        run_test(-64,  100,    0, golden9(-64,100,0));  // negative → 0 (one-sided)
        run_test(-32,    1,    0, golden9(-32,1,0));    // negative → 0
        run_test(  8,    4,  100, golden9(8,4,100));    // acc with bias

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
