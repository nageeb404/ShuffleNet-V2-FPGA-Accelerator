`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for maxpool_core (Module 1.4)
// Ch 6.2.8: G1_FM_W=10. 24 channels × 9-window max-of-9.
// Pipeline: data_flat → (comb stage1+2) → [register] → (comb stage3) → results_flat
// Latency: 1 cycle. Drive data at negedge, wait 2 posedges (1 to register, 1 to see output).

module tb_maxpool_core;

    localparam N_CHAN = `G1_POOL_PAR_CHAN; // 24
    localparam DW    = `G1_FM_W;          // 10
    localparam TOTAL = N_CHAN * 9 * DW;   // 2160

    reg clk=0; always #5 clk=~clk;
    reg rst=1;

    reg  en = 1;           // pipeline register enable — keep 1 throughout tests
    reg  [TOTAL-1:0]     data_flat;
    wire [N_CHAN*DW-1:0] results_flat;

    maxpool_core dut(.clk(clk),.rst(rst),.en(en),
                     .data_flat(data_flat),.results_flat(results_flat));

    integer pass_cnt=0, fail_cnt=0, total=0, i, ch;

    task do_reset;
        begin rst=1; data_flat=0;
              repeat(4) @(posedge clk); rst=0;
              // Extra posedge to flush pipeline after reset
              @(posedge clk); @(posedge clk); end
    endtask

    task chk_ch;
        input integer c;
        input [DW-1:0] exp;
        reg [DW-1:0] got;
        begin
            got = results_flat[c*DW +: DW];
            total=total+1;
            if (got!==exp) begin
                $display("FAIL ch=%0d: got=%0d exp=%0d",c,got,exp);
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
        end
    endtask

    // Drive data, wait 2 posedges (pipeline fill + read), then check
    task drive_and_wait;
        begin
            @(negedge clk); // drive at negedge
            @(posedge clk); // pipeline registers new data
            @(posedge clk); #1; // output now valid
        end
    endtask

    initial begin
        $display("=== tb_maxpool_core ===");
        do_reset;

        // ── Case 0: all zeros ─────────────────────────────────────────────────
        data_flat = {TOTAL{1'b0}};
        drive_and_wait;
        for (i=0; i<N_CHAN; i=i+1) chk_ch(i, 10'd0);

        // ── Case 1: all channels all-100 → max=100 ────────────────────────────
        data_flat = {TOTAL{1'b0}};
        for (ch=0; ch<N_CHAN; ch=ch+1)
            for (i=0; i<9; i=i+1)
                data_flat[(ch*9+i)*DW +: DW] = 10'd100;
        drive_and_wait;
        for (i=0; i<N_CHAN; i=i+1) chk_ch(i, 10'd100);

        // ── Case 2: ch 0 has max=511 at tap 4, all other channels = 0 ─────────
        data_flat = {TOTAL{1'b0}};
        data_flat[0*DW +: DW] = 10'd10;
        data_flat[1*DW +: DW] = 10'd20;
        data_flat[2*DW +: DW] = 10'd30;
        data_flat[3*DW +: DW] = 10'd40;
        data_flat[4*DW +: DW] = 10'd511;
        data_flat[5*DW +: DW] = 10'd60;
        data_flat[6*DW +: DW] = 10'd70;
        data_flat[7*DW +: DW] = 10'd80;
        data_flat[8*DW +: DW] = 10'd90;
        drive_and_wait;
        chk_ch(0, 10'd511);
        for (i=1; i<N_CHAN; i=i+1) chk_ch(i, 10'd0);

        // ── Case 3: ch 5 max=200, ch 10 max=350 ──────────────────────────────
        data_flat = {TOTAL{1'b0}};
        data_flat[(5*9+0)*DW +: DW] = 10'd200;
        data_flat[(10*9+8)*DW +: DW] = 10'd350;
        drive_and_wait;
        chk_ch(5,  10'd200);
        chk_ch(10, 10'd350);
        chk_ch(0,  10'd0);

        // ── Case 4: ch 23 windows 1..9 → max=9 ───────────────────────────────
        data_flat = {TOTAL{1'b0}};
        for (i=0; i<9; i=i+1)
            data_flat[(23*9+i)*DW +: DW] = i+1;
        drive_and_wait;
        chk_ch(23, 10'd9);

        // ── Case 5: each channel max = ch+1 at different taps ─────────────────
        data_flat = {TOTAL{1'b0}};
        for (ch=0; ch<N_CHAN; ch=ch+1)
            data_flat[(ch*9 + (ch%9))*DW +: DW] = ch+1;
        drive_and_wait;
        for (ch=0; ch<N_CHAN; ch=ch+1) chk_ch(ch, ch+1);

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
