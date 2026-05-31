`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for conv3x3_core (Module 1.3b)
// Ch 6.2.5/6.2.8: PHOTO_W=8 data, G1_CONV_WW=12 weights, G1_FM_W=10 outputs.
// All 24 filters share the same 9 pixel inputs. Each filter has own weights/bias.
// Timing: same as filter_unit — 3 drive rows (acc_clr=1,1,0) + wait + check.

module tb_conv3x3_core;

    localparam N_FILT  = `G1_CONV_PAR_FILT; // 24
    localparam DATA_W  = `PHOTO_W;          // 8
    localparam W_W     = `G1_CONV_WW;      // 12
    localparam BIAS_WD = `DATA_W;          // 15
    localparam OUT_W   = `G1_FM_W;         // 10
    localparam DROP_LSB = 5;

    reg clk=0; always #5 clk=~clk;
    reg rst=1; reg en=0, acc_clr=0;

    // 9 shared pixel inputs (all filters get same window)
    reg signed [DATA_W-1:0]  d0,d1,d2,d3,d4,d5,d6,d7,d8;
    // 24×9 weight inputs and 24 bias inputs (all set uniformly in tests)
    reg signed [N_FILT*9*W_W-1:0]     weights_flat;
    reg signed [N_FILT*BIAS_WD-1:0]   biases_flat;
    wire signed [N_FILT*OUT_W-1:0]    results_flat;

    conv3x3_core dut(
        .clk(clk),.rst(rst),.en(en),.acc_clr(acc_clr),
        .d0(d0),.d1(d1),.d2(d2),.d3(d3),.d4(d4),
        .d5(d5),.d6(d6),.d7(d7),.d8(d8),
        .weights_flat(weights_flat),.biases_flat(biases_flat),
        .results_flat(results_flat));

    integer pass_cnt=0, fail_cnt=0, total=0, i;

    task do_reset;
        begin rst=1; en=0; acc_clr=0; weights_flat=0; biases_flat=0;
              repeat(4) @(posedge clk); rst=0; @(posedge clk); end
    endtask

    // Check all 24 filter outputs equal expected value
    task chk_all;
        input signed [OUT_W-1:0] exp;
        input [255:0] tag;
        integer f;
        begin
            for (f=0; f<N_FILT; f=f+1) begin
                total=total+1;
                if (results_flat[f*OUT_W +: OUT_W] !== exp) begin
                    $display("FAIL [%0s] filter=%0d: got=%0d exp=%0d",
                        tag,f,$signed(results_flat[f*OUT_W+:OUT_W]),$signed(exp));
                    fail_cnt=fail_cnt+1;
                end else pass_cnt=pass_cnt+1;
            end
        end
    endtask

    // Run one test: all filters same weight/bias, all pixels same
    task run_test;
        input signed [DATA_W-1:0]  dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        input signed [OUT_W-1:0]   exp;
        integer f, t;
        begin
            // Set all 24 filters to same weight
            for (f=0; f<N_FILT; f=f+1)
                for (t=0; t<9; t=t+1)
                    weights_flat[(f*9+t)*W_W +: W_W] = wv;
            for (f=0; f<N_FILT; f=f+1)
                biases_flat[f*BIAS_WD +: BIAS_WD] = bv;

            @(negedge clk);
            {d0,d1,d2,d3,d4,d5,d6,d7,d8} = {9{dv}};
            en=1; acc_clr=1;            // row 0
            @(negedge clk); acc_clr=1; // row 1
            @(negedge clk); acc_clr=0; // row 2
            @(negedge clk);            // wait
            @(posedge clk); #1;
            chk_all(exp, "run_test");
            en=0; acc_clr=0; do_reset;
        end
    endtask

    initial begin
        $display("=== tb_conv3x3_core ===");
        do_reset;

        run_test(0,   0, 0,   0);   // all zeros
        run_test(32,  1, 0,  27);   // MAC=1, tree=9, acc=27
        run_test(1,  32, 0,  27);   // symmetric
        run_test(32,  4, 0, 108);   // MAC=4, tree=36, acc=108
        run_test(-64, 100, 0,  0);  // negative → 0 (one-sided)

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
