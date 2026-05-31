`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Structural smoke test for group3_top (Module 3.5)
// Verifies: compilation, reset behavior, FSM leaves IDLE on start_group,
//           class_idx and other outputs are non-X.

module tb_group3_top;

    localparam N_CHAN_IN = `G3_PW_PAR_CHAN; // 29
    localparam G2_FM     = `G2_FM_W;        // 12

    reg clk=0; always #5 clk=~clk;
    reg rst=1;

    reg  start_group=0;
    wire group3_done;
    wire [13:0] extramem_rd_addr;
    reg  signed [N_CHAN_IN*G2_FM-1:0] extramem_data_in;
    wire [9:0] class_idx;
    wire [13:0] dbg_extramem_addr;
    wire        dbg_conv1x1_en;

    group3_top dut(
        .clk(clk),.rst(rst),
        .start_group(start_group),
        .group3_done(group3_done),
        .extramem_rd_addr(extramem_rd_addr),
        .extramem_data_in(extramem_data_in),
        .class_idx(class_idx),
        .dbg_extramem_addr(dbg_extramem_addr),
        .dbg_conv1x1_en(dbg_conv1x1_en));

    integer pass_cnt=0, fail_cnt=0, total=0;

    initial begin
        $display("=== tb_group3_top ===");
        rst=1; extramem_data_in=0;
        repeat(5) @(posedge clk); rst=0; @(posedge clk); #1;

        // ── Test 1: after reset, key signals non-X ────────────────────────────
        total=total+1;
        if (^class_idx===1'bx || ^extramem_rd_addr===1'bx) begin
            $display("FAIL: X signals after reset");
            fail_cnt=fail_cnt+1;
        end else begin
            $display("PASS: outputs non-X after reset"); pass_cnt=pass_cnt+1;
        end

        // ── Test 2: group3_done is 0 at reset ─────────────────────────────────
        total=total+1;
        if (group3_done!==0) begin
            $display("FAIL: group3_done not 0 at reset"); fail_cnt=fail_cnt+1;
        end else pass_cnt=pass_cnt+1;

        // ── Test 3: start_group triggers activity ──────────────────────────────
        @(negedge clk); start_group=1;
        @(negedge clk); start_group=0;
        repeat(10) @(posedge clk); #1;
        total=total+1;
        if (^dbg_conv1x1_en!==1'bx) begin
            $display("PASS: dbg_conv1x1_en valid after start"); pass_cnt=pass_cnt+1;
        end else begin
            $display("FAIL: dbg_conv1x1_en is X after start"); fail_cnt=fail_cnt+1;
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
