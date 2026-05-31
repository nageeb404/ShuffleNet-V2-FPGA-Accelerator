`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for conv1x1_core (Module 2.5)
// N_CHAN=12 shared data inputs (d0..d11), 58 filter-specific weights+biases.
// nacc steps + wait step (accumulator not gated on en → nacc+1 effective).

module tb_conv1x1_core;

    localparam N_FILT  = `G2_PW_PAR_FILT;  // 58
    localparam N_CHAN  = `G2_PW_PAR_CHAN;   // 12
    localparam IN_W    = `G2_FM_W;          // 12
    localparam W_W     = `G2_PW_WW;         // 11
    localparam BIAS_WD = `G2_BIAS_W;        // 13
    localparam OUT_W   = `G2_FM_W;          // 12
    localparam DROP_LSB = 8;
    localparam OUT_MAX = (1<<(OUT_W-1))-1;  // 2047

    reg clk=0; always #5 clk=~clk;
    reg rst=1; reg en=0, acc_clr=0;

    // 12 shared data inputs
    reg signed [IN_W-1:0] d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11;
    // 58×12 weights and 58 biases (flat buses)
    reg signed [N_FILT*N_CHAN*W_W-1:0] weights_flat;
    reg signed [N_FILT*BIAS_WD-1:0]   biases_flat;
    wire signed [N_FILT*OUT_W-1:0]    results_flat;

    conv1x1_core dut(
        .clk(clk),.rst(rst),.en(en),.acc_clr(acc_clr),
        .d0(d0),.d1(d1),.d2(d2),.d3(d3),
        .d4(d4),.d5(d5),.d6(d6),.d7(d7),
        .d8(d8),.d9(d9),.d10(d10),.d11(d11),
        .weights_flat(weights_flat),
        .biases_flat(biases_flat),
        .results_flat(results_flat));

    integer pass_cnt=0, fail_cnt=0, total=0, f, c, s;

    task do_reset;
        begin rst=1; en=0; acc_clr=0;
              {d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11}=0;
              weights_flat=0; biases_flat=0;
              repeat(4) @(posedge clk); rst=0; @(posedge clk); end
    endtask

    // Golden: (nacc+1) accumulations, one-sided output
    function signed [OUT_W-1:0] golden;
        input signed [IN_W-1:0]   dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        input integer nacc;
        reg signed [47:0] mac_v, acc_v;
        begin
            mac_v = ($signed(dv)*$signed(wv)) >>> DROP_LSB;
            // conv1x1_filter_unit acc IS gated on en → nacc accumulations (not nacc+1)
            acc_v = nacc * (N_CHAN * mac_v) + bv;
            if      (acc_v<=0)       golden={OUT_W{1'b0}};
            else if (acc_v>=OUT_MAX) golden=OUT_MAX[OUT_W-1:0];
            else                     golden=acc_v[OUT_W-1:0];
        end
    endfunction

    task chk_all;
        input signed [OUT_W-1:0] exp;
        begin
            for (f=0; f<N_FILT; f=f+1) begin
                total=total+1;
                if (results_flat[f*OUT_W +:OUT_W]!==exp) begin
                    $display("FAIL f=%0d got=%0d exp=%0d",
                        f,$signed(results_flat[f*OUT_W+:OUT_W]),$signed(exp));
                    fail_cnt=fail_cnt+1;
                end else pass_cnt=pass_cnt+1;
            end
        end
    endtask

    task run_test;
        input signed [IN_W-1:0]   dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        input integer nacc;
        input signed [OUT_W-1:0]   exp;
        begin
            // Set data inputs
            {d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11} = {12{dv}};
            // Set all 58 filters to same weight/bias
            for (f=0; f<N_FILT; f=f+1) begin
                for (c=0; c<N_CHAN; c=c+1)
                    weights_flat[(f*N_CHAN+c)*W_W +:W_W] = wv;
                biases_flat[f*BIAS_WD +:BIAS_WD] = bv;
            end
            for (s=0; s<=nacc; s=s+1) begin
                @(negedge clk); en=1; acc_clr=(s<=1)?1'b1:1'b0;
            end
            @(negedge clk); en=0; acc_clr=0;
            @(posedge clk); #1;
            chk_all(exp);
            en=0; acc_clr=0; do_reset;
        end
    endtask

    initial begin
        $display("=== tb_conv1x1_core ===");
        do_reset;
        run_test(  0,  0, 0, 2, 0);
        run_test(256,  1, 0, 2, golden(256, 1, 0, 2));
        run_test(  1,256, 0, 2, golden(1, 256, 0, 2));
        run_test(-64, 10, 0, 2, golden(-64, 10, 0, 2)); // negative → 0
        run_test( 16,  1, 0, 4, golden(16,  1, 0, 4));

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
