// =============================================================================
// tb_dw_conv3x3_core.v -- Self-checking testbench for Module 2.2
// -----------------------------------------------------------------------------
// / Table 5.3
//
// Ch 6.2.5 + 6.2.8 update: IN_W=10 (data), W_W=15 (weights), BIAS_WD=15,
// OUT_W=12 (results). Vector file must be regenerated in new bit widths.
//
// Vector file format: 58 lines per test case (one line per filter).
// Each line: d0..d8 w0..w8 bias expected (9+9+1+1 = 20 hex tokens)
// Cases are separated by blank lines; comment lines start with '/'.
//
// Pipeline timing (Sec 5.4.1.1):
// Build data_flat, wts_flat, biases_flat by reading 58 filter lines.
// negedge 0: all buses already driven; posedge 0 latches 58*9 MACs.
// negedge 1: (biases_flat already wired; bias add is combinational).
// negedge 2: CHECK all 58 results against stored expected values.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_dw_conv3x3_core;

    localparam integer IN_W    = `G1_FM_W;   // 10 (Ch 6.2.8: maxpool output)
    localparam integer W_W     = `G2_DW_WW;  // 15 (unchanged)
    localparam integer BIAS_WD = `DATA_W;    // 15
    localparam integer OUT_W   = `G2_FM_W;   // 12 (Ch 6.2.8: DW conv output)
    localparam integer N_FILT  = `G2_DW_PAR_FILT;  // 58
    localparam integer N_TAPS  = 9;

    // ---- Clock / reset ----
    reg clk, rst, en;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- DUT buses ----
    reg  [N_FILT*N_TAPS*IN_W-1:0]  data_flat;
    reg  [N_FILT*N_TAPS*W_W-1:0]   wts_flat;
    reg  [N_FILT*BIAS_WD-1:0]      biases_flat;
    wire [N_FILT*OUT_W-1:0]         results_flat;

    dw_conv3x3_core #(
        .N_FILT(N_FILT),
        .IN_W  (IN_W),
        .W_W   (W_W),
        .BIAS_WD(BIAS_WD),
        .OUT_W (OUT_W)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .en          (en),
        .data_flat   (data_flat),
        .weights_flat(wts_flat),
        .biases_flat (biases_flat),
        .results_flat(results_flat)
    );

    // ---- Parse temporaries for ONE filter line (20 tokens) ----
    reg [IN_W-1:0]    p_d0, p_d1, p_d2, p_d3, p_d4,
                      p_d5, p_d6, p_d7, p_d8;
    reg [W_W-1:0]     p_w0, p_w1, p_w2, p_w3, p_w4,
                      p_w5, p_w6, p_w7, p_w8;
    reg [BIAS_WD-1:0] p_bias;
    reg [OUT_W-1:0]   p_exp;

    // ---- Expected results storage (one per filter) ----
    reg [OUT_W-1:0] exp_results [0:N_FILT-1];

    integer fd, r, scan_r;
    integer n_vectors, pass_count, fail_count, dump_count;
    integer flt, all_pass;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    reg [8*1024-1:0] filter_line;

    // ====================================================================
    initial begin
        n_vectors  = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;
        rst = 1'b1;
        en  = 1'b0;
        data_flat   = {(N_FILT*N_TAPS*IN_W){1'b0}};
        wts_flat    = {(N_FILT*N_TAPS*W_W){1'b0}};
        biases_flat = {(N_FILT*BIAS_WD){1'b0}};

        $display("=========================================================");
        $display("dw_conv3x3_core Testbench  N_FILT=%0d", N_FILT);
        $display("Ch 6.2.5+6.2.8: IN_W=%0d W_W=%0d BIAS_WD=%0d OUT_W=%0d",
                 IN_W, W_W, BIAS_WD, OUT_W);
        $display("=========================================================");

        // ---- Open vector file ----
        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/group2/vectors/dw_conv3x3_core_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/group2/vectors/dw_conv3x3_core_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./dw_conv3x3_core_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open dw_conv3x3_core_vectors.hex");
            $finish;
        end

        // ---- Reset: 2 cycles ----
        #20;
        @(negedge clk);
        rst = 1'b0;
        en  = 1'b1;
        @(negedge clk);

        // ====================================================================
        // Main test loop: read 58 filter lines per case.
        // ====================================================================
        begin : main_loop
            while (!$feof(fd)) begin

                begin : gather_filters
                    integer filters_read;
                    filters_read = 0;
                    while (filters_read < N_FILT && !$feof(fd)) begin
                        r = $fgets(filter_line, fd);
                        if (r == 0) begin
                            if (filters_read == 0) disable main_loop;
                            disable gather_filters;
                        end
                        scan_r = $sscanf(filter_line,
                            "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                            p_d0, p_d1, p_d2, p_d3, p_d4,
                            p_d5, p_d6, p_d7, p_d8,
                            p_w0, p_w1, p_w2, p_w3, p_w4,
                            p_w5, p_w6, p_w7, p_w8,
                            p_bias, p_exp);
                        if (scan_r != 20) begin
                            // comment or blank line -- skip
                        end else begin
                            flt = filters_read;
                            data_flat[(flt*N_TAPS+0)*IN_W +: IN_W] = $signed(p_d0);
                            data_flat[(flt*N_TAPS+1)*IN_W +: IN_W] = $signed(p_d1);
                            data_flat[(flt*N_TAPS+2)*IN_W +: IN_W] = $signed(p_d2);
                            data_flat[(flt*N_TAPS+3)*IN_W +: IN_W] = $signed(p_d3);
                            data_flat[(flt*N_TAPS+4)*IN_W +: IN_W] = $signed(p_d4);
                            data_flat[(flt*N_TAPS+5)*IN_W +: IN_W] = $signed(p_d5);
                            data_flat[(flt*N_TAPS+6)*IN_W +: IN_W] = $signed(p_d6);
                            data_flat[(flt*N_TAPS+7)*IN_W +: IN_W] = $signed(p_d7);
                            data_flat[(flt*N_TAPS+8)*IN_W +: IN_W] = $signed(p_d8);
                            wts_flat[(flt*N_TAPS+0)*W_W +: W_W] = $signed(p_w0);
                            wts_flat[(flt*N_TAPS+1)*W_W +: W_W] = $signed(p_w1);
                            wts_flat[(flt*N_TAPS+2)*W_W +: W_W] = $signed(p_w2);
                            wts_flat[(flt*N_TAPS+3)*W_W +: W_W] = $signed(p_w3);
                            wts_flat[(flt*N_TAPS+4)*W_W +: W_W] = $signed(p_w4);
                            wts_flat[(flt*N_TAPS+5)*W_W +: W_W] = $signed(p_w5);
                            wts_flat[(flt*N_TAPS+6)*W_W +: W_W] = $signed(p_w6);
                            wts_flat[(flt*N_TAPS+7)*W_W +: W_W] = $signed(p_w7);
                            wts_flat[(flt*N_TAPS+8)*W_W +: W_W] = $signed(p_w8);
                            biases_flat[flt*BIAS_WD +: BIAS_WD] = $signed(p_bias);
                            exp_results[flt]                     = p_exp;
                            filters_read = filters_read + 1;
                        end
                    end // while filters_read < N_FILT

                    if (filters_read < N_FILT) disable main_loop;
                end // gather_filters

                // ---- negedge 0: buses driven; posedge 0 latches MACs ----
                @(negedge clk);

                // ---- negedge 1: bias is wired combinationally ----
                @(negedge clk);

                // ---- negedge 2: CHECK all 58 results ----
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
        end // main_loop

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
// END tb_dw_conv3x3_core.v
// =============================================================================
