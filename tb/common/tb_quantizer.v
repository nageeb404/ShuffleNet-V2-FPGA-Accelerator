// =============================================================================
// tb_quantizer.v - Self-checking TB for the saturating quantizer
// -----------------------------------------------------------------------------
// Methodology: Thesis Sec 5.8.1 (Python golden -> hex -> $readmemh -> compare)
//
// This testbench instantiates TWO copies of the quantizer:
//   - dut_signed : HAS_RELU = 0 (full two-sided saturation, Sec 5.4.1.1)
//   - dut_relu   : HAS_RELU = 1 (one-sided post-ReLU saturation, Sec 5.4.1.2)
// Each input vector is checked against its respective Python golden output.
//
// Run (with Vivado XSim):
//   vivado -mode batch -source vivado/scripts/sim_tb_quantizer.tcl
//
// Run (with Icarus Verilog, alternative):
//   iverilog -g2012 -I rtl/common -o build/tb_quantizer \
//            tb/common/tb_quantizer.v rtl/common/quantizer.v
//   vvp build/tb_quantizer
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_quantizer;

    // -------------------------------------------------------------------------
    // Parameters MUST match the Python generator (in_width = 27, data_w = 15).
    // 27 is the width of the 3by3 DW conv core output per Thesis Sec 5.4.1.1.
    // -------------------------------------------------------------------------
    localparam integer IN_W      = 27;
    localparam integer OUT_W     = `DATA_W;          // 15
    localparam integer MAX_VEC   = 1024;

    // -------------------------------------------------------------------------
    // Vector storage
    //   v_in_sgn  : input for signed mode (full range)
    //   v_in_relu : input for relu  mode (non-negative only)
    //   v_exp_*   : corresponding golden outputs
    // -------------------------------------------------------------------------
    reg signed [IN_W-1:0]  v_in_sgn    [0:MAX_VEC-1];
    reg signed [OUT_W-1:0] v_exp_signed[0:MAX_VEC-1];
    reg signed [IN_W-1:0]  v_in_relu   [0:MAX_VEC-1];
    reg signed [OUT_W-1:0] v_exp_relu  [0:MAX_VEC-1];

    // -------------------------------------------------------------------------
    // DUT instances
    // -------------------------------------------------------------------------
    reg  signed [IN_W-1:0]  in_sgn;
    reg  signed [IN_W-1:0]  in_relu;
    wire signed [OUT_W-1:0] out_signed;
    wire signed [OUT_W-1:0] out_relu;

    quantizer #(.IN_W(IN_W), .OUT_W(OUT_W), .HAS_RELU(0)) dut_signed (
        .in_data (in_sgn),
        .out_data(out_signed)
    );

    quantizer #(.IN_W(IN_W), .OUT_W(OUT_W), .HAS_RELU(1)) dut_relu (
        .in_data (in_relu),
        .out_data(out_relu)
    );

    // -------------------------------------------------------------------------
    // Vector loading + run
    // -------------------------------------------------------------------------
    integer fd;
    integer scan_status;
    integer n_vectors;
    integer i;
    integer pass_signed, fail_signed;
    integer pass_relu,   fail_relu;
    integer dump_count;

    reg [IN_W-1:0]  tmp_in_sgn, tmp_in_relu;
    reg [OUT_W-1:0] tmp_signed, tmp_relu;
    reg [1023:0]    line;
    integer         r;

    initial begin
        n_vectors   = 0;
        pass_signed = 0; fail_signed = 0;
        pass_relu   = 0; fail_relu   = 0;
        dump_count  = 0;

        $display("=========================================================");
        $display("quantizer Self-Checking Testbench (Thesis Sec 5.4.1.1/2)");
        $display("=========================================================");

        // Vector file path: allow override via +VECTORS=<path> plusarg.
        begin : open_file
            reg [8*512-1:0] path_arg;
            integer have_arg;
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/common/vectors/quantizer_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/common/vectors/quantizer_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./quantizer_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open quantizer_vectors.hex");
            $display("Hint: pass +VECTORS=/absolute/path/quantizer_vectors.hex");
            $finish;
        end

        begin : load_loop
            while (!$feof(fd)) begin
                r = $fgets(line, fd);
                if (r == 0) disable load_loop;
                scan_status = $sscanf(line, "%h %h %h %h",
                                      tmp_in_sgn, tmp_signed,
                                      tmp_in_relu, tmp_relu);
                if (scan_status == 4) begin
                    v_in_sgn    [n_vectors] = $signed(tmp_in_sgn);
                    v_exp_signed[n_vectors] = $signed(tmp_signed);
                    v_in_relu   [n_vectors] = $signed(tmp_in_relu);
                    v_exp_relu  [n_vectors] = $signed(tmp_relu);
                    n_vectors               = n_vectors + 1;
                    if (n_vectors >= MAX_VEC) disable load_loop;
                end
            end
        end
        $fclose(fd);

        $display("Loaded %0d vectors.", n_vectors);
        if (n_vectors == 0) begin $display("ERROR: no vectors"); $finish; end

        // Drive and compare
        for (i = 0; i < n_vectors; i = i + 1) begin
            in_sgn  = v_in_sgn [i];
            in_relu = v_in_relu[i];
            #1;

            // Two-sided check
            if (out_signed === v_exp_signed[i]) begin
                pass_signed = pass_signed + 1;
            end else begin
                fail_signed = fail_signed + 1;
                if (dump_count < 10) begin
                    $display("FAIL[signed] #%0d: in=%0d  got=%0d  exp=%0d",
                             i, in_sgn, out_signed, v_exp_signed[i]);
                    dump_count = dump_count + 1;
                end
            end

            // ReLU-mode check
            if (out_relu === v_exp_relu[i]) begin
                pass_relu = pass_relu + 1;
            end else begin
                fail_relu = fail_relu + 1;
                if (dump_count < 10) begin
                    $display("FAIL[relu]   #%0d: in=%0d  got=%0d  exp=%0d",
                             i, in_relu, out_relu, v_exp_relu[i]);
                    dump_count = dump_count + 1;
                end
            end
        end

        $display("---------------------------------------------------------");
        $display("Mode HAS_RELU=0  PASS: %0d / %0d   FAIL: %0d",
                 pass_signed, n_vectors, fail_signed);
        $display("Mode HAS_RELU=1  PASS: %0d / %0d   FAIL: %0d",
                 pass_relu,   n_vectors, fail_relu);
        if (fail_signed == 0 && fail_relu == 0)
            $display("RESULT: *** ALL TESTS PASSED ***");
        else
            $display("RESULT: *** %0d TESTS FAILED ***",
                     fail_signed + fail_relu);
        $display("=========================================================");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_quantizer.v
// =============================================================================
