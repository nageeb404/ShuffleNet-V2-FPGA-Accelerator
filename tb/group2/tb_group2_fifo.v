// =============================================================================
// tb_group2_fifo.v -- Self-checking testbench for Module 2.6
// -----------------------------------------------------------------------------
// Thesis Sec 5.4.6 / Figure 5.36, 5.37, 5.38
//
// Vector file format per case:
//   Line 1: width_sel (1 hex token, 0-3)
//   N_STEPS lines: shift_load padding_sel data_in tap00..tap22  (12 tokens)
//   Blank line between cases (skipped)
//
// Timing: drive inputs -> @(posedge clk) -> shift reg updates ->
//         combinational taps settle -> #1 -> CHECK
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_group2_fifo;

    localparam integer DATA_W = `DATA_W;          // 15
    localparam integer DEPTH  = `G2_FIFO_DEPTH;   // 119

    // ---- Clock / reset ----
    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- DUT signals ----
    reg        shift_and_load;
    reg        padding_sel;
    reg [1:0]  width_sel;
    reg  signed [DATA_W-1:0] data_in;

    wire signed [DATA_W-1:0] tap00, tap01, tap02;
    wire signed [DATA_W-1:0] tap10, tap11, tap12;
    wire signed [DATA_W-1:0] tap20, tap21, tap22;

    group2_fifo #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
        .clk           (clk),
        .rst           (rst),
        .shift_and_load(shift_and_load),
        .padding_sel   (padding_sel),
        .width_sel     (width_sel),
        .data_in       (data_in),
        .tap00(tap00), .tap01(tap01), .tap02(tap02),
        .tap10(tap10), .tap11(tap11), .tap12(tap12),
        .tap20(tap20), .tap21(tap21), .tap22(tap22)
    );

    // ---- Parse temporaries ----
    reg [DATA_W-1:0] e00, e01, e02, e10, e11, e12, e20, e21, e22;
    reg rd_sl, rd_ps;
    reg [DATA_W-1:0] rd_din;
    integer ws_int;

    integer fd, r, scan_r;
    reg [8*1024-1:0] cur_line;
    integer pass_count, fail_count, n_cases, n_steps, dump_count;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    integer step_pass;

    // ====================================================================
    initial begin
        pass_count = 0;
        fail_count = 0;
        n_cases    = 0;
        dump_count = 0;
        rst             = 1'b1;
        shift_and_load  = 1'b0;
        padding_sel     = 1'b0;
        width_sel       = 2'b11;
        data_in         = {DATA_W{1'b0}};

        $display("=========================================================");
        $display("group2_fifo Testbench  DEPTH=%0d  DATA_W=%0d", DEPTH, DATA_W);
        $display("=========================================================");

        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/group2/vectors/group2_fifo_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/group2/vectors/group2_fifo_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./group2_fifo_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open group2_fifo_vectors.hex"); $finish;
        end

        #20; @(negedge clk); rst = 1'b0;
        @(negedge clk);  // settle

        // ----------------------------------------------------------------
        // Main test loop: find width_sel header, then read data lines
        // ----------------------------------------------------------------
        begin : test_loop
            while (!$feof(fd)) begin

                // Skip blank/comment lines until we find a 1-token width_sel line
                begin : find_header
                    while (!$feof(fd)) begin
                        r = $fgets(cur_line, fd);
                        if (r == 0) disable test_loop;
                        scan_r = $sscanf(cur_line, "%d", ws_int);
                        if (scan_r == 1 && ws_int >= 0 && ws_int <= 3)
                            disable find_header;
                    end
                end
                if ($feof(fd)) disable test_loop;

                width_sel = ws_int[1:0];
                n_steps   = 0;

                // Reset the FIFO before each case so shift_reg starts at 0
                @(negedge clk); rst = 1'b1;
                @(negedge clk); rst = 1'b0;

                // Read data lines for this case
                begin : data_loop
                    while (!$feof(fd)) begin
                        r = $fgets(cur_line, fd);
                        if (r == 0) disable data_loop;
                        scan_r = $sscanf(cur_line,
                            "%h %h %h %h %h %h %h %h %h %h %h %h",
                            rd_sl, rd_ps, rd_din,
                            e00, e01, e02,
                            e10, e11, e12,
                            e20, e21, e22);
                        if (scan_r != 12) begin
                            // blank or comment: if we already have steps, end case
                            if (n_steps > 0) disable data_loop;
                            // else keep looking
                        end else begin
                            // Drive inputs before posedge
                            shift_and_load = rd_sl;
                            padding_sel    = rd_ps;
                            data_in        = $signed(rd_din);
                            @(posedge clk);
                            #1;   // let combinational outputs settle

                            // Check all 9 taps
                            step_pass = 1;
                            if (tap00 !== $signed(e00)) step_pass = 0;
                            if (tap01 !== $signed(e01)) step_pass = 0;
                            if (tap02 !== $signed(e02)) step_pass = 0;
                            if (tap10 !== $signed(e10)) step_pass = 0;
                            if (tap11 !== $signed(e11)) step_pass = 0;
                            if (tap12 !== $signed(e12)) step_pass = 0;
                            if (tap20 !== $signed(e20)) step_pass = 0;
                            if (tap21 !== $signed(e21)) step_pass = 0;
                            if (tap22 !== $signed(e22)) step_pass = 0;

                            if (step_pass)
                                pass_count = pass_count + 1;
                            else begin
                                fail_count = fail_count + 1;
                                if (dump_count < 5) begin
                                    $display("FAIL case=%0d step=%0d ws=%0d",
                                             n_cases, n_steps, ws_int);
                                    $display("  got row0: %0d %0d %0d",
                                        $signed(tap00), $signed(tap01), $signed(tap02));
                                    $display("  exp row0: %0d %0d %0d",
                                        $signed(e00), $signed(e01), $signed(e02));
                                    $display("  got row1: %0d %0d %0d",
                                        $signed(tap10), $signed(tap11), $signed(tap12));
                                    $display("  exp row1: %0d %0d %0d",
                                        $signed(e10), $signed(e11), $signed(e12));
                                    $display("  got row2: %0d %0d %0d",
                                        $signed(tap20), $signed(tap21), $signed(tap22));
                                    $display("  exp row2: %0d %0d %0d",
                                        $signed(e20), $signed(e21), $signed(e22));
                                    dump_count = dump_count + 1;
                                end
                            end
                            n_steps = n_steps + 1;
                        end
                    end
                end // data_loop

                if (n_steps > 0)
                    n_cases = n_cases + 1;

            end // while !feof
        end // test_loop

        $fclose(fd);
        $display("---------------------------------------------------------");
        $display("Tested %0d cases, %0d total step-checks", n_cases, pass_count + fail_count);
        $display("PASS: %0d / %0d", pass_count, pass_count + fail_count);
        $display("FAIL: %0d / %0d", fail_count, pass_count + fail_count);
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
// END tb_group2_fifo.v
// =============================================================================
