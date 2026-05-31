// =============================================================================
// tb_fifo_3x3.v -- Self-checking testbench for Module 1.5
// -----------------------------------------------------------------------------
// Thesis Sec 5.8.1 / Sec 5.3.3 / Figure 5.13
//
// Vector format: one line per clock cycle
//   data_in_hex  padding_sel(0/1)  shift_and_load(0/1)
//   expected_tap0_hex  expected_tap1_hex  expected_tap2_hex
//
// Pipeline timing (2 negedges per test cycle):
//   negedge A: drive data_in, padding_sel, shift_and_load = v_sal[i]
//   posedge A+: DUT shifts (if sal=1), taps update
//   negedge B: set shift_and_load=0, CHECK taps == expected[i]
//   posedge B+: idle (sal=0 prevents spurious shift)
//   negedge C: = negedge A of next iteration
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_fifo_3x3;

    localparam integer DATA_W     = `DATA_W;              // 15
    localparam integer DEPTH      = `G1_CONV_FIFO_DEPTH;  // 455
    localparam integer TAP_STRIDE = (DEPTH - 3) / 2;      // 226
    localparam integer MAX_VEC    = 2048;

    // ---- Clock / reset ----
    reg clk, rst;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- DUT ports ----
    reg  signed [DATA_W-1:0] dut_data_in;
    reg  dut_padding_sel, dut_shift_and_load;
    wire signed [DATA_W-1:0] dut_tap0, dut_tap1, dut_tap2;

    fifo_3x3 dut (
        .clk           (clk),
        .rst           (rst),
        .shift_and_load(dut_shift_and_load),
        .padding_sel   (dut_padding_sel),
        .data_in       (dut_data_in),
        .tap0          (dut_tap0),
        .tap1          (dut_tap1),
        .tap2          (dut_tap2)
    );

    // ---- Vector storage ----
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

    // ====================================================================
    initial begin
        n_vectors  = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;
        rst                = 1'b1;
        dut_shift_and_load = 1'b0;
        dut_padding_sel    = 1'b0;
        dut_data_in        = {DATA_W{1'b0}};

        $display("=========================================================");
        $display("fifo_3x3 Testbench (Thesis Sec 5.3.3)");
        $display("DEPTH=%0d  TAP_STRIDE=%0d", DEPTH, TAP_STRIDE);
        $display("=========================================================");

        // ---- Open vector file ----
        begin : open_file
            have_arg = $value$plusargs("VECTORS=%s", path_arg);
            if (have_arg)
                fd = $fopen(path_arg, "r");
            else
                fd = $fopen("tb/common/vectors/fifo_3x3_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("../tb/common/vectors/fifo_3x3_vectors.hex", "r");
            if (fd == 0)
                fd = $fopen("./fifo_3x3_vectors.hex", "r");
        end
        if (fd == 0) begin
            $display("ERROR: cannot open fifo_3x3_vectors.hex");
            $finish;
        end

        // ---- Load all vectors ----
        begin : load_loop
            while (!$feof(fd)) begin
                r  = $fgets(line_buf, fd);
                if (r == 0) disable load_loop;
                sc = $sscanf(line_buf, "%h %h %h %h %h %h",
                             tmp_d, tmp_ps, tmp_sal,
                             tmp_t0, tmp_t1, tmp_t2);
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

        // ---- Reset sequence ----
        #20;
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);   // settle

        // ---- Verify reset state: all taps must be 0 ----
        if (dut_tap0 !== {DATA_W{1'b0}} ||
            dut_tap1 !== {DATA_W{1'b0}} ||
            dut_tap2 !== {DATA_W{1'b0}}) begin
            $display("FAIL: reset state -- taps not zero: t0=%0d t1=%0d t2=%0d",
                     $signed(dut_tap0), $signed(dut_tap1), $signed(dut_tap2));
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: reset state -- all taps = 0");
            pass_count = pass_count + 1;
        end

        // ====================================================================
        // Drive-and-check loop.
        //
        // Each iteration: 2 negedge transitions (= 2 clock cycles per check).
        //   negedge A: drive inputs for cycle i (shift_and_load = v_sal[i])
        //              posedge A+1 fires: DUT shifts if sal=1, taps update
        //   negedge B: set shift_and_load=0 first (prevents posedge B+1 from
        //              spuriously shifting), then check taps vs expected[i]
        //              posedge B+1 fires with sal=0: no spurious shift
        //   -- loop advances -- next negedge C = negedge A of iteration i+1
        // ====================================================================
        for (i = 0; i < n_vectors; i = i + 1) begin

            // ---- Negedge A: drive inputs ----
            @(negedge clk);
            dut_data_in        = v_data[i];
            dut_padding_sel    = v_psel[i];
            dut_shift_and_load = v_sal[i];
            // posedge A+1 fires here (between negedge A and negedge B)

            // ---- Negedge B: check and block spurious next shift ----
            @(negedge clk);
            dut_shift_and_load = 1'b0;  // posedge B+1 will not shift

            if (dut_tap0 === v_t0[i] &&
                dut_tap1 === v_t1[i] &&
                dut_tap2 === v_t2[i]) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                if (dump_count < 10) begin
                    $display("FAIL cycle=%0d psel=%0d sal=%0d",
                             i, v_psel[i], v_sal[i]);
                    $display("  tap0 got=%0d exp=%0d",
                             $signed(dut_tap0), $signed(v_t0[i]));
                    $display("  tap1 got=%0d exp=%0d",
                             $signed(dut_tap1), $signed(v_t1[i]));
                    $display("  tap2 got=%0d exp=%0d",
                             $signed(dut_tap2), $signed(v_t2[i]));
                    dump_count = dump_count + 1;
                end
            end
            // posedge B+1 fires with sal=0 (no spurious shift)
            // then loop advances to iteration i+1, negedge C

        end // for

        $display("---------------------------------------------------------");
        $display("Total checks: %0d  (+ 1 reset check)", n_vectors);
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
// =============================================================================
// END tb_fifo_3x3.v
// =============================================================================
