// =============================================================================
// tb_group1_ctrl.v -- Self-checking testbench for Module 1.12 (group1_ctrl)
// -----------------------------------------------------------------------------
// Thesis Sec 5.3.4.2 "Group1 Controller" / Figure 5.4
//
// Simulates a IDLE -> LDROW -> LDWIN -> PROCESS (4 pixels x 4 clocks) -> IDLE
// sequence and verifies that group1_ctrl drives the correct control signals.
//
// Each vector line drives fsm_state and checks en, acc_clr, addr, conv_valid.
//
// Vector file: tb/common/vectors/group1_ctrl_tb_vectors.hex
//   Format: fsm_state exp_en exp_acc_clr exp_addr exp_conv_valid
//
// Pass criterion: "RESULT: *** ALL TESTS PASSED ***"
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_group1_ctrl;

    // -------------------------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------------------------
    reg clk, rst;
    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    reg        start;
    reg  [1:0] fsm_state;

    wire        en;
    wire        acc_clr;
    wire [1:0]  addr;
    wire        start_fifo;
    wire        conv_valid;

    group1_ctrl dut (
        .clk        (clk),
        .rst        (rst),
        .start      (start),
        .fsm_state  (fsm_state),
        .en         (en),
        .acc_clr    (acc_clr),
        .addr       (addr),
        .start_fifo (start_fifo),
        .conv_valid (conv_valid)
    );

    // -------------------------------------------------------------------------
    // Test infrastructure
    // -------------------------------------------------------------------------
    integer fd, r, sc;
    integer n_checks, pass_count, fail_count, dump_count;
    reg [8*512-1:0] path_arg;
    integer have_arg;
    reg [8*256-1:0] line_buf;
    reg [1:0]  vec_fsm;
    integer    vec_en, vec_acc_clr, vec_addr, vec_conv_valid;

    localparam integer MAX_DUMP = 10;

    // -------------------------------------------------------------------------
    // Main test
    // -------------------------------------------------------------------------
    initial begin
        n_checks   = 0;
        pass_count = 0;
        fail_count = 0;
        dump_count = 0;

        fsm_state = 2'd0;
        start     = 1'b0;

        $display("=========================================================");
        $display("group1_ctrl Testbench (Thesis Sec 5.3.4.2 / Fig 5.4)");
        $display("col_cnt cycles 0->1->2->3->0 in PROCESS state");
        $display("=========================================================");

        // Reset
        rst = 1'b1;
        repeat(3) @(posedge clk);
        #1;
        rst = 1'b0;
        start = 1'b1;  // assert start so start_fifo can be checked

        // Open vector file
        have_arg = $value$plusargs("VECTORS=%s", path_arg);
        if (have_arg)
            fd = $fopen(path_arg, "r");
        else
            fd = $fopen("tb/common/vectors/group1_ctrl_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("../tb/common/vectors/group1_ctrl_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("../../../../../../tb/group1/vectors/group1_ctrl_tb_vectors.hex", "r");
        if (fd == 0)
            fd = $fopen("./group1_ctrl_tb_vectors.hex", "r");
        if (fd == 0) begin
            $display("ERROR: cannot open group1_ctrl_tb_vectors.hex");
            $display("Run: python scripts/gen_group1_ctrl_vectors.py");
            $finish;
        end

        // -----------------------------------------------------------------------
        // Process one vector per clock cycle:
        //   - Drive fsm_state before posedge
        //   - After posedge+#1: check output signals
        // -----------------------------------------------------------------------
        begin : file_loop
            while (!$feof(fd)) begin
                r = $fgets(line_buf, fd);
                if (r == 0) disable file_loop;

                sc = $sscanf(line_buf, " %d %d %d %d %d",
                             vec_fsm, vec_en, vec_acc_clr, vec_addr, vec_conv_valid);
                if (sc != 5) begin
                    // comment or blank -- skip
                end else begin
                    // Drive fsm_state, then clock, then check
                    fsm_state = vec_fsm;
                    @(posedge clk); #1;

                    n_checks = n_checks + 1;
                    if (en         !== vec_en[0:0]         ||
                        acc_clr    !== vec_acc_clr[0:0]    ||
                        addr       !== vec_addr[1:0]        ||
                        conv_valid !== vec_conv_valid[0:0]) begin
                        fail_count = fail_count + 1;
                        if (dump_count < MAX_DUMP) begin
                            $display("FAIL fsm=%0d: en=%b acc_clr=%b addr=%0d conv_valid=%b",
                                     vec_fsm, en, acc_clr, addr, conv_valid);
                            $display("           exp: en=%0d acc_clr=%0d addr=%0d conv_valid=%0d",
                                     vec_en, vec_acc_clr, vec_addr, vec_conv_valid);
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
        #50000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_group1_ctrl.v
// =============================================================================
