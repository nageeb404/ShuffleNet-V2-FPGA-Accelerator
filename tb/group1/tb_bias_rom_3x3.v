// =============================================================================
// tb_bias_rom_3x3.v -- Self-checking testbench for Module 1.9 (bias_rom_3x3)
// -----------------------------------------------------------------------------
// Thesis Sec 5.3.1.4 "Bias Memory" / Figure 5.7
// Thesis Sec 5.8.1 (Python golden -> hex file -> self-checking TB)
//
// The DUT is purely combinational (no clock needed).
// Checks that biases_flat[f*DATA_W +: DATA_W] matches the expected value
// for every filter f (0..23).
//
// Vector file: bias_rom_3x3_tb_vectors.hex
//   Format: filter  expected_bias_hex  (24 lines, one per filter)
//
// Pass criterion: "RESULT: *** ALL TESTS PASSED ***"
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_bias_rom_3x3;

    localparam integer N_FILT = `G1_CONV_PAR_FILT;   // 24
    localparam integer DATA_W = `DATA_W;              // 15
    localparam integer FLAT_W = N_FILT * DATA_W;      // 360

    // -------------------------------------------------------------------------
    // DUT (purely combinational -- no clock)
    // -------------------------------------------------------------------------
    wire [FLAT_W-1:0] biases_flat;

    bias_rom_3x3 dut (
        .biases_flat(biases_flat)
    );

    // -------------------------------------------------------------------------
    // Test infrastructure
    // -------------------------------------------------------------------------
    integer fd, r, sc;
    integer n_checks, pass_count, fail_count, dump_count;
    integer exp_filt;
    reg [DATA_W-1:0] exp_bias;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    reg [8*256-1:0] line_buf;

    localparam integer MAX_DUMP = 10;

    // Slice for one filter (driven combinationally from exp_filt)
    reg [15:0] slice_base;
    wire signed [DATA_W-1:0] got_bias;
    assign got_bias = biases_flat[slice_base +: DATA_W];

    // -------------------------------------------------------------------------
    // Main test
    // -------------------------------------------------------------------------
    initial begin
        n_checks   = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;

        $display("=========================================================");
        $display("bias_rom_3x3 Testbench (Thesis Sec 5.3.1.4 / Fig 5.7)");
        $display("N_FILT=%0d  DATA_W=%0d  (all outputs combinational)",
                 N_FILT, DATA_W);
        $display("=========================================================");

        // Open vector file
        have_arg = $value$plusargs("VECTORS=%s", path_arg);
        if (have_arg)
            fd = $fopen(path_arg, "r");
        else
            fd = $fopen("tb/common/vectors/bias_rom_3x3_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("../tb/common/vectors/bias_rom_3x3_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("./bias_rom_3x3_tb_vectors.hex", "r");
        if (fd == 0) begin
            $display("ERROR: cannot open bias_rom_3x3_tb_vectors.hex");
            $display("Run: python scripts/gen_bias_rom_3x3_init.py");
            $finish;
        end

        #1;  // let combinational outputs settle after time 0

        begin : check_loop
            while (!$feof(fd)) begin
                r = $fgets(line_buf, fd);
                if (r == 0) disable check_loop;

                sc = $sscanf(line_buf, " %d %h", exp_filt, exp_bias);
                if (sc != 2) begin
                    // comment or blank
                end else begin
                    slice_base = exp_filt * DATA_W;
                    #1;  // settle after driving slice_base

                    n_checks = n_checks + 1;
                    if (got_bias !== $signed(exp_bias)) begin
                        fail_count = fail_count + 1;
                        if (dump_count < MAX_DUMP) begin
                            $display("FAIL filter %0d: got %h  exp %h",
                                     exp_filt, got_bias, exp_bias);
                            dump_count = dump_count + 1;
                        end
                    end else begin
                        pass_count = pass_count + 1;
                    end
                end
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
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_bias_rom_3x3.v
// =============================================================================
