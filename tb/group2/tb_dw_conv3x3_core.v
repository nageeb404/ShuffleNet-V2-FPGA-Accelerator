`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for dw_conv3x3_core (Module 2.2)
// 58 DW filters, each with own 9 data taps. Single-pass, no accumulation.
// Uses replication to set flat buses. Multiple drive cycles to settle pipeline.

module tb_dw_conv3x3_core;

    localparam N_FILT  = `G2_DW_PAR_FILT;  // 58
    localparam IN_W    = `G1_FM_W;           // 10
    localparam W_W     = `G2_DW_WW;          // 15
    localparam BIAS_WD = `DATA_W;            // 15
    localparam OUT_W   = `G2_FM_W;           // 12
    localparam DROP_LSB = 5;

    reg clk=0; always #5 clk=~clk;
    reg rst=1; reg en=0;

    reg signed [N_FILT*9*IN_W-1:0]   data_flat;
    reg signed [N_FILT*9*W_W-1:0]    weights_flat;
    reg signed [N_FILT*BIAS_WD-1:0]  biases_flat;
    wire signed [N_FILT*OUT_W-1:0]   results_flat;

    dw_conv3x3_core dut(
        .clk(clk),.rst(rst),.en(en),
        .data_flat(data_flat),.weights_flat(weights_flat),
        .biases_flat(biases_flat),.results_flat(results_flat));

    integer pass_cnt=0, fail_cnt=0, total=0, f;

    task do_reset;
        begin rst=1; en=0; data_flat=0; weights_flat=0; biases_flat=0;
              repeat(5) @(posedge clk); rst=0; repeat(2) @(posedge clk); end
    endtask

    // Set all 58 filters to same value using replication
    task set_all;
        input signed [IN_W-1:0]   dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        integer j;
        begin
            // Replicate dv across all 58*9 = 522 data slots
            for (j=0; j < N_FILT*9; j=j+1)
                data_flat[j*IN_W +:IN_W] = dv;
            for (j=0; j < N_FILT*9; j=j+1)
                weights_flat[j*W_W +:W_W] = wv;
            for (j=0; j < N_FILT; j=j+1)
                biases_flat[j*BIAS_WD +:BIAS_WD] = bv;
        end
    endtask

    // Golden: single-pass DW (no acc), one-sided output
    function signed [OUT_W-1:0] golden;
        input signed [IN_W-1:0]   dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        reg signed [47:0] mac_v, acc_v;
        begin
            mac_v = ($signed(dv)*$signed(wv)) >>> DROP_LSB;
            acc_v = 9*mac_v + bv;
            if      (acc_v<=0)                golden={OUT_W{1'b0}};
            else if (acc_v>=(1<<(OUT_W-1))-1) golden=((1<<(OUT_W-1))-1);
            else                              golden=acc_v[OUT_W-1:0];
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
        input signed [OUT_W-1:0]   exp;
        begin
            set_all(dv, wv, bv);
            // Drive for 3 cycles to pump the MAC pipeline
            en=1;
            repeat(3) @(posedge clk);
            en=0; @(posedge clk); #1;
            chk_all(exp);
            en=0; do_reset;
        end
    endtask

    initial begin
        $display("=== tb_dw_conv3x3_core ===");
        do_reset;
        run_test(  0,  0,  0, 0);
        run_test( 32,  1,  0, golden(32,  1,  0));
        run_test(  1, 32,  0, golden(1,  32,  0));
        run_test(100, 10,  0, golden(100, 10,  0));
        run_test(-50,100,  0, golden(-50,100,  0)); // negative → 0 (one-sided)
        run_test( 50, 20,100, golden(50,  20,100));

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
