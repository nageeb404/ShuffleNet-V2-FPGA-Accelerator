// =============================================================================
// tb_dw_conv3x3_ctrl.v -- Self-checking testbench for Module 2.8
// -----------------------------------------------------------------------------
// Thesis Sec 5.4.7.2 / Figure 5.46
//
// Connects dw_conv3x3_ctrl to a real group2_fifo_ctrl instance and verifies:
//   - start_fifo asserted for exactly 1 cycle on start
//   - en tracks shift_and_load from FIFO ctrl (when RUNNING)
//   - data_valid matches FIFO PROCESS state (fsm_state_fifo == 3)
//   - wr_addr increments each data_valid cycle
//   - done arrives exactly when done_fifo arrives
//
// Vector file format per case:
//   Line 1: W H STRIDE (3 decimal tokens)
//   Per cycle (start cycle through done): start_fifo en data_valid wr_addr done
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_dw_conv3x3_ctrl;

    // ---- Clock / reset ----
    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- One FIFO ctrl + DW ctrl pair per config ----
    // Configs: (W=7,H=7,S=1), (W=14,H=14,S=1), (W=28,H=28,S=2), (W=56,H=56,S=2)
    localparam N_DUTS = 4;

    reg start_r [0:N_DUTS-1];

    // group2_fifo_ctrl outputs (per DUT)
    wire shift_load_0, shift_load_1, shift_load_2, shift_load_3;
    wire [2:0] fifo_st_0, fifo_st_1, fifo_st_2, fifo_st_3;
    wire done_fifo_0, done_fifo_1, done_fifo_2, done_fifo_3;

    // dw_conv3x3_ctrl outputs (per DUT)
    wire sf_0, sf_1, sf_2, sf_3;         // start_fifo
    wire en_0, en_1, en_2, en_3;
    wire dv_0, dv_1, dv_2, dv_3;         // data_valid
    wire [10:0] wa_0, wa_1, wa_2, wa_3;  // wr_addr
    wire we_0, we_1, we_2, we_3;
    wire dn_0, dn_1, dn_2, dn_3;         // done

    // ---- DUT 0: W=7, H=7, STRIDE=1 ----
    group2_fifo_ctrl #(.W(7), .H(7), .STRIDE(1), .AW(8)) fifo_c0 (
        .clk(clk),.rst(rst),.start(sf_0),
        .shift_and_load(shift_load_0),.padding_sel(),.width_sel(),.rd_addr(),
        .fsm_state(fifo_st_0),.done(done_fifo_0));
    dw_conv3x3_ctrl #(.AW(11)) dw_c0 (
        .clk(clk),.rst(rst),.start(start_r[0]),
        .fifo_state(fifo_st_0),.done_fifo(done_fifo_0),.shift_and_load(shift_load_0),
        .start_fifo(sf_0),.en(en_0),.data_valid(dv_0),.wr_addr(wa_0),.we(we_0),
        .done(dn_0),.fsm_state());

    // ---- DUT 1: W=14, H=14, STRIDE=1 ----
    group2_fifo_ctrl #(.W(14), .H(14), .STRIDE(1), .AW(8)) fifo_c1 (
        .clk(clk),.rst(rst),.start(sf_1),
        .shift_and_load(shift_load_1),.padding_sel(),.width_sel(),.rd_addr(),
        .fsm_state(fifo_st_1),.done(done_fifo_1));
    dw_conv3x3_ctrl #(.AW(11)) dw_c1 (
        .clk(clk),.rst(rst),.start(start_r[1]),
        .fifo_state(fifo_st_1),.done_fifo(done_fifo_1),.shift_and_load(shift_load_1),
        .start_fifo(sf_1),.en(en_1),.data_valid(dv_1),.wr_addr(wa_1),.we(we_1),
        .done(dn_1),.fsm_state());

    // ---- DUT 2: W=28, H=28, STRIDE=2 ----
    group2_fifo_ctrl #(.W(28), .H(28), .STRIDE(2), .AW(8)) fifo_c2 (
        .clk(clk),.rst(rst),.start(sf_2),
        .shift_and_load(shift_load_2),.padding_sel(),.width_sel(),.rd_addr(),
        .fsm_state(fifo_st_2),.done(done_fifo_2));
    dw_conv3x3_ctrl #(.AW(11)) dw_c2 (
        .clk(clk),.rst(rst),.start(start_r[2]),
        .fifo_state(fifo_st_2),.done_fifo(done_fifo_2),.shift_and_load(shift_load_2),
        .start_fifo(sf_2),.en(en_2),.data_valid(dv_2),.wr_addr(wa_2),.we(we_2),
        .done(dn_2),.fsm_state());

    // ---- DUT 3: W=56, H=56, STRIDE=2 ----
    group2_fifo_ctrl #(.W(56), .H(56), .STRIDE(2), .AW(12)) fifo_c3 (
        .clk(clk),.rst(rst),.start(sf_3),
        .shift_and_load(shift_load_3),.padding_sel(),.width_sel(),.rd_addr(),
        .fsm_state(fifo_st_3),.done(done_fifo_3));
    dw_conv3x3_ctrl #(.AW(11)) dw_c3 (
        .clk(clk),.rst(rst),.start(start_r[3]),
        .fifo_state(fifo_st_3),.done_fifo(done_fifo_3),.shift_and_load(shift_load_3),
        .start_fifo(sf_3),.en(en_3),.data_valid(dv_3),.wr_addr(wa_3),.we(we_3),
        .done(dn_3),.fsm_state());

    // ---- Signal selectors (indexed by active DUT) ----
    reg obs_sf, obs_en, obs_dv, obs_dn;
    reg [10:0] obs_wa;
    task select_dut;
        input integer idx;
        begin
            case (idx)
                0: begin obs_sf=sf_0; obs_en=en_0; obs_dv=dv_0; obs_wa=wa_0; obs_dn=dn_0; end
                1: begin obs_sf=sf_1; obs_en=en_1; obs_dv=dv_1; obs_wa=wa_1; obs_dn=dn_1; end
                2: begin obs_sf=sf_2; obs_en=en_2; obs_dv=dv_2; obs_wa=wa_2; obs_dn=dn_2; end
                3: begin obs_sf=sf_3; obs_en=en_3; obs_dv=dv_3; obs_wa=wa_3; obs_dn=dn_3; end
                default: begin obs_sf=0; obs_en=0; obs_dv=0; obs_wa=0; obs_dn=0; end
            endcase
        end
    endtask

    // ---- Test infrastructure ----
    integer fd, r, scan_r;
    reg [8*1024-1:0] cur_line;
    integer pass_count, fail_count, n_cases, dump_count, cyc;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    integer rd_W, rd_H, rd_STRIDE;
    integer e_sf, e_en, e_dv, e_wa, e_dn;
    integer dut_idx, step_pass;
    integer i;

    initial begin
        pass_count = 0; fail_count = 0; n_cases = 0; dump_count = 0;
        rst = 1'b1;
        for (i = 0; i < N_DUTS; i = i+1) start_r[i] = 1'b0;

        $display("=========================================================");
        $display("dw_conv3x3_ctrl Testbench");
        $display("=========================================================");

        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg) fd = $fopen(path_arg, "r");
            else fd = $fopen("tb/group2/vectors/dw_conv3x3_ctrl_vectors.hex", "r");
            if (fd == 0) fd = $fopen("../tb/group2/vectors/dw_conv3x3_ctrl_vectors.hex", "r");
            if (fd == 0) fd = $fopen("../../../../../../tb/group2/vectors/dw_conv3x3_ctrl_vectors.hex", "r");
            if (fd == 0) fd = $fopen("./dw_conv3x3_ctrl_vectors.hex", "r");
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
                        scan_r = $sscanf(cur_line, "%d %d %d", rd_W, rd_H, rd_STRIDE);
                        if (scan_r == 3) disable find_header;
                    end
                end
                if ($feof(fd)) disable test_loop;

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
                            e_sf, e_en, e_dv, e_wa, e_dn);
                        if (scan_r != 5) begin
                            if (cyc > 0) disable data_loop;
                        end else begin
                            select_dut(dut_idx);

                            step_pass = 1;
                            if (obs_sf !== e_sf) step_pass = 0;
                            if (obs_en !== e_en) step_pass = 0;
                            if (obs_dv !== e_dv) step_pass = 0;
                            if (obs_wa !== e_wa) step_pass = 0;
                            if (obs_dn !== e_dn) step_pass = 0;

                            if (step_pass)
                                pass_count = pass_count + 1;
                            else begin
                                fail_count = fail_count + 1;
                                if (dump_count < 8) begin
                                    $display("FAIL case=%0d dut=%0d cyc=%0d W=%0d S=%0d",
                                        n_cases, dut_idx, cyc, rd_W, rd_STRIDE);
                                    $display("  sf: got=%0d exp=%0d  en: got=%0d exp=%0d",
                                        obs_sf, e_sf, obs_en, e_en);
                                    $display("  dv: got=%0d exp=%0d  wa: got=%0d exp=%0d  dn: got=%0d exp=%0d",
                                        obs_dv, e_dv, obs_wa, e_wa, obs_dn, e_dn);
                                    dump_count = dump_count + 1;
                                end
                            end

                            if (e_dn) disable data_loop;
                            cyc = cyc + 1;
                            @(posedge clk); #1;
                        end
                    end
                end

                n_cases = n_cases + 1;
                dut_idx = dut_idx + 1;
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
// END tb_dw_conv3x3_ctrl.v
// =============================================================================
