// =============================================================================
// tb_conv1x1_ctrl.v -- Self-checking testbench for Module 2.9
// -----------------------------------------------------------------------------
// / Figures 5.48, 5.49, 5.50
//
// Vector file format per case:
// Line 1: W H N_ACC (3 decimal tokens)
// Per cycle (after start posedge): en acc_clr we wr_addr step_out done
// Blank line between cases.
//
// Timing: start asserted for 1 posedge -> cyc=0 checks DUT after start posedge.
// All DUT outputs (en, acc_clr, done registered; we/wr_addr/step_out combinational)
// are checked after each posedge.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_conv1x1_ctrl;

    // ---- Clock / reset ----
    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- DUT instances: W=7/14/28, H=same, N_ACC=7 ----
    localparam N_DUTS = 3;

    reg start_r [0:N_DUTS-1];

    wire en_0, en_1, en_2;
    wire acc_clr_0, acc_clr_1, acc_clr_2;
    wire we_0, we_1, we_2;
    wire [11:0] wa_0, wa_1, wa_2;
    wire [2:0]  st_0, st_1, st_2;
    wire dn_0, dn_1, dn_2;

    conv1x1_ctrl #(.W(7),  .H(7),  .N_ACC(7), .AW(12)) dut0 (
        .clk(clk),.rst(rst),.start(start_r[0]),
        .en(en_0),.acc_clr(acc_clr_0),.we(we_0),
        .wr_addr(wa_0),.step_out(st_0),.done(dn_0),.fsm_state());

    conv1x1_ctrl #(.W(14), .H(14), .N_ACC(7), .AW(12)) dut1 (
        .clk(clk),.rst(rst),.start(start_r[1]),
        .en(en_1),.acc_clr(acc_clr_1),.we(we_1),
        .wr_addr(wa_1),.step_out(st_1),.done(dn_1),.fsm_state());

    conv1x1_ctrl #(.W(28), .H(28), .N_ACC(7), .AW(12)) dut2 (
        .clk(clk),.rst(rst),.start(start_r[2]),
        .en(en_2),.acc_clr(acc_clr_2),.we(we_2),
        .wr_addr(wa_2),.step_out(st_2),.done(dn_2),.fsm_state());

    // ---- Signal selectors ----
    reg obs_en, obs_ac, obs_we, obs_dn;
    reg [11:0] obs_wa;
    reg [2:0]  obs_st;
    task select_dut;
        input integer idx;
        begin
            case (idx)
                0: begin obs_en=en_0; obs_ac=acc_clr_0; obs_we=we_0; obs_wa=wa_0; obs_st=st_0; obs_dn=dn_0; end
                1: begin obs_en=en_1; obs_ac=acc_clr_1; obs_we=we_1; obs_wa=wa_1; obs_st=st_1; obs_dn=dn_1; end
                2: begin obs_en=en_2; obs_ac=acc_clr_2; obs_we=we_2; obs_wa=wa_2; obs_st=st_2; obs_dn=dn_2; end
                default: begin obs_en=0; obs_ac=0; obs_we=0; obs_wa=0; obs_st=0; obs_dn=0; end
            endcase
        end
    endtask

    // ---- Test infrastructure ----
    integer fd, r, scan_r;
    reg [8*1024-1:0] cur_line;
    integer pass_count, fail_count, n_cases, dump_count, cyc;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    integer rd_W, rd_H, rd_N;
    integer e_en, e_ac, e_we, e_dn;
    integer e_wa, e_st;
    integer dut_idx, step_pass;
    integer i;

    initial begin
        pass_count = 0; fail_count = 0; n_cases = 0; dump_count = 0;
        rst = 1'b1;
        for (i = 0; i < N_DUTS; i = i+1) start_r[i] = 1'b0;

        $display("=========================================================");
        $display("conv1x1_ctrl Testbench");
        $display("=========================================================");

        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg) fd = $fopen(path_arg, "r");
            else fd = $fopen("tb/group2/vectors/conv1x1_ctrl_vectors.hex", "r");
            if (fd == 0) fd = $fopen("../tb/group2/vectors/conv1x1_ctrl_vectors.hex", "r");
            if (fd == 0) fd = $fopen("./conv1x1_ctrl_vectors.hex", "r");
        end
        if (fd == 0) begin $display("ERROR: cannot open vector file"); $finish; end

        #20; @(negedge clk); rst = 1'b0;
        @(negedge clk);

        dut_idx = 0;

        begin : test_loop
            while (!$feof(fd) && dut_idx < N_DUTS) begin

                begin : find_header
                    while (!$feof(fd)) begin
                        r = $fgets(cur_line, fd);
                        if (r == 0) disable test_loop;
                        scan_r = $sscanf(cur_line, "%d %d %d", rd_W, rd_H, rd_N);
                        if (scan_r == 3) disable find_header;
                    end
                end
                if ($feof(fd)) disable test_loop;

                @(negedge clk); rst = 1'b1;
                @(negedge clk); rst = 1'b0;
                @(negedge clk);

                start_r[dut_idx] = 1'b1;
                @(posedge clk); #1;
                start_r[dut_idx] = 1'b0;
                cyc = 0;

                begin : data_loop
                    while (!$feof(fd)) begin
                        r = $fgets(cur_line, fd);
                        if (r == 0) disable data_loop;
                        scan_r = $sscanf(cur_line, "%d %d %d %d %d %d",
                            e_en, e_ac, e_we, e_wa, e_st, e_dn);
                        if (scan_r != 6) begin
                            if (cyc > 0) disable data_loop;
                        end else begin
                            select_dut(dut_idx);

                            step_pass = 1;
                            if (obs_en !== e_en) step_pass = 0;
                            if (obs_ac !== e_ac) step_pass = 0;
                            if (obs_we !== e_we) step_pass = 0;
                            if (obs_wa !== e_wa) step_pass = 0;
                            if (obs_st !== e_st) step_pass = 0;
                            if (obs_dn !== e_dn) step_pass = 0;

                            if (step_pass)
                                pass_count = pass_count + 1;
                            else begin
                                fail_count = fail_count + 1;
                                if (dump_count < 8) begin
                                    $display("FAIL case=%0d dut=%0d cyc=%0d W=%0d",
                                        n_cases, dut_idx, cyc, rd_W);
                                    $display("  en:%0d/%0d ac:%0d/%0d we:%0d/%0d wa:%0d/%0d st:%0d/%0d dn:%0d/%0d",
                                        obs_en,e_en, obs_ac,e_ac, obs_we,e_we,
                                        obs_wa,e_wa, obs_st,e_st, obs_dn,e_dn);
                                    dump_count = dump_count + 1;
                                end
                            end

                            if (e_dn) disable data_loop;
                            cyc = cyc + 1;
                            @(posedge clk); #1;
                        end
                    end
                end

                n_cases  = n_cases + 1;
                dut_idx  = dut_idx + 1;
            end
        end

        $fclose(fd);
        $display("---------------------------------------------------------");
        $display("Tested %0d cases, %0d total checks", n_cases, pass_count+fail_count);
        $display("PASS: %0d / %0d", pass_count, pass_count+fail_count);
        $display("FAIL: %0d / %0d", fail_count, pass_count+fail_count);
        if (fail_count == 0) $display("RESULT: *** ALL TESTS PASSED ***");
        else                 $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
        $display("=========================================================");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_conv1x1_ctrl.v
// =============================================================================
