`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for dw_conv3x3_filter_unit (Module 2.1)
// Ch 6.2.8: G1_FM_W=10 input, G2_DW_WW=15 weights, G2_FM_W=12 output.
// Single-pass DW (no multi-step acc). 1-cycle MAC pipeline.
// Timing: set inputs, wait 1 posedge (MAC latches), wait 1 negedge, check.

module tb_dw_conv3x3_filter_unit;

    localparam DATA_W   = `G1_FM_W;   // 10
    localparam W_W      = `G2_DW_WW;  // 15
    localparam BIAS_WD  = `DATA_W;    // 15
    localparam DROP_LSB = 5;
    localparam OUT_W    = `G2_FM_W;   // 12
    localparam OUT_MAX  = (1<<(OUT_W-1))-1; // 2047
    localparam OUT_MIN  = -(1<<(OUT_W-1));  // -2048

    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;

    reg en = 0;
    reg signed [DATA_W-1:0]  d0,d1,d2,d3,d4,d5,d6,d7,d8;
    reg signed [W_W-1:0]     w0,w1,w2,w3,w4,w5,w6,w7,w8;
    reg signed [BIAS_WD-1:0] bias;
    wire signed [OUT_W-1:0]  result;

    dw_conv3x3_filter_unit dut(
        .clk(clk),.rst(rst),.en(en),
        .d0(d0),.d1(d1),.d2(d2),.d3(d3),.d4(d4),
        .d5(d5),.d6(d6),.d7(d7),.d8(d8),
        .w0(w0),.w1(w1),.w2(w2),.w3(w3),.w4(w4),
        .w5(w5),.w6(w6),.w7(w7),.w8(w8),
        .bias(bias),.result(result));

    integer pass_cnt=0, fail_cnt=0, total=0;

    // Golden model (one-sided: ReLU applied, negative→0)
    function signed [OUT_W-1:0] golden9;
        input signed [DATA_W-1:0]  dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        reg signed [47:0] mac_v, acc_v;
        begin
            mac_v = ($signed(dv) * $signed(wv)) >>> DROP_LSB;
            acc_v = 9 * mac_v + bv;
            if      (acc_v <= 0)       golden9 = {OUT_W{1'b0}};
            else if (acc_v >= OUT_MAX) golden9 = OUT_MAX[OUT_W-1:0];
            else                       golden9 = acc_v[OUT_W-1:0];
        end
    endfunction

    task do_reset;
        begin
            rst=1; en=0;
            repeat(4) @(posedge clk);
            rst=0; @(posedge clk);
        end
    endtask

    task run_test;
        input signed [DATA_W-1:0]  dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        input signed [OUT_W-1:0]   exp;
        begin
            // Drive at negedge 0
            @(negedge clk);
            {d0,d1,d2,d3,d4,d5,d6,d7,d8} = {9{dv}};
            {w0,w1,w2,w3,w4,w5,w6,w7,w8} = {9{wv}};
            bias = bv; en = 1;
            // Posedge 0: MAC latches inputs, mac_out = old value (0 from reset)
            // Negedge 1: MAC output settles
            @(negedge clk);
            // Posedge 1: mac_out = f(d,w); result = quantize(tree + bias)
            @(posedge clk); #1;
            total = total + 1;
            if (result !== exp) begin
                $display("FAIL d=%0d w=%0d b=%0d: got=%0d exp=%0d",
                    $signed(dv),$signed(wv),$signed(bv),
                    $signed(result),$signed(exp));
                fail_cnt = fail_cnt + 1;
            end else pass_cnt = pass_cnt + 1;
            en = 0;
            do_reset;
        end
    endtask

    initial begin
        $display("=== tb_dw_conv3x3_filter_unit ===");
        do_reset;

        // Tests use values producing output within [0, OUT_MAX-1] range
        run_test(0,    0,   0,  0);
        run_test(32,   1,   0,  golden9(32,   1,   0));  // positive
        run_test(1,    32,  0,  golden9(1,    32,  0));  // positive
        run_test(100,  10,  0,  golden9(100,  10,  0));  // positive
        run_test(-100, 10,  0,  golden9(-100, 10,  0));  // negative → 0 (one-sided)
        run_test(-32,   1,  0,  golden9(-32,   1,  0));  // negative → 0
        run_test(50,   20, 100, golden9(50,   20, 100)); // positive with bias
        run_test(10,    5,  0,  golden9(10,    5,  0));  // small positive

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
