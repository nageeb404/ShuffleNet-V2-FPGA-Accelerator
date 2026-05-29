// =============================================================================
// tb_group2_fifo_ctrl.v -- Self-checking testbench for Module 2.7
// -----------------------------------------------------------------------------
// / Figure 5.39
//
// One test case per (W, H, STRIDE) configuration.
// The DUT is re-parameterized per case using a parameter-override trick:
// since Verilog-2001 doesn't allow runtime parameter changes, we instantiate
// a separate DUT for each case and select via an integer index.
//
// This TB uses the SMALLEST test case (W=7, H=7, STRIDE=1) directly to keep
// the Verilog manageable; larger cases are validated via the Python model.
// The vector file is read and each cycle's outputs are compared.
//
// Vector file format per case:
// Line 1: W H STRIDE (3 decimal tokens)
// Per cycle: shift_load padding_sel fsm_state rd_ptr done (5 decimal tokens)
// Blank line between cases.
//
// Timing: start is asserted at cycle 0 (after reset).
// Each subsequent cycle advances the FSM.
// Outputs are registered; we compare them AFTER each posedge.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_group2_fifo_ctrl;

    // ---- Clock / reset ----
    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- One DUT instance per test config (Verilog-2001 workaround) ----
    // Configs: (W=7,H=7,S=1), (W=14,H=14,S=1), (W=28,H=28,S=1),
    // (W=14,H=14,S=2), (W=28,H=28,S=2), (W=56,H=56,S=2)
    localparam N_DUTS = 6;

    reg  start_r [0:N_DUTS-1];
    wire shift_and_load_w [0:N_DUTS-1];
    wire padding_sel_w    [0:N_DUTS-1];
    wire [1:0]  width_sel_w [0:N_DUTS-1];
    wire [11:0] rd_addr_w   [0:N_DUTS-1];
    wire [2:0]  fsm_state_w [0:N_DUTS-1];
    wire        done_w      [0:N_DUTS-1];

    group2_fifo_ctrl #(.W(7),  .H(7),  .STRIDE(1), .AW(12)) dut0 (
        .clk(clk),.rst(rst),.start(start_r[0]),
        .shift_and_load(shift_and_load_w[0]),.padding_sel(padding_sel_w[0]),
        .width_sel(width_sel_w[0]),.rd_addr(rd_addr_w[0]),
        .fsm_state(fsm_state_w[0]),.done(done_w[0]));

    group2_fifo_ctrl #(.W(14), .H(14), .STRIDE(1), .AW(12)) dut1 (
        .clk(clk),.rst(rst),.start(start_r[1]),
        .shift_and_load(shift_and_load_w[1]),.padding_sel(padding_sel_w[1]),
        .width_sel(width_sel_w[1]),.rd_addr(rd_addr_w[1]),
        .fsm_state(fsm_state_w[1]),.done(done_w[1]));

    group2_fifo_ctrl #(.W(28), .H(28), .STRIDE(1), .AW(12)) dut2 (
        .clk(clk),.rst(rst),.start(start_r[2]),
        .shift_and_load(shift_and_load_w[2]),.padding_sel(padding_sel_w[2]),
        .width_sel(width_sel_w[2]),.rd_addr(rd_addr_w[2]),
        .fsm_state(fsm_state_w[2]),.done(done_w[2]));

    group2_fifo_ctrl #(.W(14), .H(14), .STRIDE(2), .AW(12)) dut3 (
        .clk(clk),.rst(rst),.start(start_r[3]),
        .shift_and_load(shift_and_load_w[3]),.padding_sel(padding_sel_w[3]),
        .width_sel(width_sel_w[3]),.rd_addr(rd_addr_w[3]),
        .fsm_state(fsm_state_w[3]),.done(done_w[3]));

    group2_fifo_ctrl #(.W(28), .H(28), .STRIDE(2), .AW(12)) dut4 (
        .clk(clk),.rst(rst),.start(start_r[4]),
        .shift_and_load(shift_and_load_w[4]),.padding_sel(padding_sel_w[4]),
        .width_sel(width_sel_w[4]),.rd_addr(rd_addr_w[4]),
        .fsm_state(fsm_state_w[4]),.done(done_w[4]));

    group2_fifo_ctrl #(.W(56), .H(56), .STRIDE(2), .AW(12)) dut5 (
        .clk(clk),.rst(rst),.start(start_r[5]),
        .shift_and_load(shift_and_load_w[5]),.padding_sel(padding_sel_w[5]),
        .width_sel(width_sel_w[5]),.rd_addr(rd_addr_w[5]),
        .fsm_state(fsm_state_w[5]),.done(done_w[5]));

    // ---- Parse temporaries ----
    integer fd, r, scan_r;
    reg [8*1024-1:0] cur_line;
    integer pass_count, fail_count, n_cases, dump_count;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    integer rd_W, rd_H, rd_STRIDE;
    integer e_sl, e_ps, e_state, e_rd, e_done;
    integer dut_idx;
    integer step_pass, cyc;
    // Observed signals (selected from active DUT)
    integer obs_sl, obs_ps, obs_state, obs_rd, obs_done;

    // ====================================================================
    task select_dut;
        input integer idx;
        begin
            obs_sl    = shift_and_load_w[idx];
            obs_ps    = padding_sel_w[idx];
            obs_state = fsm_state_w[idx];
            obs_rd    = rd_addr_w[idx];
            obs_done  = done_w[idx];
        end
    endtask

    integer i;
    initial begin
        pass_count = 0;
        fail_count = 0;
        n_cases    = 0;
        dump_count = 0;
        rst        = 1'b1;
        for (i = 0; i < N_DUTS; i = i + 1)
            start_r[i] = 1'b0;

        $display("=========================================================");
        $display("group2_fifo_ctrl Testbench");
        $display("=========================================================");

        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/group2/vectors/group2_fifo_ctrl_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/group2/vectors/group2_fifo_ctrl_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./group2_fifo_ctrl_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open group2_fifo_ctrl_vectors.hex"); $finish;
        end

        #20; @(negedge clk); rst = 1'b0;
        @(negedge clk);

        dut_idx = 0;

        begin : test_loop
            while (!$feof(fd) && dut_idx < N_DUTS) begin

                // Skip to header line (3 tokens: W H STRIDE)
                begin : find_header
                    while (!$feof(fd)) begin
                        r = $fgets(cur_line, fd);
                        if (r == 0) disable test_loop;
                        scan_r = $sscanf(cur_line, "%d %d %d", rd_W, rd_H, rd_STRIDE);
                        if (scan_r == 3) disable find_header;
                    end
                end
                if ($feof(fd)) disable test_loop;

                // Reset DUT between cases
                @(negedge clk); rst = 1'b1;
                @(negedge clk); rst = 1'b0;
                @(negedge clk);

                // Assert start for one cycle
                start_r[dut_idx] = 1'b1;
                @(posedge clk); #1;
                start_r[dut_idx] = 1'b0;

                cyc = 0;

                begin : data_loop
                    while (!$feof(fd)) begin
                        r = $fgets(cur_line, fd);
                        if (r == 0) disable data_loop;
                        scan_r = $sscanf(cur_line, "%d %d %d %d %d",
                            e_sl, e_ps, e_state, e_rd, e_done);
                        if (scan_r != 5) begin
                            if (cyc > 0) disable data_loop;
                        end else begin
                            // Read DUT outputs (combinational after last posedge)
                            select_dut(dut_idx);

                            step_pass = 1;
                            if (obs_sl    !== e_sl)    step_pass = 0;
                            if (obs_ps    !== e_ps)    step_pass = 0;
                            if (obs_state !== e_state) step_pass = 0;
                            if (obs_rd    !== e_rd)    step_pass = 0;
                            if (obs_done  !== e_done)  step_pass = 0;

                            if (step_pass)
                                pass_count = pass_count + 1;
                            else begin
                                fail_count = fail_count + 1;
                                if (dump_count < 8) begin
                                    $display("FAIL case=%0d dut=%0d cyc=%0d W=%0d S=%0d",
                                        n_cases, dut_idx, cyc, rd_W, rd_STRIDE);
                                    $display("  sl: got=%0d exp=%0d  ps: got=%0d exp=%0d",
                                        obs_sl, e_sl, obs_ps, e_ps);
                                    $display("  state: got=%0d exp=%0d  rd: got=%0d exp=%0d  done: got=%0d exp=%0d",
                                        obs_state, e_state, obs_rd, e_rd, obs_done, e_done);
                                    dump_count = dump_count + 1;
                                end
                            end

                            if (e_done) disable data_loop;

                            cyc = cyc + 1;
                            @(posedge clk); #1;
                        end
                    end
                end // data_loop

                n_cases  = n_cases + 1;
                dut_idx  = dut_idx + 1;

            end // while
        end // test_loop

        $fclose(fd);
        $display("---------------------------------------------------------");
        $display("Tested %0d cases, %0d total cycle-checks",
                 n_cases, pass_count + fail_count);
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
// END tb_group2_fifo_ctrl.v
// =============================================================================
