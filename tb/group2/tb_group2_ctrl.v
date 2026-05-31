`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for group2_ctrl (Module 2.10)
// Sequential DW-then-PW: start[0]=DW pulse, start[1]=PW pulse (1-cycle each).
// Tests: FSM stages, loop progression, width/stride, group2_done.

module tb_group2_ctrl;

    reg clk=0; always #5 clk=~clk;
    reg rst=1;

    reg  start_group=0, done_dw=0, done_1x1=0;
    wire [1:0] start, fsm_state;
    wire [5:0] width;
    wire       stride, group2_done;
    wire [4:0] loops;

    group2_ctrl dut(
        .clk(clk),.rst(rst),
        .start_group(start_group),
        .done_dw(done_dw),.done_1x1(done_1x1),
        .start(start),.width(width),.stride(stride),
        .fsm_state(fsm_state),.loops(loops),
        .group2_done(group2_done));

    integer pass_cnt=0, fail_cnt=0, total=0;

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

    task do_reset;
        begin
            rst=1; start_group=0; done_dw=0; done_1x1=0;
            repeat(4) @(posedge clk); rst=0; @(posedge clk);
        end
    endtask

    // Pulse start_group for 1 cycle
    task pulse_start; begin
        @(negedge clk); start_group=1;
        @(negedge clk); start_group=0;
    end endtask

    // Shared done flag — set once before 16-block loop, never reset inside do_block
    reg g_saw_done;

    // Complete one shuffle block. Checks group2_done at EVERY posedge.
    task do_block_inner;
        integer i;
        begin
            // DW phase: check while waiting, then assert done_dw
            for (i=0; i<4; i=i+1) begin @(posedge clk); #1; if (group2_done) g_saw_done=1; end
            @(negedge clk); done_dw = 1;
            @(posedge clk); #1; if (group2_done) g_saw_done=1;
            @(negedge clk); done_dw = 0;

            // PW phase: check while waiting, then assert done_1x1
            for (i=0; i<4; i=i+1) begin @(posedge clk); #1; if (group2_done) g_saw_done=1; end
            @(negedge clk); done_1x1 = 1;
            @(posedge clk); #1; if (group2_done) g_saw_done=1;
            @(negedge clk); done_1x1 = 0;

            // Post-block: give FSM time to advance loops
            for (i=0; i<6; i=i+1) begin @(posedge clk); #1; if (group2_done) g_saw_done=1; end
        end
    endtask

    integer lp;

    initial begin
        $display("=== tb_group2_ctrl ===");
        do_reset;

        // ── Test 1: idle after reset ──────────────────────────────────────────
        @(posedge clk); #1;
        chk(fsm_state, 0, "idle_after_reset");
        chk(loops,     0, "loops_zero");
        chk(group2_done, 0, "no_done_idle");

        // ── Test 2: enters S_S2 after start_group ────────────────────────────
        pulse_start;
        // Check FSM state 1 cycle after start posedge
        @(posedge clk); #1;
        chk(fsm_state, 1, "entered_S2");
        chk(width, 56,    "width_56_S2");
        // stride at loop 0 should be 1 (stride-2 for first block)
        chk(stride, 1,    "stride2_loop0");
        do_reset;

        // ── Test 3: run all 16 blocks and detect group2_done ─────────────────
        pulse_start;
        g_saw_done = 0;
        for (lp=0; lp<16; lp=lp+1)
            do_block_inner;

        // Extra wait in case done fires just after the last block
        repeat(10) begin @(posedge clk); #1; if (group2_done) g_saw_done=1; end

        total=total+1;
        if (g_saw_done) begin
            pass_cnt=pass_cnt+1;
            $display("PASS: group2_done observed after 16 blocks");
        end else begin
            fail_cnt=fail_cnt+1;
            $display("FAIL: group2_done NOT seen after 16 blocks");
        end

        // FSM should return to IDLE
        repeat(3) @(posedge clk); #1;
        chk(fsm_state, 0, "idle_after_all");
        do_reset;

        // ── Test 4: loop counter increments ──────────────────────────────────
        pulse_start;
        chk(loops, 0, "loops_0_start");
        do_block_inner; // complete block 0
        @(posedge clk); #1;
        chk(loops, 1, "loops_1_after_block0");
        do_reset;

        // ── Test 5: width changes at stage boundaries ─────────────────────────
        // Blocks 0-3: Stage 2 (W=56 input), blocks 4-11: Stage 3 (W=28 input)
        pulse_start;
        // Do 4 blocks (Stage 2: loops 0-3)
        for (lp=0; lp<4; lp=lp+1) do_block_inner;
        @(posedge clk); #1;
        chk(fsm_state, 2, "state_S3_at_loop4");
        chk(width, 28,    "width_28_S3");
        do_reset;

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
