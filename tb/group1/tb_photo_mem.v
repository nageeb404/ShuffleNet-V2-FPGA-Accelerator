// =============================================================================
// tb_photo_mem.v -- Self-checking testbench for Module 1.10 (photo_mem)
// -----------------------------------------------------------------------------
// Thesis Sec 5.3.1.1 "Photo Memory" / Figure 5.5
//
// Uses a small image (IMG_W=4, IMG_H=4) so the test runs fast.
// Exercises the full ping-pong protocol:
//   Phase A: write bank0 (mem_select=0), 16 addresses x 3 channels
//   Phase B: switch mem_select=1, read bank0 and verify
//   Phase C: write bank1 (mem_select=1) with a different pattern
//   Phase D: switch mem_select=0, read bank1 and verify
//
// Writing: 3 cycles per address (one clock per channel, shared data_in bus).
// Reading: 1 cycle latency (BRAM registered read + registered output mux).
//
// Vector file format: tb/common/vectors/photo_mem_tb_vectors.hex
//   W addr data_ch1 data_ch2 data_ch3   -- write operation (3 clocks)
//   R addr exp_ch1  exp_ch2  exp_ch3    -- read check      (1 clock)
//   Lines beginning with // are comments.
//
// Pass criterion: "RESULT: *** ALL TESTS PASSED ***"
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_photo_mem;

    // Override parameters for small image (4x4)
    localparam integer IMG_W  = 4;
    localparam integer IMG_H  = 4;
    localparam integer DATA_W = `DATA_W;       // 15
    localparam integer AW     = `PHOTO_MEM_AW; // 16

    // -------------------------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------------------------
    reg clk, rst;
    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg  [AW-1:0]     addr_wr;
    reg  [DATA_W-1:0] data_in;
    reg  [2:0]         we;
    reg  [AW-1:0]     addr_rd;
    reg                mem_select;

    wire [DATA_W-1:0] data_out_ch1;
    wire [DATA_W-1:0] data_out_ch2;
    wire [DATA_W-1:0] data_out_ch3;

    photo_mem #(
        .IMG_W  (IMG_W),
        .IMG_H  (IMG_H),
        .DATA_W (DATA_W),
        .AW     (AW)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .addr_wr      (addr_wr),
        .data_in      (data_in),
        .we           (we),
        .addr_rd      (addr_rd),
        .mem_select   (mem_select),
        .data_out_ch1 (data_out_ch1),
        .data_out_ch2 (data_out_ch2),
        .data_out_ch3 (data_out_ch3)
    );

    // -------------------------------------------------------------------------
    // Test infrastructure
    // -------------------------------------------------------------------------
    integer fd, r, sc;
    integer n_checks, pass_count, fail_count, dump_count;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    reg [8*256-1:0] line_buf;
    reg [7:0]        op_char;
    reg [AW-1:0]     vec_addr;
    reg [DATA_W-1:0] vec_d1, vec_d2, vec_d3;

    localparam integer MAX_DUMP = 10;

    reg in_read_phase;   // 1 while inside a read phase (prevents repeated toggle)

    // -------------------------------------------------------------------------
    // Main test
    // -------------------------------------------------------------------------
    initial begin
        n_checks      = 0;
        pass_count    = 0;
        fail_count    = 0;
        dump_count    = 0;
        in_read_phase = 0;

        // Initial signal state
        addr_wr    = {AW{1'b0}};
        data_in    = {DATA_W{1'b0}};
        we         = 3'b000;
        addr_rd    = {AW{1'b0}};
        mem_select = 1'b0;

        $display("=========================================================");
        $display("photo_mem Testbench (Thesis Sec 5.3.1.1 / Fig 5.5)");
        $display("IMG_W=%0d IMG_H=%0d DATA_W=%0d (ping-pong BRAM)",
                 IMG_W, IMG_H, DATA_W);
        $display("=========================================================");

        // Reset for 3 cycles
        rst = 1'b1;
        repeat(3) @(posedge clk);
        #1;
        rst = 1'b0;

        // Open vector file
        have_arg = $value$plusargs("VECTORS=%s", path_arg);
        if (have_arg)
            fd = $fopen(path_arg, "r");
        else
            fd = $fopen("tb/common/vectors/photo_mem_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("../tb/common/vectors/photo_mem_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("./photo_mem_tb_vectors.hex", "r");
        if (fd == 0) begin
            $display("ERROR: cannot open photo_mem_tb_vectors.hex");
            $display("Run: python scripts/gen_photo_mem_vectors.py");
            $finish;
        end

        // ---------------------------------------------------------------------------
        // Process vector file line by line.
        // Each line: op_char addr d1 d2 d3 (5 tokens).
        // op_char == 'W': write; op_char == 'R': read+check.
        // Comment/blank lines fail sscanf (sc != 5) and are skipped.
        // ---------------------------------------------------------------------------
        begin : file_loop
            while (!$feof(fd)) begin
                r = $fgets(line_buf, fd);
                if (r == 0) disable file_loop;

                sc = $sscanf(line_buf, " %c %h %h %h %h",
                             op_char, vec_addr, vec_d1, vec_d2, vec_d3);
                if (sc != 5) begin
                    // comment or blank line -- skip
                end else if (op_char == "W" || op_char == "w") begin
                    // ----------------------------------------------------------
                    // Write: 3 clock cycles (one per channel, shared data_in)
                    // ----------------------------------------------------------
                    we = 3'b000;

                    // Write ch1
                    addr_wr = vec_addr;
                    data_in = vec_d1;
                    we      = 3'b001;
                    @(posedge clk); #1;

                    // Write ch2
                    data_in = vec_d2;
                    we      = 3'b010;
                    @(posedge clk); #1;

                    // Write ch3
                    data_in = vec_d3;
                    we      = 3'b100;
                    @(posedge clk); #1;

                    we            = 3'b000;
                    in_read_phase = 0;

                end else if (op_char == "R" || op_char == "r") begin
                    // ----------------------------------------------------------
                    // Read: 1 clock cycle.  First R after a write phase toggles
                    // mem_select so the accelerator reads the bank just written.
                    // ----------------------------------------------------------
                    we = 3'b000;
                    if (!in_read_phase) begin
                        // Phase transition: toggle bank select, apply first addr_rd,
                        // then clock once -- both mem_select_r and BRAM dout update.
                        mem_select    = ~mem_select;
                        addr_rd       = vec_addr;
                        @(posedge clk); #1;
                        in_read_phase = 1;
                    end else begin
                        addr_rd = vec_addr;
                        @(posedge clk); #1;
                    end

                    // Check all 3 channel outputs
                    n_checks = n_checks + 1;
                    if (data_out_ch1 !== vec_d1 ||
                        data_out_ch2 !== vec_d2 ||
                        data_out_ch3 !== vec_d3) begin
                        fail_count = fail_count + 1;
                        if (dump_count < MAX_DUMP) begin
                            $display("FAIL addr=%0h got ch1=%h ch2=%h ch3=%h  exp %h %h %h",
                                     vec_addr,
                                     data_out_ch1, data_out_ch2, data_out_ch3,
                                     vec_d1, vec_d2, vec_d3);
                            dump_count = dump_count + 1;
                        end
                    end else begin
                        pass_count = pass_count + 1;
                    end
                end
                // else: unrecognised op -- skip
            end
        end
        $fclose(fd);

        $display("---------------------------------------------------------");
        $display("Checks : %0d", n_checks);
        $display("PASS   : %0d / %0d", pass_count, n_checks);
        $display("FAIL   : %0d / %0d", fail_count, n_checks);
        $display("---------------------------------------------------------");
        if (fail_count == 0)
            $display("RESULT: *** ALL TESTS PASSED ***");
        else
            $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
        $display("=========================================================");

        $finish;
    end

    initial begin
        #500000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_photo_mem.v
// =============================================================================
