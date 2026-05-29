// =============================================================================
// tb_conv1x1_filter_unit.v -- Self-checking testbench for Module 2.4
// -----------------------------------------------------------------------------
//
//
// Ch 6.2.5 + 6.2.8 update: data=DATA_W=12 (G2_FM_W), weights=W_W=11 (G2_PW_WW),
// bias=BIAS_WD=13 (G2_BIAS_W), result=OUT_W=12 (G2_FM_W).
// Vector file must be regenerated in new bit widths.
//
// Vector file: N_ACC+1 = 8 lines per case
// Lines 0..6: d0..d28 w0..w28 (58 hex tokens: 29 x DATA_W + 29 x W_W)
// Line 7: bias expected (BIAS_WD + OUT_W)
//
// Pipeline timing (N_ACC=7):
// negedge 0: drive row0, acc_clr=1
// negedge 1: drive row1, acc_clr=1
// negedge 2..5: drive rows 2..5, acc_clr=0
// negedge 6: drive row6 + bias, acc_clr=0
// negedge 7: wait
// negedge 8: CHECK
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_conv1x1_filter_unit;

    localparam integer DATA_W  = `G2_FM_W;   // 12 (Ch 6.2.8: G2 FM input/output)
    localparam integer W_W     = `G2_PW_WW;  // 11 (Ch 6.2.5: PW weight)
    localparam integer BIAS_WD = `G2_BIAS_W; // 13 (Ch 6.2.5: PW bias)
    localparam integer OUT_W   = `G2_FM_W;   // 12 (same as DATA_W)
    localparam integer N_ACC   = 7;
    localparam integer N_CHAN  = 29;

    // ---- Clock / reset ----
    reg clk, rst, en, acc_clr;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- DUT ports ----
    reg signed [DATA_W-1:0] dut_d0,  dut_d1,  dut_d2,  dut_d3,  dut_d4,
                             dut_d5,  dut_d6,  dut_d7,  dut_d8,  dut_d9,
                             dut_d10, dut_d11, dut_d12, dut_d13, dut_d14,
                             dut_d15, dut_d16, dut_d17, dut_d18, dut_d19,
                             dut_d20, dut_d21, dut_d22, dut_d23, dut_d24,
                             dut_d25, dut_d26, dut_d27, dut_d28;
    reg signed [W_W-1:0]    dut_w0,  dut_w1,  dut_w2,  dut_w3,  dut_w4,
                             dut_w5,  dut_w6,  dut_w7,  dut_w8,  dut_w9,
                             dut_w10, dut_w11, dut_w12, dut_w13, dut_w14,
                             dut_w15, dut_w16, dut_w17, dut_w18, dut_w19,
                             dut_w20, dut_w21, dut_w22, dut_w23, dut_w24,
                             dut_w25, dut_w26, dut_w27, dut_w28;
    reg  signed [BIAS_WD-1:0] dut_bias;
    wire signed [OUT_W-1:0]   dut_result;

    conv1x1_filter_unit dut (
        .clk    (clk),
        .rst    (rst),
        .en     (en),
        .acc_clr(acc_clr),
        .d0 (dut_d0),  .d1 (dut_d1),  .d2 (dut_d2),  .d3 (dut_d3),  .d4 (dut_d4),
        .d5 (dut_d5),  .d6 (dut_d6),  .d7 (dut_d7),  .d8 (dut_d8),  .d9 (dut_d9),
        .d10(dut_d10), .d11(dut_d11), .d12(dut_d12), .d13(dut_d13), .d14(dut_d14),
        .d15(dut_d15), .d16(dut_d16), .d17(dut_d17), .d18(dut_d18), .d19(dut_d19),
        .d20(dut_d20), .d21(dut_d21), .d22(dut_d22), .d23(dut_d23), .d24(dut_d24),
        .d25(dut_d25), .d26(dut_d26), .d27(dut_d27), .d28(dut_d28),
        .w0 (dut_w0),  .w1 (dut_w1),  .w2 (dut_w2),  .w3 (dut_w3),  .w4 (dut_w4),
        .w5 (dut_w5),  .w6 (dut_w6),  .w7 (dut_w7),  .w8 (dut_w8),  .w9 (dut_w9),
        .w10(dut_w10), .w11(dut_w11), .w12(dut_w12), .w13(dut_w13), .w14(dut_w14),
        .w15(dut_w15), .w16(dut_w16), .w17(dut_w17), .w18(dut_w18), .w19(dut_w19),
        .w20(dut_w20), .w21(dut_w21), .w22(dut_w22), .w23(dut_w23), .w24(dut_w24),
        .w25(dut_w25), .w26(dut_w26), .w27(dut_w27), .w28(dut_w28),
        .bias  (dut_bias),
        .result(dut_result)
    );

    // ---- Parse temporaries for one row ----
    reg [DATA_W-1:0] p_d0,  p_d1,  p_d2,  p_d3,  p_d4,
                     p_d5,  p_d6,  p_d7,  p_d8,  p_d9,
                     p_d10, p_d11, p_d12, p_d13, p_d14,
                     p_d15, p_d16, p_d17, p_d18, p_d19,
                     p_d20, p_d21, p_d22, p_d23, p_d24,
                     p_d25, p_d26, p_d27, p_d28;
    reg [W_W-1:0]    p_w0,  p_w1,  p_w2,  p_w3,  p_w4,
                     p_w5,  p_w6,  p_w7,  p_w8,  p_w9,
                     p_w10, p_w11, p_w12, p_w13, p_w14,
                     p_w15, p_w16, p_w17, p_w18, p_w19,
                     p_w20, p_w21, p_w22, p_w23, p_w24,
                     p_w25, p_w26, p_w27, p_w28;
    reg [BIAS_WD-1:0] p_bias;
    reg [OUT_W-1:0]   p_exp;

    // Stored rows for all N_ACC accumulations
    reg [DATA_W-1:0] row_d [0:N_ACC-1][0:N_CHAN-1];
    reg [W_W-1:0]    row_w [0:N_ACC-1][0:N_CHAN-1];

    integer fd, r, scan_r;
    integer n_vectors, pass_count, fail_count, dump_count;
    integer row_idx;
    reg [8*512-1:0]  path_arg;
    integer have_arg;
    reg [8*2048-1:0] cur_line;

    // ====================================================================
    // Task: drive one row of data/weights onto DUT inputs
    // ====================================================================
    task drive_row;
        input integer k;
        begin
            dut_d0  = $signed(row_d[k][ 0]); dut_d1  = $signed(row_d[k][ 1]);
            dut_d2  = $signed(row_d[k][ 2]); dut_d3  = $signed(row_d[k][ 3]);
            dut_d4  = $signed(row_d[k][ 4]); dut_d5  = $signed(row_d[k][ 5]);
            dut_d6  = $signed(row_d[k][ 6]); dut_d7  = $signed(row_d[k][ 7]);
            dut_d8  = $signed(row_d[k][ 8]); dut_d9  = $signed(row_d[k][ 9]);
            dut_d10 = $signed(row_d[k][10]); dut_d11 = $signed(row_d[k][11]);
            dut_d12 = $signed(row_d[k][12]); dut_d13 = $signed(row_d[k][13]);
            dut_d14 = $signed(row_d[k][14]); dut_d15 = $signed(row_d[k][15]);
            dut_d16 = $signed(row_d[k][16]); dut_d17 = $signed(row_d[k][17]);
            dut_d18 = $signed(row_d[k][18]); dut_d19 = $signed(row_d[k][19]);
            dut_d20 = $signed(row_d[k][20]); dut_d21 = $signed(row_d[k][21]);
            dut_d22 = $signed(row_d[k][22]); dut_d23 = $signed(row_d[k][23]);
            dut_d24 = $signed(row_d[k][24]); dut_d25 = $signed(row_d[k][25]);
            dut_d26 = $signed(row_d[k][26]); dut_d27 = $signed(row_d[k][27]);
            dut_d28 = $signed(row_d[k][28]);
            dut_w0  = $signed(row_w[k][ 0]); dut_w1  = $signed(row_w[k][ 1]);
            dut_w2  = $signed(row_w[k][ 2]); dut_w3  = $signed(row_w[k][ 3]);
            dut_w4  = $signed(row_w[k][ 4]); dut_w5  = $signed(row_w[k][ 5]);
            dut_w6  = $signed(row_w[k][ 6]); dut_w7  = $signed(row_w[k][ 7]);
            dut_w8  = $signed(row_w[k][ 8]); dut_w9  = $signed(row_w[k][ 9]);
            dut_w10 = $signed(row_w[k][10]); dut_w11 = $signed(row_w[k][11]);
            dut_w12 = $signed(row_w[k][12]); dut_w13 = $signed(row_w[k][13]);
            dut_w14 = $signed(row_w[k][14]); dut_w15 = $signed(row_w[k][15]);
            dut_w16 = $signed(row_w[k][16]); dut_w17 = $signed(row_w[k][17]);
            dut_w18 = $signed(row_w[k][18]); dut_w19 = $signed(row_w[k][19]);
            dut_w20 = $signed(row_w[k][20]); dut_w21 = $signed(row_w[k][21]);
            dut_w22 = $signed(row_w[k][22]); dut_w23 = $signed(row_w[k][23]);
            dut_w24 = $signed(row_w[k][24]); dut_w25 = $signed(row_w[k][25]);
            dut_w26 = $signed(row_w[k][26]); dut_w27 = $signed(row_w[k][27]);
            dut_w28 = $signed(row_w[k][28]);
        end
    endtask

    // ====================================================================
    initial begin
        n_vectors  = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;
        rst = 1'b1; en = 1'b0; acc_clr = 1'b1;
        dut_d0=0;dut_d1=0;dut_d2=0;dut_d3=0;dut_d4=0;dut_d5=0;dut_d6=0;
        dut_d7=0;dut_d8=0;dut_d9=0;dut_d10=0;dut_d11=0;dut_d12=0;dut_d13=0;
        dut_d14=0;dut_d15=0;dut_d16=0;dut_d17=0;dut_d18=0;dut_d19=0;dut_d20=0;
        dut_d21=0;dut_d22=0;dut_d23=0;dut_d24=0;dut_d25=0;dut_d26=0;dut_d27=0;
        dut_d28=0;
        dut_w0=0;dut_w1=0;dut_w2=0;dut_w3=0;dut_w4=0;dut_w5=0;dut_w6=0;
        dut_w7=0;dut_w8=0;dut_w9=0;dut_w10=0;dut_w11=0;dut_w12=0;dut_w13=0;
        dut_w14=0;dut_w15=0;dut_w16=0;dut_w17=0;dut_w18=0;dut_w19=0;dut_w20=0;
        dut_w21=0;dut_w22=0;dut_w23=0;dut_w24=0;dut_w25=0;dut_w26=0;dut_w27=0;
        dut_w28=0;
        dut_bias = 0;

        $display("=========================================================");
        $display("conv1x1_filter_unit Testbench");
        $display("Ch 6.2.5+6.2.8: DATA_W=%0d W_W=%0d BIAS_WD=%0d OUT_W=%0d",
                 DATA_W, W_W, BIAS_WD, OUT_W);
        $display("=========================================================");

        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/group2/vectors/conv1x1_filter_unit_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/group2/vectors/conv1x1_filter_unit_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./conv1x1_filter_unit_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open conv1x1_filter_unit_vectors.hex");
            $finish;
        end

        #20; @(negedge clk); rst = 1'b0; en = 1'b1;
        @(negedge clk);

        begin : main_loop
            while (!$feof(fd)) begin

                // ---- Read N_ACC rows of 58 tokens each ----
                begin : read_rows
                    integer rows_read;
                    rows_read = 0;
                    while (rows_read < N_ACC && !$feof(fd)) begin
                        r = $fgets(cur_line, fd);
                        if (r == 0) disable main_loop;
                        scan_r = $sscanf(cur_line,
                            {"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                             " %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                             " %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                             " %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h"},
                            p_d0, p_d1, p_d2, p_d3, p_d4, p_d5, p_d6, p_d7, p_d8,
                            p_d9, p_d10,p_d11,p_d12,p_d13,p_d14,
                            p_d15,p_d16,p_d17,p_d18,p_d19,p_d20,p_d21,p_d22,p_d23,
                            p_d24,p_d25,p_d26,p_d27,p_d28,
                            p_w0, p_w1, p_w2, p_w3, p_w4, p_w5, p_w6, p_w7, p_w8,
                            p_w9, p_w10,p_w11,p_w12,p_w13,p_w14,
                            p_w15,p_w16,p_w17,p_w18,p_w19,p_w20,p_w21,p_w22,p_w23,
                            p_w24,p_w25,p_w26,p_w27,p_w28);
                        if (scan_r == 2*N_CHAN) begin
                            row_d[rows_read][ 0]=p_d0;  row_d[rows_read][ 1]=p_d1;
                            row_d[rows_read][ 2]=p_d2;  row_d[rows_read][ 3]=p_d3;
                            row_d[rows_read][ 4]=p_d4;  row_d[rows_read][ 5]=p_d5;
                            row_d[rows_read][ 6]=p_d6;  row_d[rows_read][ 7]=p_d7;
                            row_d[rows_read][ 8]=p_d8;  row_d[rows_read][ 9]=p_d9;
                            row_d[rows_read][10]=p_d10; row_d[rows_read][11]=p_d11;
                            row_d[rows_read][12]=p_d12; row_d[rows_read][13]=p_d13;
                            row_d[rows_read][14]=p_d14; row_d[rows_read][15]=p_d15;
                            row_d[rows_read][16]=p_d16; row_d[rows_read][17]=p_d17;
                            row_d[rows_read][18]=p_d18; row_d[rows_read][19]=p_d19;
                            row_d[rows_read][20]=p_d20; row_d[rows_read][21]=p_d21;
                            row_d[rows_read][22]=p_d22; row_d[rows_read][23]=p_d23;
                            row_d[rows_read][24]=p_d24; row_d[rows_read][25]=p_d25;
                            row_d[rows_read][26]=p_d26; row_d[rows_read][27]=p_d27;
                            row_d[rows_read][28]=p_d28;
                            row_w[rows_read][ 0]=p_w0;  row_w[rows_read][ 1]=p_w1;
                            row_w[rows_read][ 2]=p_w2;  row_w[rows_read][ 3]=p_w3;
                            row_w[rows_read][ 4]=p_w4;  row_w[rows_read][ 5]=p_w5;
                            row_w[rows_read][ 6]=p_w6;  row_w[rows_read][ 7]=p_w7;
                            row_w[rows_read][ 8]=p_w8;  row_w[rows_read][ 9]=p_w9;
                            row_w[rows_read][10]=p_w10; row_w[rows_read][11]=p_w11;
                            row_w[rows_read][12]=p_w12; row_w[rows_read][13]=p_w13;
                            row_w[rows_read][14]=p_w14; row_w[rows_read][15]=p_w15;
                            row_w[rows_read][16]=p_w16; row_w[rows_read][17]=p_w17;
                            row_w[rows_read][18]=p_w18; row_w[rows_read][19]=p_w19;
                            row_w[rows_read][20]=p_w20; row_w[rows_read][21]=p_w21;
                            row_w[rows_read][22]=p_w22; row_w[rows_read][23]=p_w23;
                            row_w[rows_read][24]=p_w24; row_w[rows_read][25]=p_w25;
                            row_w[rows_read][26]=p_w26; row_w[rows_read][27]=p_w27;
                            row_w[rows_read][28]=p_w28;
                            rows_read = rows_read + 1;
                        end
                    end // while rows_read < N_ACC
                    if (rows_read < N_ACC) disable main_loop;
                end // read_rows

                // ---- Read bias + expected ----
                begin : read_bias
                    integer bias_ok;
                    bias_ok = 0;
                    while (!bias_ok && !$feof(fd)) begin
                        r = $fgets(cur_line, fd);
                        if (r == 0) disable main_loop;
                        if ($sscanf(cur_line, "%h %h", p_bias, p_exp) == 2)
                            bias_ok = 1;
                    end
                    if (!bias_ok) disable main_loop;
                end // read_bias

                // negedge 0: row0, acc_clr=1
                @(negedge clk);
                acc_clr = 1'b1;
                drive_row(0);

                // negedge 1: row1, acc_clr=1
                @(negedge clk);
                acc_clr = 1'b1;
                drive_row(1);

                // negedge 2..N_ACC-2: acc_clr=0
                begin : drive_rows
                    integer k;
                    for (k = 2; k < N_ACC - 1; k = k + 1) begin
                        @(negedge clk);
                        acc_clr = 1'b0;
                        drive_row(k);
                    end
                end

                // negedge N_ACC-1: last row + bias, acc_clr=0
                @(negedge clk);
                acc_clr = 1'b0;
                drive_row(N_ACC - 1);
                dut_bias = $signed(p_bias);

                // negedge N_ACC: wait
                @(negedge clk);

                // negedge N_ACC+1: CHECK
                @(negedge clk);
                if (dut_result === $signed(p_exp)) begin
                    pass_count = pass_count + 1;
                end else begin
                    fail_count = fail_count + 1;
                    if (dump_count < 10) begin
                        $display("FAIL #%0d: bias=%0d got=%0d exp=%0d",
                            n_vectors, $signed(p_bias), dut_result, $signed(p_exp));
                        dump_count = dump_count + 1;
                    end
                end
                n_vectors = n_vectors + 1;

            end // while !feof
        end // main_loop

        $fclose(fd);
        $display("---------------------------------------------------------");
        $display("Tested %0d vectors", n_vectors);
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
// END tb_conv1x1_filter_unit.v
// =============================================================================
