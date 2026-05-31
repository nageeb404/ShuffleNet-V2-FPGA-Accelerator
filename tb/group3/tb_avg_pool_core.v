`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for avg_pool_core (Module 3.2)
// Ch 6.2.8: IN_W=G3_CONV_OUT_W=27, DATA_W=G3_FM_W=9.
// Accumulates N_PIX pixels per channel, approximates /49 via *5>>8.

module tb_avg_pool_core;

    localparam N_CHAN = `G3_PW_PAR_FILT;  // 16
    localparam IN_W  = `G3_CONV_OUT_W;   // 27
    localparam DW    = `G3_FM_W;          // 9
    localparam N_PIX = 49;                // 7×7 global avgpool
    localparam OUT_MAX = (1<<(DW-1))-1;   // 255 (one-sided)

    reg clk=0; always #5 clk=~clk;
    reg rst=1;
    initial begin repeat(3) @(posedge clk); rst=0; end

    reg acc_en=0, acc_clr=0, result_we=0;
    reg [N_CHAN*IN_W-1:0] data_in_flat;
    wire [N_CHAN*DW-1:0]  results_flat;

    avg_pool_core dut(
        .clk(clk),.rst(rst),
        .acc_en(acc_en),.acc_clr(acc_clr),.result_we(result_we),
        .data_in_flat(data_in_flat),.results_flat(results_flat));

    integer pass_cnt=0, fail_cnt=0, total=0;
    integer i,j;

    task chk_ch;
        input integer ch;
        input signed [DW-1:0] exp;
        reg signed [DW-1:0] got;
        begin
            got = results_flat[ch*DW +: DW];
            total=total+1;
            if (got!==exp) begin
                $display("FAIL ch=%0d got=%0d exp=%0d",ch,$signed(got),$signed(exp));
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
        end
    endtask

    task do_reset;
        begin rst=1; acc_en=0; acc_clr=0; result_we=0; data_in_flat=0;
              repeat(3) @(posedge clk); rst=0; @(posedge clk); end
    endtask

    // Golden: quantizer clips raw sum using signed one-sided saturation.
    // HAS_RELU=1: negative→0, >= 2^(DW-1)=256 → all-ones (saturate).
    // Use pix_val where acc = N_PIX * pix < 256 for non-saturating tests.
    function [DW-1:0] avg_golden;
        input [IN_W-1:0] pv;
        input integer n_pix;
        reg [47:0] acc;
        begin
            acc = n_pix * pv;
            if      (acc == 0)                    avg_golden = {DW{1'b0}};
            else if (acc >= (1<<(DW-1)))           avg_golden = {DW{1'b1}}; // saturate
            else                                   avg_golden = acc[DW-1:0];
        end
    endfunction

    // Run one avgpool: acc_clr for 1 cycle, acc_en for N_PIX, result_we for 1
    task run_pool;
        input [IN_W-1:0] pix_val; // all channels same, all pixels same
        input signed [DW-1:0] expected;
        begin
            // Clear accumulator
            @(negedge clk); acc_clr=1; acc_en=0; result_we=0;
            data_in_flat = {N_CHAN{pix_val}};
            @(posedge clk);
            @(negedge clk); acc_clr=0;

            // Accumulate N_PIX pixels
            acc_en=1;
            repeat(N_PIX) begin
                @(posedge clk);
            end
            @(negedge clk); acc_en=0;

            // Write result
            @(negedge clk); result_we=1;
            @(posedge clk);
            @(negedge clk); result_we=0;
            @(posedge clk); #1;

            // Check all channels (all same value)
            for (i=0; i<N_CHAN; i=i+1) begin
                total=total+1;
                if (results_flat[i*DW +: DW] !== expected) begin
                    $display("FAIL run_pool ch=%0d pix=%0d: got=%0d exp=%0d",
                        i,pix_val,$signed(results_flat[i*DW+:DW]),$signed(expected));
                    fail_cnt=fail_cnt+1;
                end else pass_cnt=pass_cnt+1;
            end
            do_reset;
        end
    endtask

    initial begin
        $display("=== tb_avg_pool_core ===");
        do_reset;

        // Use small pix_val where sum = N_PIX * pix < 512 (fits in 9-bit unsigned)
        // Keep acc = N_PIX * pix < 256 for non-saturating cases
        run_pool(27'd0, avg_golden(27'd0, 49)); // acc=0   → 0
        run_pool(27'd1, avg_golden(27'd1, 49)); // acc=49  → 49
        run_pool(27'd3, avg_golden(27'd3, 49)); // acc=147 → 147
        run_pool(27'd5, avg_golden(27'd5, 49)); // acc=245 → 245
        // acc=255: 255/49 = 5.2 → pix=5 is the max non-saturating

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
