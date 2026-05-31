// =============================================================================
// tb_avg_pool_core.v -- Self-checking testbench for Module 3.2
// -----------------------------------------------------------------------------
// Thesis Sec 5.5 / Figures 5.58, 5.59
//
// Ch 6.2.5 + 6.2.8 update: IN_W=27 (G3_CONV_OUT_W -- full-precision 1x1 output),
//   DATA_W=9 (G3_FM_W -- avgpool quantized output).
//   Vector file must be regenerated: input pixels are now 27-bit, outputs 9-bit.
//
// Vector file format per case:
//   Comment: // Case N
//   Header:  N_CHAN N_PIX   (e.g. "16 49")
//   N_PIX data lines: N_CHAN hex values (IN_W bits each)
//   Result line: N_CHAN hex expected outputs (DATA_W bits each)
//
// Timing:
//   acc_clr for 1 cycle to reset accumulators.
//   acc_en for N_PIX cycles, feeding one pixel per cycle.
//   result_we for 1 cycle to capture result.
//   results_flat checked 1 cycle after result_we.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_avg_pool_core;

    localparam integer N_CHAN = `G3_PW_PAR_FILT;   // 16
    localparam integer IN_W  = `G3_CONV_OUT_W;     // 27 (Ch 6.2.5+6.2.8: full-precision)
    localparam integer DATA_W = `G3_FM_W;           //  9 (Ch 6.2.8: quantized output)

    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg acc_en, acc_clr, result_we;
    reg signed [N_CHAN*IN_W-1:0]   data_in_flat;
    wire signed [N_CHAN*DATA_W-1:0] results_flat;

    avg_pool_core #(.N_CHAN(N_CHAN), .IN_W(IN_W), .DATA_W(DATA_W)) dut (
        .clk         (clk),
        .rst         (rst),
        .acc_en      (acc_en),
        .acc_clr     (acc_clr),
        .result_we   (result_we),
        .data_in_flat(data_in_flat),
        .results_flat(results_flat)
    );

    // ---- Test infrastructure ----
    integer fd, r, scan_r;
    reg [8*2048-1:0] cur_line;
    reg [8*512-1:0]  path_arg;
    integer have_arg;
    integer pass_count, fail_count, n_cases, dump_count;
    integer rd_nchan, rd_npix;
    integer cyc, ch_idx;

    // Per-channel expected results (DATA_W-bit outputs)
    reg [DATA_W-1:0] exp_out [0:15];

    // Input pixel temporaries (IN_W-bit per channel)
    reg [IN_W-1:0] t0,t1,t2,t3,t4,t5,t6,t7,
                   t8,t9,t10,t11,t12,t13,t14,t15;

    initial begin
        pass_count   = 0; fail_count = 0; n_cases = 0; dump_count = 0;
        rst          = 1'b1;
        acc_en       = 1'b0;
        acc_clr      = 1'b0;
        result_we    = 1'b0;
        data_in_flat = {(N_CHAN*IN_W){1'b0}};

        $display("=========================================================");
        $display("avg_pool_core Testbench (N_CHAN=%0d N_PIX=49)", N_CHAN);
        $display("Ch 6.2.5+6.2.8: IN_W=%0d DATA_W=%0d", IN_W, DATA_W);
        $display("=========================================================");

        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg) fd = $fopen(path_arg, "r");
            else fd = $fopen("tb/group3/vectors/avg_pool_vectors.hex", "r");
            if (fd == 0) fd = $fopen("../tb/group3/vectors/avg_pool_vectors.hex","r");
            if (fd == 0) fd = $fopen("./avg_pool_vectors.hex", "r");
        end
        if (fd == 0) begin $display("ERROR: cannot open vector file"); $finish; end

        #20; @(negedge clk); rst = 1'b0;
        @(negedge clk);

        begin : test_loop
            while (!$feof(fd)) begin

                // ---- Find header: N_CHAN N_PIX ----
                begin : find_header
                    while (!$feof(fd)) begin
                        r = $fgets(cur_line, fd);
                        if (r == 0) disable test_loop;
                        scan_r = $sscanf(cur_line, "%d %d", rd_nchan, rd_npix);
                        if (scan_r == 2 && rd_nchan == N_CHAN) disable find_header;
                    end
                end
                if ($feof(fd)) disable test_loop;

                // ---- Reset accumulator ----
                @(negedge clk); rst = 1'b1;
                @(negedge clk); rst = 1'b0;
                @(negedge clk);

                // ---- Accumulate N_PIX pixels ----
                acc_clr = 1'b1;
                @(posedge clk); #1;
                acc_clr = 1'b0;
                acc_en  = 1'b1;

                for (cyc = 0; cyc < rd_npix; cyc = cyc + 1) begin
                    r = $fgets(cur_line, fd);
                    scan_r = $sscanf(cur_line,
                        "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                        t0,t1,t2,t3,t4,t5,t6,t7,
                        t8,t9,t10,t11,t12,t13,t14,t15);
                    if (scan_r == 16) begin
                        data_in_flat[ 0*IN_W +: IN_W] = t0;
                        data_in_flat[ 1*IN_W +: IN_W] = t1;
                        data_in_flat[ 2*IN_W +: IN_W] = t2;
                        data_in_flat[ 3*IN_W +: IN_W] = t3;
                        data_in_flat[ 4*IN_W +: IN_W] = t4;
                        data_in_flat[ 5*IN_W +: IN_W] = t5;
                        data_in_flat[ 6*IN_W +: IN_W] = t6;
                        data_in_flat[ 7*IN_W +: IN_W] = t7;
                        data_in_flat[ 8*IN_W +: IN_W] = t8;
                        data_in_flat[ 9*IN_W +: IN_W] = t9;
                        data_in_flat[10*IN_W +: IN_W] = t10;
                        data_in_flat[11*IN_W +: IN_W] = t11;
                        data_in_flat[12*IN_W +: IN_W] = t12;
                        data_in_flat[13*IN_W +: IN_W] = t13;
                        data_in_flat[14*IN_W +: IN_W] = t14;
                        data_in_flat[15*IN_W +: IN_W] = t15;
                    end
                    @(posedge clk); #1;
                end

                acc_en = 1'b0;

                // ---- Read expected result line (DATA_W-bit outputs) ----
                begin : read_exp
                    reg [DATA_W-1:0] e0,e1,e2,e3,e4,e5,e6,e7,
                                     e8,e9,e10,e11,e12,e13,e14,e15;
                    r = $fgets(cur_line, fd);
                    scan_r = $sscanf(cur_line,
                        "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                        e0,e1,e2,e3,e4,e5,e6,e7,
                        e8,e9,e10,e11,e12,e13,e14,e15);
                    exp_out[0] = e0;  exp_out[1] = e1;  exp_out[2] = e2;
                    exp_out[3] = e3;  exp_out[4] = e4;  exp_out[5] = e5;
                    exp_out[6] = e6;  exp_out[7] = e7;  exp_out[8] = e8;
                    exp_out[9] = e9;  exp_out[10] = e10; exp_out[11] = e11;
                    exp_out[12] = e12; exp_out[13] = e13; exp_out[14] = e14;
                    exp_out[15] = e15;
                end

                // ---- Assert result_we to capture ----
                @(negedge clk);
                result_we = 1'b1;
                @(posedge clk); #1;
                result_we = 1'b0;

                // ---- Check all 16 channel outputs ----
                for (ch_idx = 0; ch_idx < N_CHAN; ch_idx = ch_idx + 1) begin
                    if (results_flat[ch_idx*DATA_W +: DATA_W] === exp_out[ch_idx])
                        pass_count = pass_count + 1;
                    else begin
                        fail_count = fail_count + 1;
                        if (dump_count < 8) begin
                            $display("FAIL case=%0d ch=%0d: got=%0d exp=%0d",
                                n_cases, ch_idx,
                                $signed(results_flat[ch_idx*DATA_W +: DATA_W]),
                                $signed(exp_out[ch_idx]));
                            dump_count = dump_count + 1;
                        end
                    end
                end

                n_cases = n_cases + 1;
                @(negedge clk);
            end
        end

        $fclose(fd);
        $display("---------------------------------------------------------");
        $display("Tested %0d cases, %0d total checks",
                 n_cases, pass_count + fail_count);
        $display("PASS: %0d / %0d", pass_count, pass_count + fail_count);
        $display("FAIL: %0d / %0d", fail_count, pass_count + fail_count);
        if (fail_count == 0) $display("RESULT: *** ALL TESTS PASSED ***");
        else                 $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
        $display("=========================================================");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_avg_pool_core.v
// =============================================================================
