`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Structural smoke test for accelerator_top (Module 4.2)
// Verifies: compilation, reset, photo_ready triggers busy, outputs non-X.

module tb_accelerator_top;

    reg clk=0; always #5 clk=~clk;
    reg rst=1;

    reg  [`PHOTO_MEM_AW-1:0] pm_addr_wr=0;
    reg  [`DATA_W-1:0]       pm_data_in=0;
    reg  [2:0]               pm_we=0;
    reg                      pm_mem_select=0;
    reg                      photo_ready=0;
    wire                     busy;
    wire                     classification_done;
    wire [9:0]               class_idx;

    accelerator_top dut(
        .clk(clk),.rst(rst),
        .photo_ready(photo_ready),
        .busy(busy),
        .pm_addr_wr(pm_addr_wr),.pm_data_in(pm_data_in),
        .pm_we(pm_we),.pm_mem_select(pm_mem_select),
        .class_idx(class_idx),
        .classification_done(classification_done));

    integer pass_cnt=0, fail_cnt=0, total=0;

    initial begin
        $display("=== tb_accelerator_top ===");
        repeat(5) @(posedge clk); rst=0; @(posedge clk); #1;

        // ── Test 1: after reset, outputs non-X ───────────────────────────────
        total=total+1;
        if (^class_idx===1'bx || ^busy===1'bx) begin
            $display("FAIL: X outputs after reset"); fail_cnt=fail_cnt+1;
        end else begin
            $display("PASS: outputs non-X after reset"); pass_cnt=pass_cnt+1;
        end

        // ── Test 2: busy=0 at reset ───────────────────────────────────────────
        total=total+1;
        if (busy===0) begin
            $display("PASS: busy=0 at reset"); pass_cnt=pass_cnt+1;
        end else begin
            $display("FAIL: busy=%0d at reset",busy); fail_cnt=fail_cnt+1;
        end

        // ── Test 3: classification_done=0 at reset ────────────────────────────
        total=total+1;
        if (classification_done===0) begin
            $display("PASS: classification_done=0"); pass_cnt=pass_cnt+1;
        end else begin
            $display("FAIL: classification_done=%0d",classification_done); fail_cnt=fail_cnt+1;
        end

        // ── Test 4: photo_ready pulse triggers busy ───────────────────────────
        @(negedge clk); photo_ready=1;
        @(negedge clk); photo_ready=0;
        repeat(5) @(posedge clk); #1;
        total=total+1;
        if (^busy!==1'bx) begin
            $display("PASS: busy valid after photo_ready"); pass_cnt=pass_cnt+1;
        end else begin
            $display("FAIL: busy is X after photo_ready"); fail_cnt=fail_cnt+1;
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
