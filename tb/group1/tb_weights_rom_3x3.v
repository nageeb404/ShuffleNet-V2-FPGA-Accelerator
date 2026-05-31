// =============================================================================
// tb_weights_rom_3x3.v -- Self-checking testbench for Module 1.8
// -----------------------------------------------------------------------------
// Thesis Sec 5.3.1.3 "Weights Memory" / Figure 5.6
// Thesis Sec 5.8.1 (Python golden -> hex file -> self-checking TB)
//
// Verifies that for every (addr, filter, channel, row) combination, the
// weights_rom_3x3 outputs the correct 15-bit weight on the flat bus.
//
// Check vector file format (weights_rom_3x3_tb_vectors.hex):
//   One line per check:  addr  filter  channel  row  expected_weight_hex
//   648 total checks (3 addr x 24 filters x 3 channels x 3 rows)
//
// For each check:
//   1. Drive addr = addr_field
//   2. Wait 1 ns (combinational settle)
//   3. Extract weights_flat[(f*9 + c*3 + r)*DATA_W +: DATA_W]
//   4. Compare to expected
//
// Pass criterion: "RESULT: *** ALL TESTS PASSED ***"
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_weights_rom_3x3;

    // -------------------------------------------------------------------------
    // Parameters matching the DUT
    // -------------------------------------------------------------------------
    localparam integer N_FILT = `G1_CONV_PAR_FILT;   // 24
    localparam integer N_CHAN = `G1_CONV_PAR_CHAN;    // 3
    localparam integer N_WIN  = `G1_CONV_PAR_WIN;     // 3 (rows)
    localparam integer DATA_W = `DATA_W;              // 15
    localparam integer FLAT_W = N_FILT * N_CHAN * N_WIN * DATA_W; // 216*15=3240

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg  [1:0]       addr;
    wire [FLAT_W-1:0] weights_flat;

    weights_rom_3x3 dut (
        .addr        (addr),
        .weights_flat(weights_flat)
    );

    // -------------------------------------------------------------------------
    // Test infrastructure
    // -------------------------------------------------------------------------
    integer fd, r, sc;
    integer n_checks, pass_count, fail_count, dump_count;
    integer exp_addr, exp_filt, exp_chan, exp_row;
    reg [DATA_W-1:0] exp_weight;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    reg [8*256-1:0] line_buf;

    // The slice we read from weights_flat for (filter f, channel c, row r):
    //   base = (f*9 + c*3 + r) * DATA_W
    wire signed [DATA_W-1:0] slice_out;
    reg [15:0] slice_base;
    assign slice_out = weights_flat[slice_base +: DATA_W];

    localparam integer MAX_DUMP = 20;

    // -------------------------------------------------------------------------
    // Main test
    // -------------------------------------------------------------------------
    initial begin
        n_checks   = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;
        addr       = 2'd0;

        $display("=========================================================");
        $display("weights_rom_3x3 Testbench (Thesis Sec 5.3.1.3 / Fig 5.6)");
        $display("N_FILT=%0d N_CHAN=%0d N_WIN=%0d DATA_W=%0d",
                 N_FILT, N_CHAN, N_WIN, DATA_W);
        $display("=========================================================");

        // Open check vector file
        have_arg = $value$plusargs("VECTORS=%s", path_arg);
        if (have_arg)
            fd = $fopen(path_arg, "r");
        else
            fd = $fopen("tb/common/vectors/weights_rom_3x3_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("../tb/common/vectors/weights_rom_3x3_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("./weights_rom_3x3_tb_vectors.hex", "r");
        if (fd == 0) begin
            $display("ERROR: cannot open weights_rom_3x3_tb_vectors.hex");
            $display("Run: python scripts/gen_weights_rom_3x3_vectors.py");
            $finish;
        end

        // Read and check each vector
        begin : check_loop
            while (!$feof(fd)) begin
                r = $fgets(line_buf, fd);
                if (r == 0) disable check_loop;

                sc = $sscanf(line_buf, " %d %d %d %d %h",
                             exp_addr, exp_filt, exp_chan, exp_row, exp_weight);
                if (sc != 5) begin
                    // comment or blank -- skip
                end else begin
                    // Drive address, let combinational output settle
                    addr       = exp_addr[1:0];
                    slice_base = (exp_filt * 9 + exp_chan * 3 + exp_row) * DATA_W;
                    #1;   // combinational settle (no clock needed)

                    n_checks = n_checks + 1;

                    if (slice_out !== $signed(exp_weight)) begin
                        fail_count = fail_count + 1;
                        if (dump_count < MAX_DUMP) begin
                            $display("FAIL  addr=%0d f=%0d c=%0d r=%0d : got %h  exp %h",
                                     exp_addr, exp_filt, exp_chan, exp_row,
                                     slice_out, exp_weight);
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

    // Safety timeout (combinational DUT, should finish instantly)
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_weights_rom_3x3.v
// =============================================================================
