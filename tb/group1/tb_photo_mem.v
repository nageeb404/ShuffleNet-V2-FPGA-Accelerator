`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for photo_mem (Module 1.10)
// DATA_W=15 write port, PHOTO_W=8 read output (Ch 6.2.6).
// Ping-pong: mem_select=0 → write→bank0, read→bank1; =1 → write→bank1, read→bank0.
// BRAM starts uninitialized (X) — only test after writing first.

module tb_photo_mem;

    localparam AW      = `PHOTO_MEM_AW; // 16
    localparam DATA_W  = `DATA_W;       // 15
    localparam PHOTO_W = `PHOTO_W;      // 8

    reg clk=0; always #5 clk=~clk;
    reg rst=1;

    reg  [AW-1:0]      addr_wr;
    reg  [DATA_W-1:0]  data_in;
    reg  [2:0]         we;
    reg  [AW-1:0]      addr_rd;
    reg                mem_select;
    wire [PHOTO_W-1:0] data_out_ch1, data_out_ch2, data_out_ch3;

    photo_mem dut(.clk(clk),.rst(rst),
        .addr_wr(addr_wr),.data_in(data_in),.we(we),
        .addr_rd(addr_rd),.mem_select(mem_select),
        .data_out_ch1(data_out_ch1),
        .data_out_ch2(data_out_ch2),
        .data_out_ch3(data_out_ch3));

    integer pass_cnt=0, fail_cnt=0, total=0;

    task do_reset;
        begin rst=1; addr_wr=0; data_in=0; we=0; addr_rd=0; mem_select=0;
              repeat(4) @(posedge clk); rst=0; @(posedge clk); end
    endtask

    task chk;
        input [PHOTO_W-1:0] got, exp; input integer ch;
        begin
            total=total+1;
            if (got!==exp) begin
                $display("FAIL ch%0d: got=%0d exp=%0d",ch,got,exp);
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
        end
    endtask

    initial begin
        $display("=== tb_photo_mem ===");
        do_reset;

        // ── Case 1: write ch1=100 to bank0 (mem_select=0), read from bank0 (mem_select=1)
        @(negedge clk); mem_select=0; addr_wr=5; data_in=15'd100; we=3'b001;
        @(posedge clk); we=0;
        @(negedge clk); mem_select=1; addr_rd=5; // switch to read bank0
        @(posedge clk); @(posedge clk); #1; // 2-cycle BRAM latency
        chk(data_out_ch1, 8'd100, 1);
        // ch2 was never written at addr=5 → uninitialized (X), skip check

        // ── Case 2: write all 3 channels at addr=10
        @(negedge clk); mem_select=0; addr_wr=10; data_in=15'd42; we=3'b111;
        @(posedge clk); we=0;
        @(negedge clk); mem_select=1; addr_rd=10;
        @(posedge clk); @(posedge clk); #1;
        chk(data_out_ch1, 8'd42, 1);
        chk(data_out_ch2, 8'd42, 2);
        chk(data_out_ch3, 8'd42, 3);

        // ── Case 3: write ch3 only at addr=20
        @(negedge clk); mem_select=0; addr_wr=20; data_in=15'd77; we=3'b100;
        @(posedge clk); we=0;
        @(negedge clk); mem_select=1; addr_rd=20;
        @(posedge clk); @(posedge clk); #1;
        chk(data_out_ch3, 8'd77, 3);

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
