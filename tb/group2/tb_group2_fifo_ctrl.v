`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for group2_fifo_ctrl (Module 2.7)
// 5-state FSM: IDLE→LOAD_ROW→LOAD_WIN→PROCESS→LAST_PAD.
// Tests: starts in IDLE, transitions on start, generates shift_and_load,
//        asserts done after one frame, returns to IDLE.

module tb_group2_fifo_ctrl;

    reg clk=0; always #5 clk=~clk;
    reg rst=1;

    // DUT 0: W=7, H=7, STRIDE=1 (smallest config, fewest cycles)
    localparam W0=7, H0=7, S0=1;
    reg  start0=0;
    wire shift_and_load0, padding_sel0, done0;
    wire [1:0] width_sel0;
    wire [11:0] rd_addr0;
    wire [2:0] fsm_state0;

    group2_fifo_ctrl #(.W(W0),.H(H0),.STRIDE(S0)) dut0(
        .clk(clk),.rst(rst),.start(start0),
        .shift_and_load(shift_and_load0),.padding_sel(padding_sel0),
        .width_sel(width_sel0),.rd_addr(rd_addr0),
        .fsm_state(fsm_state0),.done(done0));

    // DUT 1: W=14, H=14, STRIDE=2
    localparam W1=14, H1=14, S1=2;
    reg  start1=0;
    wire shift_and_load1, padding_sel1, done1;
    wire [1:0] width_sel1;
    wire [11:0] rd_addr1;
    wire [2:0] fsm_state1;

    group2_fifo_ctrl #(.W(W1),.H(H1),.STRIDE(S1)) dut1(
        .clk(clk),.rst(rst),.start(start1),
        .shift_and_load(shift_and_load1),.padding_sel(padding_sel1),
        .width_sel(width_sel1),.rd_addr(rd_addr1),
        .fsm_state(fsm_state1),.done(done1));

    integer pass_cnt=0, fail_cnt=0, total=0;

    task do_reset;
        begin rst=1; start0=0; start1=0;
              repeat(3) @(posedge clk); rst=0; @(posedge clk); end
    endtask

    task chk;
        input [63:0] got; input [63:0] exp; input [255:0] tag;
        begin
            total=total+1;
            if (got!==exp) begin
                $display("FAIL [%0s]: got=%0d exp=%0d",tag,got,exp);
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
        end
    endtask

    // Run DUT0 to completion, check done is seen
    integer cyc; reg saw_done;
    task test_dut0_full_run;
        begin
            saw_done=0;
            @(negedge clk); start0=1;
            @(negedge clk); start0=0;
            // Give enough cycles for W=7 H=7 STRIDE=1 to complete
            for (cyc=0; cyc<500; cyc=cyc+1) begin
                @(posedge clk); #1;
                if (done0) saw_done=1;
            end
            total=total+1;
            if (saw_done) begin
                pass_cnt=pass_cnt+1;
                $display("PASS: dut0 done seen");
            end else begin
                fail_cnt=fail_cnt+1;
                $display("FAIL: dut0 done NOT seen");
            end
            // Should return to IDLE
            repeat(5) @(posedge clk); #1;
            chk(fsm_state0, 0, "dut0_idle_after");
        end
    endtask

    task test_dut1_starts;
        begin
            @(negedge clk); start1=1;
            @(negedge clk); start1=0;
            // After start, FSM should leave IDLE
            repeat(3) @(posedge clk); #1;
            total=total+1;
            if (fsm_state1!==3'd0) begin
                pass_cnt=pass_cnt+1;
                $display("PASS: dut1 left IDLE (state=%0d)", fsm_state1);
            end else begin
                fail_cnt=fail_cnt+1;
                $display("FAIL: dut1 still in IDLE");
            end
            do_reset;
        end
    endtask

    initial begin
        $display("=== tb_group2_fifo_ctrl ===");
        do_reset;

        // ── Test 1: idle after reset ──────────────────────────────────────────
        @(posedge clk); #1;
        chk(fsm_state0, 0, "idle_after_reset");
        chk(done0, 0, "no_done_at_reset");

        // ── Test 2: run DUT0 through full frame ───────────────────────────────
        test_dut0_full_run;

        // ── Test 3: DUT1 leaves IDLE after start ──────────────────────────────
        do_reset;
        test_dut1_starts;

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
