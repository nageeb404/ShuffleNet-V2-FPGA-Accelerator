// =============================================================================
// tb_conv1x1_core.v -- Self-checking testbench for Module 2.5
// -----------------------------------------------------------------------------
// Thesis Sec 5.4.1.2 / Table 5.4
//
// Ch 6.2.5 + 6.2.8 update: IN_W=12 (data), W_W=11 (weights), BIAS_WD=13,
//   OUT_W=12 (results). Vector file must be regenerated in new bit widths.
//
// Vector file format per test case (N_ACC=7, N_FILT=58, N_CHAN=29):
//   For k=0..6:
//     1 line: d0..d28    (29 x IN_W-bit hex tokens)
//     58 lines: w0..w28  (29 x W_W-bit hex tokens, per-filter)
//   Then 58 lines: bias expected  (BIAS_WD + OUT_W, per filter)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_conv1x1_core;

    localparam integer IN_W    = `G2_FM_W;           // 12 (Ch 6.2.8)
    localparam integer W_W     = `G2_PW_WW;          // 11 (Ch 6.2.5)
    localparam integer BIAS_WD = `G2_BIAS_W;         // 13 (Ch 6.2.5)
    localparam integer OUT_W   = `G2_FM_W;           // 12 (Ch 6.2.8)
    localparam integer N_FILT  = `G2_PW_PAR_FILT;   // 58
    localparam integer N_CHAN  = `G2_PW_PAR_CHAN;    // 29
    localparam integer N_ACC   = 7;

    // ---- Clock / reset ----
    reg clk, rst, en, acc_clr;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- DUT buses ----
    reg  signed [IN_W-1:0] d0,  d1,  d2,  d3,  d4,
                            d5,  d6,  d7,  d8,  d9,
                            d10, d11, d12, d13, d14,
                            d15, d16, d17, d18, d19,
                            d20, d21, d22, d23, d24,
                            d25, d26, d27, d28;
    reg  [N_FILT*N_CHAN*W_W-1:0]  weights_flat;
    reg  [N_FILT*BIAS_WD-1:0]     biases_flat;
    wire [N_FILT*OUT_W-1:0]        results_flat;

    conv1x1_core #(
        .N_FILT (N_FILT),
        .N_CHAN (N_CHAN),
        .IN_W   (IN_W),
        .W_W    (W_W),
        .BIAS_WD(BIAS_WD),
        .OUT_W  (OUT_W)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .en          (en),
        .acc_clr     (acc_clr),
        .d0 (d0),  .d1 (d1),  .d2 (d2),  .d3 (d3),  .d4 (d4),
        .d5 (d5),  .d6 (d6),  .d7 (d7),  .d8 (d8),  .d9 (d9),
        .d10(d10), .d11(d11), .d12(d12), .d13(d13), .d14(d14),
        .d15(d15), .d16(d16), .d17(d17), .d18(d18), .d19(d19),
        .d20(d20), .d21(d21), .d22(d22), .d23(d23), .d24(d24),
        .d25(d25), .d26(d26), .d27(d27), .d28(d28),
        .weights_flat(weights_flat),
        .biases_flat (biases_flat),
        .results_flat(results_flat)
    );

    // ---- Parse temporaries ----
    reg [IN_W-1:0]    pd [0:N_CHAN-1];
    reg [W_W-1:0]     pw [0:N_CHAN-1];
    reg [BIAS_WD-1:0] pb;
    reg [OUT_W-1:0]   pe;
    reg [OUT_W-1:0]   exp_results [0:N_FILT-1];

    integer fd, r, scan_r;
    integer n_vectors, pass_count, fail_count, dump_count;
    integer k, flt, ch, all_pass, d_ok, w_ok, b_ok, flt_idx;
    reg [8*512-1:0]  path_arg;
    integer have_arg;
    reg [8*1024-1:0] cur_line;

    // ====================================================================
    task drive_data;
        begin
            d0  = $signed(pd[ 0]); d1  = $signed(pd[ 1]); d2  = $signed(pd[ 2]);
            d3  = $signed(pd[ 3]); d4  = $signed(pd[ 4]); d5  = $signed(pd[ 5]);
            d6  = $signed(pd[ 6]); d7  = $signed(pd[ 7]); d8  = $signed(pd[ 8]);
            d9  = $signed(pd[ 9]); d10 = $signed(pd[10]); d11 = $signed(pd[11]);
            d12 = $signed(pd[12]); d13 = $signed(pd[13]); d14 = $signed(pd[14]);
            d15 = $signed(pd[15]); d16 = $signed(pd[16]); d17 = $signed(pd[17]);
            d18 = $signed(pd[18]); d19 = $signed(pd[19]); d20 = $signed(pd[20]);
            d21 = $signed(pd[21]); d22 = $signed(pd[22]); d23 = $signed(pd[23]);
            d24 = $signed(pd[24]); d25 = $signed(pd[25]); d26 = $signed(pd[26]);
            d27 = $signed(pd[27]); d28 = $signed(pd[28]);
        end
    endtask

    task read_data_line;
        output integer ok;
        begin : rdl
            ok = 0;
            while (!ok && !$feof(fd)) begin
                r = $fgets(cur_line, fd);
                if (r == 0) disable rdl;
                scan_r = $sscanf(cur_line,
                    "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                    pd[ 0],pd[ 1],pd[ 2],pd[ 3],pd[ 4],pd[ 5],pd[ 6],pd[ 7],pd[ 8],pd[ 9],
                    pd[10],pd[11],pd[12],pd[13],pd[14],pd[15],pd[16],pd[17],pd[18],pd[19],
                    pd[20],pd[21],pd[22],pd[23],pd[24],pd[25],pd[26],pd[27],pd[28]);
                if (scan_r == N_CHAN) ok = 1;
            end
        end
    endtask

    task read_weight_line;
        output integer ok;
        begin : rwl
            ok = 0;
            while (!ok && !$feof(fd)) begin
                r = $fgets(cur_line, fd);
                if (r == 0) disable rwl;
                scan_r = $sscanf(cur_line,
                    "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                    pw[ 0],pw[ 1],pw[ 2],pw[ 3],pw[ 4],pw[ 5],pw[ 6],pw[ 7],pw[ 8],pw[ 9],
                    pw[10],pw[11],pw[12],pw[13],pw[14],pw[15],pw[16],pw[17],pw[18],pw[19],
                    pw[20],pw[21],pw[22],pw[23],pw[24],pw[25],pw[26],pw[27],pw[28]);
                if (scan_r == N_CHAN) ok = 1;
            end
        end
    endtask

    // ====================================================================
    initial begin
        n_vectors  = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;
        rst        = 1'b1;
        en         = 1'b0;
        acc_clr    = 1'b1;
        weights_flat = {(N_FILT*N_CHAN*W_W){1'b0}};
        biases_flat  = {(N_FILT*BIAS_WD){1'b0}};
        d0=0;d1=0;d2=0;d3=0;d4=0;d5=0;d6=0;d7=0;d8=0;d9=0;
        d10=0;d11=0;d12=0;d13=0;d14=0;d15=0;d16=0;d17=0;d18=0;d19=0;
        d20=0;d21=0;d22=0;d23=0;d24=0;d25=0;d26=0;d27=0;d28=0;

        $display("=========================================================");
        $display("conv1x1_core Testbench  N_FILT=%0d  N_CHAN=%0d  N_ACC=%0d",
                 N_FILT, N_CHAN, N_ACC);
        $display("Ch 6.2.5+6.2.8: IN_W=%0d W_W=%0d BIAS_WD=%0d OUT_W=%0d",
                 IN_W, W_W, BIAS_WD, OUT_W);
        $display("=========================================================");

        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/group2/vectors/conv1x1_core_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/group2/vectors/conv1x1_core_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./conv1x1_core_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open conv1x1_core_vectors.hex"); $finish;
        end

        #20; @(negedge clk); rst = 1'b0; en = 1'b1;
        @(negedge clk);

        begin : test_loop
            while (!$feof(fd)) begin

                begin : drive_loop
                    integer s;
                    for (s = 0; s < N_ACC && !$feof(fd); s = s + 1) begin

                        read_data_line(d_ok);
                        if (!d_ok) disable test_loop;

                        for (flt = 0; flt < N_FILT && !$feof(fd); flt = flt + 1) begin
                            read_weight_line(w_ok);
                            if (!w_ok) disable test_loop;
                            for (ch = 0; ch < N_CHAN; ch = ch + 1)
                                weights_flat[(flt*N_CHAN+ch)*W_W +: W_W] = $signed(pw[ch]);
                        end

                        drive_data;
                        if (s < 2)
                            acc_clr = 1'b1;
                        else
                            acc_clr = 1'b0;

                        if (s == N_ACC - 1) begin
                            flt_idx = 0;
                            while (flt_idx < N_FILT && !$feof(fd)) begin
                                r = $fgets(cur_line, fd);
                                if (r == 0) disable test_loop;
                                if ($sscanf(cur_line, "%h %h", pb, pe) == 2) begin
                                    biases_flat[flt_idx*BIAS_WD +: BIAS_WD] = $signed(pb);
                                    exp_results[flt_idx] = pe;
                                    flt_idx = flt_idx + 1;
                                end
                            end
                        end

                        @(negedge clk);
                    end
                end // drive_loop

                @(negedge clk);

                all_pass = 1;
                for (flt = 0; flt < N_FILT; flt = flt + 1) begin
                    if (results_flat[flt*OUT_W +: OUT_W] !== $signed(exp_results[flt])) begin
                        all_pass = 0;
                        if (dump_count < 5) begin
                            $display("FAIL vec=%0d flt=%0d: got=%0d exp=%0d",
                                n_vectors, flt,
                                $signed(results_flat[flt*OUT_W +: OUT_W]),
                                $signed(exp_results[flt]));
                            dump_count = dump_count + 1;
                        end
                    end
                end
                if (all_pass) pass_count = pass_count + 1;
                else          fail_count = fail_count + 1;
                n_vectors = n_vectors + 1;

            end // while !feof
        end // test_loop

        $fclose(fd);
        $display("---------------------------------------------------------");
        $display("Tested %0d vectors (%0d filter-checks each)", n_vectors, N_FILT);
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
// END tb_conv1x1_core.v
// =============================================================================
