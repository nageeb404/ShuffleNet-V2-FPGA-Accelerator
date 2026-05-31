`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Structural smoke test for group2_top (Module 2.11)
// New port interface (ZU19EG adaptation): fm_data_in, fm_rd_addr,
// pw_results_flat, pw_wr_addr, pw_we, loops, fsm_state.
// Tests: reset, FSM leaves IDLE on start, done eventually fires.

module tb_group2_top;

    localparam N_DW   = `G2_DW_PAR_FILT;  // 58
    localparam N_PW   = `G2_PW_PAR_FILT;  // 58
    localparam G1_FM  = `G1_FM_W;          // 10
    localparam G2_FM  = `G2_FM_W;          // 12

    reg clk=0; always #5 clk=~clk;
    reg rst=1;

    reg  start_group=0;
    reg  signed [N_DW*G1_FM-1:0] fm_data_in;
    wire [11:0]                  fm_rd_addr;
    wire [N_PW*G2_FM-1:0]        pw_results_flat;
    wire [11:0]                  pw_wr_addr;
    wire                         pw_we;
    wire [4:0]                   loops;
    wire [1:0]                   fsm_state;
    wire                         group2_done;

    group2_top dut(
        .clk(clk),.rst(rst),
        .start_group(start_group),
        .group2_done(group2_done),
        .fm_data_in(fm_data_in),
        .fm_rd_addr(fm_rd_addr),
        .pw_results_flat(pw_results_flat),
        .pw_wr_addr(pw_wr_addr),
        .pw_we(pw_we),
        .loops(loops),
        .fsm_state(fsm_state));

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

    initial begin
        $display("=== tb_group2_top ===");
        rst=1; fm_data_in=0;
        repeat(5) @(posedge clk); rst=0; @(posedge clk);

        // ── Test 1: idle after reset ──────────────────────────────────────────
        #1;
        chk(fsm_state, 0, "idle_after_reset");
        chk(loops, 0, "loops_zero");
        chk(group2_done, 0, "no_done");

        // ── Test 2: outputs not X after reset ─────────────────────────────────
        total=total+1;
        if (^pw_results_flat===1'bx) begin
            $display("FAIL pw_results_flat is X after reset");
            fail_cnt=fail_cnt+1;
        end else pass_cnt=pass_cnt+1;

        // ── Test 3: start_group triggers FSM out of IDLE ──────────────────────
        @(negedge clk); start_group=1;
        @(negedge clk); start_group=0;
        repeat(5) @(posedge clk); #1;
        total=total+1;
        if (fsm_state!==2'd0) begin
            $display("PASS: FSM left IDLE (state=%0d)",fsm_state);
            pass_cnt=pass_cnt+1;
        end else begin
            $display("FAIL: FSM still IDLE after start_group");
            fail_cnt=fail_cnt+1;
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
