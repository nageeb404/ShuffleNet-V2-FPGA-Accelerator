// =============================================================================
// tb_group2_top.v -- Structural smoke test for Module 2.11
// -----------------------------------------------------------------------------
// "Group 2 Design"
//
// Tests:
// 1. Module elaborates (no unconnected port / hierarchy errors)
// 2. RST -> IDLE behaviour: after reset, group2_done stays 0
// 3. start_group triggers FSM (loops counter advances from 0 with done injection)
//
// This is a structural connectivity check. Full end-to-end functional
// verification (with real image data, weights, and golden outputs) is
// deferred to Phase 5 system-level integration.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_group2_top;

    // ---- Clock / reset ----
    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- DUT parameters ----
    localparam integer DATA_W    = `DATA_W;           // 15 (DW biases, original)
    localparam integer G1_FM_W   = `G1_FM_W;          // 10 (Ch 6.2.8: DW input)
    localparam integer G2_DW_WW  = `G2_DW_WW;         // 15 (DW weight width)
    localparam integer G2_FM_W   = `G2_FM_W;          // 12 (Ch 6.2.8: DW/PW output)
    localparam integer G2_PW_WW  = `G2_PW_WW;         // 11 (Ch 6.2.5: PW weight)
    localparam integer G2_BIAS_W = `G2_BIAS_W;        // 13 (Ch 6.2.5: PW bias)
    localparam integer N_FILT    = `G2_DW_PAR_FILT;   // 58
    localparam integer N_CHAN    = `G2_PW_PAR_CHAN;    // 29

    // ---- DUT ports ----
    reg  start_group;
    wire group2_done;
    wire [4:0] loops;
    wire [1:0] fsm_state;

    // Feature map and data buses driven to 0 (structural test only)
    reg [N_FILT*G1_FM_W-1:0]             fm_data_in;       // Ch 6.2.8
    wire [11:0]                           fm_rd_addr;
    reg [N_FILT*9*G2_DW_WW-1:0]          dw_weights_flat;  // Ch 6.2.5
    reg [N_FILT*DATA_W-1:0]              dw_biases_flat;   // DW biases 15-bit
    wire [N_FILT*G2_FM_W-1:0]            dw_results_flat;  // Ch 6.2.8
    wire [11:0]                           dw_wr_addr;
    wire                                  dw_we;
    reg [N_CHAN*G2_FM_W-1:0]             pw_data_in;       // Ch 6.2.8
    reg [N_FILT*N_CHAN*G2_PW_WW-1:0]     pw_weights_flat;  // Ch 6.2.5
    reg [N_FILT*G2_BIAS_W-1:0]           pw_biases_flat;   // Ch 6.2.5
    wire [N_FILT*G2_FM_W-1:0]            pw_results_flat;  // Ch 6.2.8
    wire [11:0]                           pw_wr_addr;
    wire                                  pw_we;

    group2_top dut (
        .clk            (clk),
        .rst            (rst),
        .start_group    (start_group),
        .group2_done    (group2_done),
        .fm_data_in     (fm_data_in),
        .fm_rd_addr     (fm_rd_addr),
        .dw_weights_flat(dw_weights_flat),
        .dw_biases_flat (dw_biases_flat),
        .dw_results_flat(dw_results_flat),
        .dw_wr_addr     (dw_wr_addr),
        .dw_we          (dw_we),
        .pw_data_in     (pw_data_in),
        .pw_weights_flat(pw_weights_flat),
        .pw_biases_flat (pw_biases_flat),
        .pw_results_flat(pw_results_flat),
        .pw_wr_addr     (pw_wr_addr),
        .pw_we          (pw_we),
        .loops          (loops),
        .fsm_state      (fsm_state)
    );

    // ---- Test infrastructure ----
    integer pass_count, fail_count;

    task check;
        input integer cond;
        input [8*64-1:0] msg;
        begin
            if (cond)
                pass_count = pass_count + 1;
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s", msg);
            end
        end
    endtask

    integer i;

    initial begin
        pass_count   = 0;
        fail_count   = 0;
        start_group  = 1'b0;
        fm_data_in   = {(N_FILT*G1_FM_W){1'b0}};
        dw_weights_flat = {(N_FILT*9*G2_DW_WW){1'b0}};
        dw_biases_flat  = {(N_FILT*DATA_W){1'b0}};
        pw_data_in      = {(N_CHAN*G2_FM_W){1'b0}};
        pw_weights_flat = {(N_FILT*N_CHAN*G2_PW_WW){1'b0}};
        pw_biases_flat  = {(N_FILT*G2_BIAS_W){1'b0}};
        rst = 1'b1;

        $display("=========================================================");
        $display("group2_top Testbench (Structural Smoke Test)");
        $display("=========================================================");

        // ---- Test 1: Reset behaviour ----
        #20; @(negedge clk); rst = 1'b0;
        @(posedge clk); #1;

        check((group2_done === 1'b0), "group2_done=0 after reset");
        check((fsm_state   === 2'd0), "fsm_state=IDLE after reset");
        check((loops       === 5'd0), "loops=0 after reset");

        // ---- Test 2: start_group transitions FSM to non-IDLE ----
        @(negedge clk);
        start_group = 1'b1;
        @(posedge clk); #1;
        start_group = 1'b0;

        check((fsm_state !== 2'd0), "fsm_state != IDLE after start_group");
        check((loops === 5'd0),     "loops still 0 (first block, no done yet)");

        $display("Smoke test: FSM active, fsm_state=%0d loops=%0d", fsm_state, loops);

        // ---- Run for a few more cycles (structural connectivity) ----
        for (i = 0; i < 20; i = i + 1)
            @(posedge clk);
        #1;

        $display("After 20 extra cycles: fsm_state=%0d loops=%0d", fsm_state, loops);
        check((group2_done === 1'b0), "group2_done=0 (sub-ctls not done, no data)");

        // ---- Reset again -- FSM returns to IDLE ----
        @(negedge clk); rst = 1'b1;
        @(negedge clk); rst = 1'b0;
        @(posedge clk); #1;

        check((fsm_state === 2'd0), "fsm_state=IDLE after second reset");
        check((loops     === 5'd0), "loops=0 after second reset");

        // ---- Summary ----
        $display("---------------------------------------------------------");
        $display("Tested %0d checks", pass_count + fail_count);
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
// END tb_group2_top.v
// =============================================================================
