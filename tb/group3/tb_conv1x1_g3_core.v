`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for conv1x1_g3_core (Module 3.1)
// N_FILT=16, N_CHAN=29 shared d0..d28 inputs, weights_flat, biases_flat.
// OUT_W=27 (full precision, no quantizer). One-sided output (ReLU applied).

module tb_conv1x1_g3_core;

    localparam N_FILT    = `G3_PW_PAR_FILT;   // 16
    localparam N_CHAN    = `G3_PW_PAR_CHAN;    // 29
    localparam IN_W     = `G2_FM_W;            // 12
    localparam W_W      = `G3_PW_WW;           // 9
    localparam BIAS_WD  = `DATA_W;             // 15
    localparam OUT_W    = `G3_CONV_OUT_W;      // 27
    localparam DROP_LSB = 7;

    reg clk=0; always #5 clk=~clk;
    reg rst=1; reg en=0, acc_clr=0;

    reg signed [IN_W-1:0] d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11,d12,d13,d14,
                           d15,d16,d17,d18,d19,d20,d21,d22,d23,d24,d25,d26,d27,d28;
    reg signed [N_FILT*N_CHAN*W_W-1:0] weights_flat;
    reg signed [N_FILT*BIAS_WD-1:0]   biases_flat;
    wire signed [N_FILT*OUT_W-1:0]    results_flat;

    conv1x1_g3_core dut(
        .clk(clk),.rst(rst),.en(en),.acc_clr(acc_clr),
        .d0(d0),.d1(d1),.d2(d2),.d3(d3),.d4(d4),
        .d5(d5),.d6(d6),.d7(d7),.d8(d8),.d9(d9),
        .d10(d10),.d11(d11),.d12(d12),.d13(d13),.d14(d14),
        .d15(d15),.d16(d16),.d17(d17),.d18(d18),.d19(d19),
        .d20(d20),.d21(d21),.d22(d22),.d23(d23),.d24(d24),
        .d25(d25),.d26(d26),.d27(d27),.d28(d28),
        .weights_flat(weights_flat),
        .biases_flat(biases_flat),
        .results_flat(results_flat));

    integer pass_cnt=0, fail_cnt=0, total=0, f, c, s, nacc;
    reg signed [OUT_W-1:0] v0;

    task do_reset;
        begin rst=1; en=0; acc_clr=0; weights_flat=0; biases_flat=0;
              {d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11,d12,d13,d14,
               d15,d16,d17,d18,d19,d20,d21,d22,d23,d24,d25,d26,d27,d28}=0;
              repeat(4) @(posedge clk); rst=0; @(posedge clk); end
    endtask

    task chk_nonx;
        input [255:0] tag;
        begin
            for (f=0; f<N_FILT; f=f+1) begin
                total=total+1;
                if (^results_flat[f*OUT_W +:OUT_W]===1'bx) begin
                    $display("FAIL [%0s] f=%0d: X",tag,f); fail_cnt=fail_cnt+1;
                end else pass_cnt=pass_cnt+1;
            end
        end
    endtask

    task set_data; input signed [IN_W-1:0] v;
        begin {d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11,d12,d13,d14,
               d15,d16,d17,d18,d19,d20,d21,d22,d23,d24,d25,d26,d27,d28}={29{v}}; end
    endtask

    initial begin
        $display("=== tb_conv1x1_g3_core ===");
        do_reset;

        // Case 0: all zeros
        nacc = 2;
        set_data(0); weights_flat=0; biases_flat=0;
        for (s=0; s<=nacc; s=s+1) begin
            @(negedge clk); en=1; acc_clr=(s<=1)?1'b1:1'b0;
        end
        @(negedge clk); en=0; acc_clr=0;
        @(posedge clk); #1;
        // Check all outputs are 0
        for (f=0; f<N_FILT; f=f+1) begin
            total=total+1;
            if (results_flat[f*OUT_W +:OUT_W]!==0) begin
                $display("FAIL zero f=%0d got=%0d",f,$signed(results_flat[f*OUT_W+:OUT_W]));
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
        end
        do_reset;

        // Case 1: positive inputs — check non-X and all same
        set_data(8); // small positive
        for (f=0; f<N_FILT; f=f+1)
            for (c=0; c<N_CHAN; c=c+1)
                weights_flat[(f*N_CHAN+c)*W_W +:W_W] = 9'sd1;
        biases_flat = 0;
        nacc = 2;
        for (s=0; s<=nacc; s=s+1) begin
            @(negedge clk); en=1; acc_clr=(s<=1)?1'b1:1'b0;
        end
        @(negedge clk); en=0; acc_clr=0;
        @(posedge clk); #1;
        chk_nonx("positive");
        // All 16 filters should produce same value
        v0 = results_flat[0 +:OUT_W];
        for (f=1; f<N_FILT; f=f+1) begin
            total=total+1;
            if (results_flat[f*OUT_W +:OUT_W]!==v0) begin
                $display("FAIL uniform f=%0d differs",f); fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
        end

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
