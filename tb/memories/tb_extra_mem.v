`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for extra_mem (G2→G3 feature map buffer)
// 29 channel instances, each BRAM 1024×12 bits. 1-cycle BRAM read latency.
// Address: wr_addr[9:0] for write, rd_addr[9:0] for read.

module tb_extra_mem;
    `include "shufflenet_pkg.vh"
    localparam N_CH   = `G3_PW_PAR_CHAN; // 29
    localparam DATA_W = `G2_FM_W;         // 12
    localparam AW = 10;

    reg clk=0; always #5 clk=~clk;

    reg  [N_CH*DATA_W-1:0]  wr_data;
    reg  [AW-1:0]           wr_addr, rd_addr;
    reg                     wr_we;
    wire [N_CH*DATA_W-1:0]  rd_data;

    extra_mem dut(
        .clk(clk),
        .wr_data(wr_data),.wr_addr(wr_addr),.wr_we(wr_we),
        .rd_addr(rd_addr),.rd_data(rd_data));

    integer pass_cnt=0, fail_cnt=0, total=0, ch;

    task do_reset;
        begin wr_we=0; wr_data=0; wr_addr=0; rd_addr=0;
              repeat(4) @(posedge clk); end
    endtask

    initial begin
        $display("=== tb_extra_mem ===");
        do_reset;

        // ── Write 0xABC to all channels at addr=5, read back ─────────────────
        @(negedge clk);
        wr_addr=5; wr_we=1;
        for (ch=0; ch<N_CH; ch=ch+1)
            wr_data[ch*DATA_W +:DATA_W] = 12'hABC;
        @(posedge clk); @(negedge clk); wr_we=0;

        // Read back
        rd_addr=5;
        @(posedge clk); @(posedge clk); #1; // 1-cycle BRAM read latency

        for (ch=0; ch<N_CH; ch=ch+1) begin
            total=total+1;
            if (rd_data[ch*DATA_W +:DATA_W] !== 12'hABC) begin
                $display("FAIL ch=%0d addr=5: got=0x%03h exp=0xABC",
                    ch, rd_data[ch*DATA_W +:DATA_W]);
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
        end

        // ── Write different values per channel at addr=10 ─────────────────────
        @(negedge clk); wr_addr=10; wr_we=1;
        for (ch=0; ch<N_CH; ch=ch+1)
            wr_data[ch*DATA_W +:DATA_W] = ch;
        @(posedge clk); @(negedge clk); wr_we=0;

        rd_addr=10;
        @(posedge clk); @(posedge clk); #1;

        for (ch=0; ch<N_CH; ch=ch+1) begin
            total=total+1;
            if (rd_data[ch*DATA_W +:DATA_W] !== ch[DATA_W-1:0]) begin
                $display("FAIL ch=%0d addr=10: got=%0d exp=%0d",
                    ch, rd_data[ch*DATA_W +:DATA_W], ch);
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
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
