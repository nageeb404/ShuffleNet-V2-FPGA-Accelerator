`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for conv1x1_ctrl (Module 2.9, Sec 5.4.7.3)
// step_out is [4:0] (5-bit) supporting N_ACC up to 31.
// Tests: step sequence, acc_clr timing, we pulse, wr_addr, done.

module tb_conv1x1_ctrl;

    reg clk = 0; always #5 clk = ~clk;
    reg rst = 0;
    task do_reset; begin rst=1; repeat(3) @(posedge clk); rst=0; @(posedge clk); end endtask

    // ── DUT 0: W=H=7,  N_ACC=2  (config 0) ───────────────────────────────────
    localparam W0=7, H0=7, N0=2;
    reg  start0 = 0;
    wire en0, acc_clr0, we0, done0, fsm0;
    wire [11:0] wr0; wire [4:0] step0;
    conv1x1_ctrl #(.W(W0),.H(H0),.N_ACC(N0),.AW(12)) dut0(
        .clk(clk),.rst(rst),.start(start0),
        .en(en0),.acc_clr(acc_clr0),.we(we0),.wr_addr(wr0),
        .step_out(step0),.done(done0),.fsm_state(fsm0));

    // ── DUT 1: W=H=14, N_ACC=5  (config 1) ───────────────────────────────────
    localparam W1=14, H1=14, N1=5;
    reg  start1 = 0;
    wire en1, acc_clr1, we1, done1, fsm1;
    wire [11:0] wr1; wire [4:0] step1;
    conv1x1_ctrl #(.W(W1),.H(H1),.N_ACC(N1),.AW(12)) dut1(
        .clk(clk),.rst(rst),.start(start1),
        .en(en1),.acc_clr(acc_clr1),.we(we1),.wr_addr(wr1),
        .step_out(step1),.done(done1),.fsm_state(fsm1));

    // ── DUT 2: W=H=7,  N_ACC=20 (config 5, max) ──────────────────────────────
    localparam W2=7, H2=7, N2=20;
    reg  start2 = 0;
    wire en2, acc_clr2, we2, done2, fsm2;
    wire [11:0] wr2; wire [4:0] step2;
    conv1x1_ctrl #(.W(W2),.H(H2),.N_ACC(N2),.AW(12)) dut2(
        .clk(clk),.rst(rst),.start(start2),
        .en(en2),.acc_clr(acc_clr2),.we(we2),.wr_addr(wr2),
        .step_out(step2),.done(done2),.fsm_state(fsm2));

    integer pass_cnt=0, fail_cnt=0, total=0;

    task chk;
        input [63:0] got; input [63:0] exp; input [255:0] tag;
        begin
            total = total + 1;
            if (got !== exp) begin
                $display("FAIL [%0s]: got=%0d exp=%0d", tag, got, exp);
                fail_cnt = fail_cnt + 1;
            end else pass_cnt = pass_cnt + 1;
        end
    endtask

    // ── Run DUT0: verify step_out 1..N_ACC, acc_clr, we, wr_addr, done ────────
    task test_dut0;
        integer s, pix;
        begin
            @(negedge clk); start0 = 1;
            @(negedge clk); start0 = 0;

            // step_cnt goes 0→1 at first RUNNING posedge.
            // step_out = step_cnt+1 post-update: at iter s, step_cnt=s, step_out=(s<N0)?s+1:0
            for (s = 1; s <= N0; s = s + 1) begin
                @(posedge clk); #1;
                chk(step0,   (s<N0) ? (s+1) : 5'd0, "d0.step");
                chk(we0,     (s==N0)?1'b1:1'b0,      "d0.we");
                chk(acc_clr0,(s<=2) ?1'b1:1'b0,      "d0.acc_clr");
                chk(en0,     1'b1,                    "d0.en");
                chk(wr0,     12'd0,                   "d0.wr_addr_pix0");
            end

            // After we=1: new pixel starts, wr_addr=1
            @(posedge clk); #1;
            chk(wr0, 12'd1, "d0.wr_addr_pix1");
            chk(done0, 1'b0, "d0.no_done_yet");

            // Let it run to completion
            repeat (W0*H0*(N0+1) + 10) @(posedge clk);
            #1; chk(done0, 1'b0, "d0.done_cleared"); // done is 1-cycle pulse, should be gone
            chk(fsm0, 1'b0, "d0.idle_after");

            do_reset;
        end
    endtask

    // ── Run DUT1: verify step_out reaches N_ACC=5 ─────────────────────────────
    task test_dut1;
        integer s;
        begin
            @(negedge clk); start1 = 1;
            @(negedge clk); start1 = 0;
            for (s = 1; s <= N1; s = s + 1) begin
                @(posedge clk); #1;
                chk(step1, (s<N1)?(s+1):5'd0, "d1.step");
            end
            // step_cnt=N1 → next: step_cnt resets 0→1, pix_cnt→1
            @(posedge clk); #1;
            chk(step1, 5'd1, "d1.step_pix1_start"); // step_cnt resets STEP_MAX→0, step_out=0+1=1
            chk(wr1,  12'd1, "d1.wr_addr_pix1");
            do_reset;
        end
    endtask

    // ── Run DUT2: step_out reaches 20 without overflow ────────────────────────
    task test_dut2;
        integer s;
        begin
            @(negedge clk); start2 = 1;
            @(negedge clk); start2 = 0;
            for (s = 1; s <= N2; s = s + 1) begin
                @(posedge clk); #1;
                chk(step2, (s<N2)?(s+1):5'd0, "d2.step");
                chk(we2, (s==N2)?1'b1:1'b0, "d2.we");
            end
            do_reset;
        end
    endtask

    // ── Done detection: DUT0 full run ─────────────────────────────────────────
    task test_dut0_done;
        integer cyc; reg saw_done;
        begin
            saw_done = 0;
            @(negedge clk); start0 = 1;
            @(negedge clk); start0 = 0;
            for (cyc = 0; cyc < W0*H0*(N0+2)+10; cyc = cyc+1) begin
                @(posedge clk); #1;
                if (done0) saw_done = 1;
            end
            chk(saw_done, 1, "d0.done_seen");
            do_reset;
        end
    endtask

    initial begin
        $display("=== tb_conv1x1_ctrl ===");
        do_reset;
        test_dut0;
        test_dut1;
        test_dut2;
        test_dut0_done;

        $display("---------------------------------------------------------");
        $display("Tested %0d checks", total);
        $display("PASS: %0d / %0d", pass_cnt, total);
        $display("FAIL: %0d / %0d", fail_cnt, total);
        if (fail_cnt == 0)
            $display("RESULT: *** ALL TESTS PASSED ***");
        else
            $display("RESULT: *** %0d TESTS FAILED ***", fail_cnt);
        $display("=========================================================");
        $finish;
    end

endmodule
`default_nettype wire
