// =============================================================================
// tb_fifo_pool.v -- Self-checking testbench for Module 1.6 (fifo_pool)
// -----------------------------------------------------------------------------
// / Figure 5.11 / Figure 5.13
// Same structure as tb_fifo_3x3 but DEPTH=231, TAP_STRIDE=114.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_fifo_pool;

    localparam integer DATA_W     = `DATA_W;              // 15
    localparam integer DEPTH      = `G1_POOL_FIFO_DEPTH;  // 231
    localparam integer TAP_STRIDE = (DEPTH - 3) / 2;      // 114
    localparam integer MAX_VEC    = 1024;

    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg  signed [DATA_W-1:0] dut_data_in;
    reg  dut_padding_sel, dut_shift_and_load;
    wire signed [DATA_W-1:0] dut_tap0, dut_tap1, dut_tap2;

    fifo_pool dut (
        .clk           (clk),
        .rst           (rst),
        .shift_and_load(dut_shift_and_load),
        .padding_sel   (dut_padding_sel),
        .data_in       (dut_data_in),
        .tap0          (dut_tap0),
        .tap1          (dut_tap1),
        .tap2          (dut_tap2)
    );

    reg signed [DATA_W-1:0] v_data [0:MAX_VEC-1];
    reg                     v_psel [0:MAX_VEC-1];
    reg                     v_sal  [0:MAX_VEC-1];
    reg signed [DATA_W-1:0] v_t0   [0:MAX_VEC-1];
    reg signed [DATA_W-1:0] v_t1   [0:MAX_VEC-1];
    reg signed [DATA_W-1:0] v_t2   [0:MAX_VEC-1];

    integer fd, r, sc, n_vectors, i;
    integer pass_count, fail_count, dump_count;
    reg [8*1024-1:0] line_buf;
    reg [8*512-1:0]  path_arg;
    integer have_arg;
    reg [DATA_W-1:0] tmp_d, tmp_t0, tmp_t1, tmp_t2;
    reg [3:0]        tmp_ps, tmp_sal;

    initial begin
        n_vectors = 0; pass_count = 0; fail_count = 0; dump_count = 0;
        rst = 1'b1; dut_shift_and_load = 1'b0;
        dut_padding_sel = 1'b0; dut_data_in = {DATA_W{1'b0}};

        $display("=========================================================");
        $display("fifo_pool Testbench");
        $display("DEPTH=%0d  TAP_STRIDE=%0d", DEPTH, TAP_STRIDE);
        $display("=========================================================");

        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg) fd = $fopen(path_arg, "r");
            else          fd = $fopen("tb/common/vectors/fifo_pool_vectors.hex", "r");
            if (fd == 0)  fd = $fopen("../tb/common/vectors/fifo_pool_vectors.hex", "r");
            if (fd == 0)  fd = $fopen("./fifo_pool_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open fifo_pool_vectors.hex"); $finish;
        end

        begin : load_loop
            while (!$feof(fd)) begin
                r  = $fgets(line_buf, fd);
                if (r == 0) disable load_loop;
                sc = $sscanf(line_buf, "%h %h %h %h %h %h",
                             tmp_d, tmp_ps, tmp_sal, tmp_t0, tmp_t1, tmp_t2);
                if (sc == 6) begin
                    v_data[n_vectors] = $signed(tmp_d);
                    v_psel[n_vectors] = tmp_ps[0];
                    v_sal [n_vectors] = tmp_sal[0];
                    v_t0  [n_vectors] = $signed(tmp_t0);
                    v_t1  [n_vectors] = $signed(tmp_t1);
                    v_t2  [n_vectors] = $signed(tmp_t2);
                    n_vectors = n_vectors + 1;
                    if (n_vectors >= MAX_VEC) disable load_loop;
                end
            end
        end
        $fclose(fd);
        $display("Loaded %0d vectors.", n_vectors);

        #20; @(negedge clk); rst = 1'b0; @(negedge clk);

        // Reset check
        if (dut_tap0 !== {DATA_W{1'b0}} ||
            dut_tap1 !== {DATA_W{1'b0}} ||
            dut_tap2 !== {DATA_W{1'b0}}) begin
            $display("FAIL: reset state taps not zero");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: reset state -- all taps = 0");
            pass_count = pass_count + 1;
        end

        for (i = 0; i < n_vectors; i = i + 1) begin
            @(negedge clk);
            dut_data_in        = v_data[i];
            dut_padding_sel    = v_psel[i];
            dut_shift_and_load = v_sal[i];

            @(negedge clk);
            dut_shift_and_load = 1'b0;

            if (dut_tap0 === v_t0[i] &&
                dut_tap1 === v_t1[i] &&
                dut_tap2 === v_t2[i]) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                if (dump_count < 10) begin
                    $display("FAIL cycle=%0d psel=%0d sal=%0d", i, v_psel[i], v_sal[i]);
                    $display("  tap0 got=%0d exp=%0d", $signed(dut_tap0), $signed(v_t0[i]));
                    $display("  tap1 got=%0d exp=%0d", $signed(dut_tap1), $signed(v_t1[i]));
                    $display("  tap2 got=%0d exp=%0d", $signed(dut_tap2), $signed(v_t2[i]));
                    dump_count = dump_count + 1;
                end
            end
        end

        $display("---------------------------------------------------------");
        $display("PASS: %0d / %0d", pass_count, n_vectors + 1);
        $display("FAIL: %0d / %0d", fail_count, n_vectors + 1);
        if (fail_count == 0)
            $display("RESULT: *** ALL TESTS PASSED ***");
        else
            $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
        $display("=========================================================");
        $finish;
    end

endmodule

`default_nettype wire
