// =============================================================================
// tb_adder_tree_9.v - Self-checking testbench for adder_tree_9
// -----------------------------------------------------------------------------
// Methodology: (Python golden -> hex -> $readmemh -> compare)
//
// adder_tree_9 is purely combinational, so no clock is required. The TB
// drives one vector at a time with a small #1 settling delay, mirroring the
// approach used for tb_Adder3.
//
// Run (with Vivado XSim):
// source {N:\GP\shufflenet_rtl\vivado\scripts\sim_tb_adder_tree_9.tcl}
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_adder_tree_9;

    // ---- Parameters (must match the Python generator) ----
    localparam integer IN_W   = `MUL_OUT_W;          // 23
    localparam integer OUT_W  = IN_W + 4;            // 27
    localparam integer MAX_VEC = 2048;

    // ---- Vector storage ----
    // Use 9 separate 1D arrays for maximum Verilog-2001 portability
    // (multi-dim unpacked arrays are IEEE 1364-2005+ only).
    reg signed [IN_W -1:0] v_in0 [0:MAX_VEC-1];
    reg signed [IN_W -1:0] v_in1 [0:MAX_VEC-1];
    reg signed [IN_W -1:0] v_in2 [0:MAX_VEC-1];
    reg signed [IN_W -1:0] v_in3 [0:MAX_VEC-1];
    reg signed [IN_W -1:0] v_in4 [0:MAX_VEC-1];
    reg signed [IN_W -1:0] v_in5 [0:MAX_VEC-1];
    reg signed [IN_W -1:0] v_in6 [0:MAX_VEC-1];
    reg signed [IN_W -1:0] v_in7 [0:MAX_VEC-1];
    reg signed [IN_W -1:0] v_in8 [0:MAX_VEC-1];
    reg signed [OUT_W-1:0] v_exp [0:MAX_VEC-1];

    // ---- DUT instance ----
    reg  signed [IN_W -1:0] in0_r, in1_r, in2_r, in3_r, in4_r;
    reg  signed [IN_W -1:0] in5_r, in6_r, in7_r, in8_r;
    wire signed [OUT_W-1:0] sum_o;

    adder_tree_9 #(.IN_W(IN_W), .OUT_W(OUT_W)) dut (
        .in0(in0_r), .in1(in1_r), .in2(in2_r),
        .in3(in3_r), .in4(in4_r), .in5(in5_r),
        .in6(in6_r), .in7(in7_r), .in8(in8_r),
        .sum_out(sum_o)
    );

    // ---- File / loop counters ----
    integer fd;
    integer scan_status;
    integer n_vectors;
    integer i;
    integer pass_count, fail_count;
    integer dump_count;

    reg [IN_W -1:0] tmp0, tmp1, tmp2, tmp3, tmp4, tmp5, tmp6, tmp7, tmp8;
    reg [OUT_W-1:0] tmp_exp;
    reg [1023:0] line;
    integer r;

    initial begin
        n_vectors   = 0;
        pass_count  = 0;
        fail_count  = 0;
        dump_count  = 0;

        $display("=========================================================");
        $display("adder_tree_9 Self-Checking Testbench");
        $display("=========================================================");

        // ---- Open vector file ----
        begin : open_file
            reg [8*512-1:0] path_arg;
            integer have_arg;
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/common/vectors/adder_tree_9_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/common/vectors/adder_tree_9_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./adder_tree_9_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open adder_tree_9_vectors.hex");
            $finish;
        end

        // ---- Parse file ----
        // Each line has 9 input hex values + 1 expected hex value = 10 fields.
        begin : load_loop
            while (!$feof(fd)) begin
                r = $fgets(line, fd);
                if (r == 0) disable load_loop;
                scan_status = $sscanf(line, "%h %h %h %h %h %h %h %h %h %h",
                                      tmp0, tmp1, tmp2, tmp3, tmp4,
                                      tmp5, tmp6, tmp7, tmp8, tmp_exp);
                if (scan_status == 10) begin
                    v_in0[n_vectors] = $signed(tmp0);
                    v_in1[n_vectors] = $signed(tmp1);
                    v_in2[n_vectors] = $signed(tmp2);
                    v_in3[n_vectors] = $signed(tmp3);
                    v_in4[n_vectors] = $signed(tmp4);
                    v_in5[n_vectors] = $signed(tmp5);
                    v_in6[n_vectors] = $signed(tmp6);
                    v_in7[n_vectors] = $signed(tmp7);
                    v_in8[n_vectors] = $signed(tmp8);
                    v_exp[n_vectors] = $signed(tmp_exp);
                    n_vectors = n_vectors + 1;
                    if (n_vectors >= MAX_VEC) disable load_loop;
                end
            end
        end
        $fclose(fd);

        $display("Loaded %0d vectors.", n_vectors);
        if (n_vectors == 0) begin
            $display("ERROR: no vectors loaded");
            $finish;
        end

        // ---- Drive and check ----
        for (i = 0; i < n_vectors; i = i + 1) begin
            in0_r = v_in0[i];
            in1_r = v_in1[i];
            in2_r = v_in2[i];
            in3_r = v_in3[i];
            in4_r = v_in4[i];
            in5_r = v_in5[i];
            in6_r = v_in6[i];
            in7_r = v_in7[i];
            in8_r = v_in8[i];
            #1;  // settle combinational delay

            if (sum_o === v_exp[i]) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                if (dump_count < 10) begin
                    $display("FAIL #%0d: in=[%0d %0d %0d %0d %0d %0d %0d %0d %0d] got=%0d exp=%0d",
                             i, v_in0[i], v_in1[i], v_in2[i],
                                 v_in3[i], v_in4[i], v_in5[i],
                                 v_in6[i], v_in7[i], v_in8[i],
                                 sum_o, v_exp[i]);
                    dump_count = dump_count + 1;
                end
            end
        end

        $display("---------------------------------------------------------");
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
// END tb_adder_tree_9.v
// =============================================================================
