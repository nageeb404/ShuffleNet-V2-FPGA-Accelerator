// =============================================================================
// tb_group3_ctrl.v -- Structural smoke test for Module 3.4 (group3_ctrl)
// -----------------------------------------------------------------------------
// Thesis Sec 5.5 / Table 5.12, Figure 5.68
//
// Tests:
//   1. After reset: outputs are zero, state is IDLE
//   2. start_group triggers conv1x1_en and conv1x1_acc_clr on cycle 1
//   3. acc_clr de-asserts after 2 cycles (pipeline settling)
//   4. extramem_rd_addr advances every cycle
//   5. group3_done stays 0 initially (full run takes ~47000 cycles)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_group3_ctrl;

    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg start_group;

    wire conv1x1_en, conv1x1_acc_clr;
    wire [9:0]  conv1x1_step_out;
    wire avgpool_acc_en, avgpool_acc_clr, avgpool_result_we;
    wire regfile_shift;
    wire fc_en, fc_acc_clr;
    wire [14:0] fc_acc_addr;
    wire [9:0]  fc_bias_addr;
    wire class_we, max_update;
    wire [9:0]  class_idx;
    wire [13:0] extramem_rd_addr;
    wire [9:0]  regfile_sel_ch;
    wire group3_done;

    group3_ctrl dut (
        .clk              (clk),
        .rst              (rst),
        .start_group      (start_group),
        .conv1x1_en       (conv1x1_en),
        .conv1x1_acc_clr  (conv1x1_acc_clr),
        .conv1x1_step_out (conv1x1_step_out),
        .avgpool_acc_en   (avgpool_acc_en),
        .avgpool_acc_clr  (avgpool_acc_clr),
        .avgpool_result_we(avgpool_result_we),
        .regfile_shift    (regfile_shift),
        .fc_en            (fc_en),
        .fc_acc_clr       (fc_acc_clr),
        .fc_acc_addr      (fc_acc_addr),
        .fc_bias_addr     (fc_bias_addr),
        .class_we         (class_we),
        .max_update       (max_update),
        .class_idx        (class_idx),
        .extramem_rd_addr (extramem_rd_addr),
        .regfile_sel_ch   (regfile_sel_ch),
        .group3_done      (group3_done)
    );

    integer pass_count, fail_count;
    integer i;

    task check;
        input integer cond;
        input [8*64-1:0] msg;
        begin
            if (cond) pass_count = pass_count + 1;
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s", msg);
            end
        end
    endtask

    initial begin
        pass_count  = 0; fail_count = 0;
        rst         = 1'b1;
        start_group = 1'b0;

        $display("=========================================================");
        $display("group3_ctrl Testbench (Structural Smoke Test)");
        $display("=========================================================");

        // ---- Test 1: After reset ----
        #20; @(negedge clk); rst = 1'b0;
        @(posedge clk); #1;

        check((conv1x1_en       === 1'b0), "conv1x1_en=0 after reset");
        check((group3_done      === 1'b0), "group3_done=0 after reset");
        check((extramem_rd_addr === 14'd0), "extramem_rd_addr=0 after reset");

        // ---- Test 2: start_group fires conv on next cycle ----
        @(negedge clk); start_group = 1'b1;
        @(posedge clk); #1;
        start_group = 1'b0;

        check((conv1x1_en     === 1'b1), "conv1x1_en=1 after start_group");
        check((conv1x1_acc_clr=== 1'b1), "conv1x1_acc_clr=1 (first step)");

        // ---- Test 3: acc_clr stays high for step 1 too ----
        @(posedge clk); #1;
        check((conv1x1_en     === 1'b1), "conv1x1_en=1 at step 1");
        check((conv1x1_acc_clr=== 1'b1), "conv1x1_acc_clr=1 at step 1");

        // ---- Test 4: acc_clr goes low at step 2 ----
        @(posedge clk); #1;
        check((conv1x1_acc_clr === 1'b0), "conv1x1_acc_clr=0 at step 2");

        // ---- Test 5: extramem_rd_addr advances ----
        check((extramem_rd_addr !== 14'd0), "extramem_rd_addr advanced from 0");

        // ---- Test 6: group3_done stays 0 (operation not complete) ----
        repeat(20) @(posedge clk);
        #1;
        check((group3_done === 1'b0), "group3_done=0 (only 24 cycles elapsed)");

        // ---- Test 7: Reset restores IDLE ----
        @(negedge clk); rst = 1'b1;
        @(negedge clk); rst = 1'b0;
        @(posedge clk); #1;

        check((conv1x1_en     === 1'b0), "conv1x1_en=0 after second reset");
        check((extramem_rd_addr === 14'd0), "extramem_rd_addr=0 after reset");

        // ---- Summary ----
        $display("---------------------------------------------------------");
        $display("Tested %0d checks", pass_count + fail_count);
        $display("PASS: %0d / %0d", pass_count, pass_count + fail_count);
        $display("FAIL: %0d / %0d", fail_count, pass_count + fail_count);
        if (fail_count == 0) $display("RESULT: *** ALL TESTS PASSED ***");
        else                 $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
        $display("=========================================================");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_group3_ctrl.v
// =============================================================================
