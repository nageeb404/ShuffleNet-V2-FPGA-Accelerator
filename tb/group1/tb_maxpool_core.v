// =============================================================================
// tb_maxpool_core.v -- Self-checking testbench for Module 1.4
// -----------------------------------------------------------------------------
// Thesis Sec 5.8.1 / Sec 5.3.2.2 / Table 5.2
//
// Vector file format: 25 lines per test case
//   Lines 1-24: 9 hex values (channel 0..23 window inputs)
//   Line 25:    24 hex values (expected max per channel)
//
// Pipeline timing (1-cycle latency -- pipeline reg after stage 2):
//   negedge 0: drive inputs, en=1
//   (posedge 0: pipeline register captures stage-2 results)
//   negedge 1: CHECK results (stage-3 combinational output valid)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_maxpool_core;

    localparam integer N_CHAN  = `G1_POOL_PAR_CHAN;        // 24
    localparam integer N_WIN   = `G1_POOL_PAR_WIN;         // 9
    localparam integer DATA_W  = `G1_FM_W;                 // 10 (Ch 6.2.8)
    localparam integer D_TOT   = N_CHAN * N_WIN * DATA_W;  // 2160
    localparam integer R_TOT   = N_CHAN * DATA_W;           // 240

    // ---- Clock / reset ----
    reg clk, rst, en;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- DUT ports ----
    reg  [D_TOT-1:0] dut_data;
    wire [R_TOT-1:0] dut_results;

    maxpool_core dut (
        .clk        (clk),
        .rst        (rst),
        .en         (en),
        .data_flat  (dut_data),
        .results_flat(dut_results)
    );

    // ---- Parse temporaries ----
    reg [DATA_W-1:0] tmp_win [0:8];    // one channel's 9 window values
    reg [DATA_W-1:0] tmp_exp [0:23];   // 24 expected max values

    // ---- Counters / file ----
    integer fd, r, sc, n_vectors, pass_count, fail_count, dump_count;
    integer chan_idx, tap_idx, chk_idx;
    reg [8*1024-1:0] line_buf;
    reg [8*512-1:0]  path_arg;
    integer have_arg;
    reg [DATA_W-1:0] got_val;

    // ====================================================================
    initial begin
        n_vectors  = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;
        rst        = 1'b1;
        en         = 1'b0;
        dut_data   = {D_TOT{1'b0}};

        $display("=========================================================");
        $display("maxpool_core Testbench (Thesis Sec 5.3.2.2, Table 5.2)");
        $display("24 channels x 9-window max-of-9 with 1-cycle pipeline");
        $display("=========================================================");

        // ---- Open vector file ----
        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/common/vectors/maxpool_core_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/common/vectors/maxpool_core_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./maxpool_core_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open maxpool_core_vectors.hex");
            $finish;
        end

        // ---- Reset: 3 cycles ----
        #20;
        @(negedge clk);
        rst = 1'b0;
        en  = 1'b1;
        @(negedge clk);

        // ====================================================================
        // Main loop: 25 lines per test case
        //   Lines 1-24: channel window (9 values each)
        //   Line 25:    expected outputs (24 values)
        // ====================================================================
        begin : main_loop
            while (!$feof(fd)) begin

                // ---- Read channel 0 window (skip comments/blanks) ----
                r  = $fgets(line_buf, fd);
                if (r == 0) disable main_loop;
                sc = $sscanf(line_buf,
                             "%h %h %h %h %h %h %h %h %h",
                             tmp_win[0], tmp_win[1], tmp_win[2],
                             tmp_win[3], tmp_win[4], tmp_win[5],
                             tmp_win[6], tmp_win[7], tmp_win[8]);
                if (sc != 9) begin
                    // comment or blank -- skip
                end else begin
                    // Pack channel 0 into dut_data
                    for (tap_idx = 0; tap_idx < 9; tap_idx = tap_idx + 1)
                        dut_data[(0*9 + tap_idx)*DATA_W +: DATA_W] = tmp_win[tap_idx];

                    // ---- Read channels 1..23 ----
                    for (chan_idx = 1; chan_idx < N_CHAN; chan_idx = chan_idx + 1) begin
                        r  = $fgets(line_buf, fd);
                        sc = $sscanf(line_buf,
                                     "%h %h %h %h %h %h %h %h %h",
                                     tmp_win[0], tmp_win[1], tmp_win[2],
                                     tmp_win[3], tmp_win[4], tmp_win[5],
                                     tmp_win[6], tmp_win[7], tmp_win[8]);
                        for (tap_idx = 0; tap_idx < 9; tap_idx = tap_idx + 1)
                            dut_data[(chan_idx*9 + tap_idx)*DATA_W +: DATA_W]
                                = tmp_win[tap_idx];
                    end

                    // ---- Read 24 expected results ----
                    r  = $fgets(line_buf, fd);
                    sc = $sscanf(line_buf,
                        "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                        tmp_exp[ 0], tmp_exp[ 1], tmp_exp[ 2], tmp_exp[ 3],
                        tmp_exp[ 4], tmp_exp[ 5], tmp_exp[ 6], tmp_exp[ 7],
                        tmp_exp[ 8], tmp_exp[ 9], tmp_exp[10], tmp_exp[11],
                        tmp_exp[12], tmp_exp[13], tmp_exp[14], tmp_exp[15],
                        tmp_exp[16], tmp_exp[17], tmp_exp[18], tmp_exp[19],
                        tmp_exp[20], tmp_exp[21], tmp_exp[22], tmp_exp[23]);

                    // ============================================================
                    // Drive DUT (2-negedge sequence, 1-cycle latency)
                    // ============================================================

                    // negedge 0: present inputs, en=1
                    @(negedge clk);
                    // dut_data already loaded above (and stays stable for this cycle)
                    // posedge 0: pipeline register captures stage-2 results

                    // negedge 1: results valid (stage-3 combinational from register)
                    @(negedge clk);
                    begin : check_loop
                        integer fail_this;
                        fail_this = 0;
                        for (chk_idx = 0; chk_idx < N_CHAN; chk_idx = chk_idx + 1) begin
                            got_val = dut_results[chk_idx*DATA_W +: DATA_W];
                            if (got_val !== tmp_exp[chk_idx]) begin
                                fail_this = fail_this + 1;
                                if (dump_count < 10) begin
                                    $display(
                                      "FAIL case=%0d ch=%0d got=%0d exp=%0d",
                                      n_vectors, chk_idx,
                                      $signed(got_val), $signed(tmp_exp[chk_idx]));
                                    dump_count = dump_count + 1;
                                end
                            end
                        end
                        if (fail_this == 0) pass_count = pass_count + 1;
                        else                fail_count = fail_count + 1;
                    end

                    n_vectors = n_vectors + 1;

                end // if sc==9 (valid first channel line)

            end // while
        end // main_loop

        $fclose(fd);
        $display("---------------------------------------------------------");
        $display("Tested %0d vectors (%0d channel-results each)",
                 n_vectors, N_CHAN);
        $display("PASS: %0d / %0d", pass_count, n_vectors);
        $display("FAIL: %0d / %0d", fail_count, n_vectors);
        if (fail_count == 0)
            $display("RESULT: *** ALL TESTS PASSED ***");
        else
            $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
        $display("=========================================================");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_maxpool_core.v
// =============================================================================
