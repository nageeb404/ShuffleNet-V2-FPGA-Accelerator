// =============================================================================
// tb_accelerator_top.v -- Structural smoke test for Module 4.2
// -----------------------------------------------------------------------------
// Thesis Sec 5.6 / Figure 5.72
//
// Tests:
//   1. Module elaborates (all ports connected, hierarchy correct)
//   2. Reset: busy=0, classification_done=0
//   3. photo_ready triggers busy and group1_start (via ctrl)
//   4. System remains stable over several cycles
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_accelerator_top;

    localparam integer DATA_W     = `DATA_W;           // 15
    localparam integer G2_DW_F    = `G2_DW_PAR_FILT;  // 58
    localparam integer G2_PW_F    = `G2_PW_PAR_FILT;  // 58
    localparam integer G2_PW_C    = `G2_PW_PAR_CHAN;   // 29
    localparam integer G3_PW_F    = `G3_PW_PAR_FILT;  // 16
    localparam integer G3_PW_C    = `G3_PW_PAR_CHAN;   // 29
    localparam integer G3_FC_C    = `G3_FC_PAR_CHAN;   // 32
    localparam integer PHOTO_W    = `PHOTO_W;          //  8 (Ch 6.2.6)
    localparam integer G2_DW_WW   = `G2_DW_WW;         // 15 (Ch 6.2.5: DW weight)
    localparam integer G2_PW_WW   = `G2_PW_WW;         // 11 (Ch 6.2.5: PW weight)
    localparam integer G2_BIAS_W  = `G2_BIAS_W;        // 13 (Ch 6.2.5: PW bias)
    localparam integer G2_FM_W    = `G2_FM_W;          // 12 (Ch 6.2.8)
    localparam integer G3_PW_WW   = `G3_PW_WW;         //  9 (Ch 6.2.5)
    localparam integer FC_WW      = `FC_WW;             //  9 (Ch 6.2.5)
    localparam integer FC_BIAS_W  = `FC_BIAS_W;        // 11 (Ch 6.2.5)

    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg  photo_ready;
    wire busy;
    wire [9:0] class_idx;
    wire       classification_done;

    // Photo memory write ports (driven to 0 for smoke test)
    reg [`PHOTO_MEM_AW-1:0] pm_addr_wr;
    reg [PHOTO_W-1:0]       pm_data_in;               // Ch 6.2.6: 8-bit pixel
    reg [2:0]               pm_we;
    reg                     pm_mem_select;

    // All weight/bias/data ports driven to 0
    reg [G2_DW_F*9*G2_DW_WW-1:0]       g2_dw_weights_flat;   // Ch 6.2.5: DW 15-bit
    reg [G2_DW_F*DATA_W-1:0]            g2_dw_biases_flat;    // DW biases 15-bit
    reg [G2_PW_F*G2_PW_C*G2_PW_WW-1:0] g2_pw_weights_flat;   // Ch 6.2.5: PW 11-bit
    reg [G2_PW_F*G2_BIAS_W-1:0]         g2_pw_biases_flat;    // Ch 6.2.5: 13-bit
    reg [G2_PW_C*G2_FM_W-1:0]           g2_pw_data_in;        // Ch 6.2.8: 12-bit
    reg [G3_PW_F*G3_PW_C*G3_PW_WW-1:0] g3_pw_weights_flat;   // Ch 6.2.5: 9-bit
    reg [G3_PW_F*DATA_W-1:0]            g3_pw_biases_flat;    // G3 PW biases 15-bit
    reg [G3_FC_C*FC_WW-1:0]             g3_fc_weights_flat;   // Ch 6.2.5: 9-bit
    reg signed [FC_BIAS_W-1:0]          g3_fc_bias_in;        // Ch 6.2.5: 11-bit
    reg [G3_PW_C*G2_FM_W-1:0]           g3_extramem_data_in;  // Ch 6.2.8: 12-bit

    accelerator_top dut (
        .clk                (clk),
        .rst                (rst),
        .photo_ready        (photo_ready),
        .busy               (busy),
        .pm_addr_wr         (pm_addr_wr),
        .pm_data_in         (pm_data_in),
        .pm_we              (pm_we),
        .pm_mem_select      (pm_mem_select),
        .g2_dw_weights_flat (g2_dw_weights_flat),
        .g2_dw_biases_flat  (g2_dw_biases_flat),
        .g2_pw_weights_flat (g2_pw_weights_flat),
        .g2_pw_biases_flat  (g2_pw_biases_flat),
        .g2_pw_data_in      (g2_pw_data_in),
        .g3_pw_weights_flat (g3_pw_weights_flat),
        .g3_pw_biases_flat  (g3_pw_biases_flat),
        .g3_fc_weights_flat (g3_fc_weights_flat),
        .g3_fc_bias_in      (g3_fc_bias_in),
        .g3_extramem_data_in(g3_extramem_data_in),
        .class_idx          (class_idx),
        .classification_done(classification_done)
    );

    integer pass_count, fail_count;

    task check;
        input integer cond;
        input [8*80-1:0] msg;
        begin
            if (cond) pass_count = pass_count + 1;
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s", msg);
            end
        end
    endtask

    initial begin
        pass_count          = 0; fail_count = 0;
        rst                 = 1'b1;
        photo_ready         = 1'b0;
        pm_addr_wr          = {`PHOTO_MEM_AW{1'b0}};
        pm_data_in          = {PHOTO_W{1'b0}};
        pm_we               = 3'd0;
        pm_mem_select       = 1'b0;
        g2_dw_weights_flat  = {(G2_DW_F*9*G2_DW_WW){1'b0}};
        g2_dw_biases_flat   = {(G2_DW_F*DATA_W){1'b0}};
        g2_pw_weights_flat  = {(G2_PW_F*G2_PW_C*G2_PW_WW){1'b0}};
        g2_pw_biases_flat   = {(G2_PW_F*G2_BIAS_W){1'b0}};
        g2_pw_data_in       = {(G2_PW_C*G2_FM_W){1'b0}};
        g3_pw_weights_flat  = {(G3_PW_F*G3_PW_C*G3_PW_WW){1'b0}};
        g3_pw_biases_flat   = {(G3_PW_F*DATA_W){1'b0}};
        g3_fc_weights_flat  = {(G3_FC_C*FC_WW){1'b0}};
        g3_fc_bias_in       = {FC_BIAS_W{1'b0}};
        g3_extramem_data_in = {(G3_PW_C*G2_FM_W){1'b0}};

        $display("=========================================================");
        $display("accelerator_top Testbench (Structural Smoke Test)");
        $display("=========================================================");

        // ---- Test 1: Reset state ----
        #20; @(negedge clk); rst = 1'b0;
        @(posedge clk); #1;

        check((busy               === 1'b0), "T1: busy=0 after reset");
        check((classification_done=== 1'b0), "T1: classification_done=0 after reset");

        // ---- Test 2: photo_ready triggers busy ----
        @(negedge clk); photo_ready = 1'b1;
        @(posedge clk); #1;
        photo_ready = 1'b0;

        check((busy === 1'b1), "T2: busy=1 after photo_ready");
        check((classification_done === 1'b0), "T2: classification_done=0 (G1 running)");

        // ---- Test 3: System stable for several more cycles ----
        repeat(20) @(posedge clk);
        #1;
        check((busy               === 1'b1), "T3: busy=1 (G1 still running)");
        check((classification_done=== 1'b0), "T3: no spurious classification_done");

        // ---- Test 4: Reset mid-operation restores idle ----
        @(negedge clk); rst = 1'b1;
        @(negedge clk); rst = 1'b0;
        @(posedge clk); #1;

        check((busy               === 1'b0), "T4: busy=0 after mid-op reset");
        check((classification_done=== 1'b0), "T4: classification_done=0 after reset");

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
// END tb_accelerator_top.v
// =============================================================================
