// =============================================================================
// tb_maxpool_mem.v -- Self-checking testbench for Module 1.11 (maxpool_mem)
// -----------------------------------------------------------------------------
// Thesis Sec 5.3.1.2 "Max Pooling Memory" / Figure 5.4
//
// Uses N_CHAN=24, IMG_W=4, IMG_H=4 (DEPTH=16) for a fast test.
// Writes all 16 addresses with known 24-channel pattern, then reads back
// all 16 addresses and verifies all 24 channel values simultaneously.
//
// Vector file format: tb/common/vectors/maxpool_mem_tb_vectors.hex
//   W addr flat_hex    -- write (1 clock, all 24 channels at once)
//   R addr flat_hex    -- read check (1-cycle latency)
//   flat is a 360-bit hex value; flat[ch*15 +: 15] = value for channel ch.
//   Lines beginning with // are comments.
//
// Pass criterion: "RESULT: *** ALL TESTS PASSED ***"
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_maxpool_mem;

    // Small image for fast simulation; full N_CHAN to test all 24 BRAMs
    localparam integer N_CHAN = `G1_OUT_C;       // 24
    localparam integer DATA_W = `DATA_W;         // 15
    localparam integer IMG_W  = 4;
    localparam integer IMG_H  = 4;
    localparam integer AW     = `MAXPOOL_MEM_AW; // 12

    localparam integer FLAT_W = N_CHAN * DATA_W; // 360

    // -------------------------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------------------------
    reg clk, rst;
    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg  [AW-1:0]    addr_wr;
    reg  [FLAT_W-1:0] data_in;
    reg               we;
    reg  [AW-1:0]    addr_rd;
    wire [FLAT_W-1:0] data_out;

    maxpool_mem #(
        .N_CHAN (N_CHAN),
        .DATA_W (DATA_W),
        .IMG_W  (IMG_W),
        .IMG_H  (IMG_H),
        .AW     (AW)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .addr_wr (addr_wr),
        .data_in (data_in),
        .we      (we),
        .addr_rd (addr_rd),
        .data_out(data_out)
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
    reg [FLAT_W-1:0] vec_flat;

    localparam integer MAX_DUMP = 10;

    reg first_read;  // used to handle 1-cycle BRAM read latency on first read

    // -------------------------------------------------------------------------
    // Main test
    // -------------------------------------------------------------------------
    initial begin
        n_checks   = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;
        first_read = 1;

        addr_wr = {AW{1'b0}};
        data_in = {FLAT_W{1'b0}};
        we      = 1'b0;
        addr_rd = {AW{1'b0}};

        $display("=========================================================");
        $display("maxpool_mem Testbench (Thesis Sec 5.3.1.2 / Fig 5.4)");
        $display("N_CHAN=%0d IMG_W=%0d IMG_H=%0d DATA_W=%0d (SDP BRAM x24)",
                 N_CHAN, IMG_W, IMG_H, DATA_W);
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
            fd = $fopen("tb/common/vectors/maxpool_mem_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("../tb/common/vectors/maxpool_mem_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("../../../../../../tb/group1/vectors/maxpool_mem_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("./maxpool_mem_tb_vectors.hex", "r");
        if (fd == 0) begin
            $display("ERROR: cannot open maxpool_mem_tb_vectors.hex");
            $display("Run: python scripts/gen_maxpool_mem_vectors.py");
            $finish;
        end

        // ---------------------------------------------------------------------------
        // Process vector file
        // ---------------------------------------------------------------------------
        begin : file_loop
            while (!$feof(fd)) begin
                r = $fgets(line_buf, fd);
                if (r == 0) disable file_loop;

                sc = $sscanf(line_buf, " %c %h %h", op_char, vec_addr, vec_flat);
                if (sc != 3) begin
                    // comment or blank line -- skip
                end else if (op_char == "W" || op_char == "w") begin
                    // ----------------------------------------------------------
                    // Write: 1 clock cycle, all 24 channels simultaneously
                    // ----------------------------------------------------------
                    addr_wr = vec_addr;
                    data_in = vec_flat;
                    we      = 1'b1;
                    @(posedge clk); #1;
                    we      = 1'b0;

                end else if (op_char == "R" || op_char == "r") begin
                    // ----------------------------------------------------------
                    // Read: 1-cycle BRAM latency.
                    // Drive addr_rd, clock once, then check data_out.
                    // ----------------------------------------------------------
                    we      = 1'b0;
                    addr_rd = vec_addr;
                    @(posedge clk); #1;

                    n_checks = n_checks + 1;
                    if (data_out !== vec_flat) begin
                        fail_count = fail_count + 1;
                        if (dump_count < MAX_DUMP) begin
                            $display("FAIL addr=%0h", vec_addr);
                            $display("  got  = %h", data_out);
                            $display("  exp  = %h", vec_flat);
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
// END tb_maxpool_mem.v
// =============================================================================
