// =============================================================================
// tb_group3_top.v -- Structural smoke test for Module 3.5 (group3_top)
// -----------------------------------------------------------------------------
// Tests:
// 1. Module elaborates (no connectivity errors)
// 2. After reset: group3_done=0, class_idx=0
// 3. start_group transitions to active state (conv1x1_en=1)
// 4. group3_done stays 0 for initial cycles (full run is ~47000 cycles)
// 5. Reset restores initial state
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_group3_top;

 localparam integer DATA_W = `DATA_W; // 15
 localparam integer N_CHAN_1X1 = `G3_PW_PAR_CHAN; // 29
 localparam integer N_FILT_1X1 = `G3_PW_PAR_FILT; // 16
 localparam integer N_FC_PAR = `G3_FC_PAR_CHAN; // 32
 localparam integer G2_FM_W = `G2_FM_W; // 12 (Ch 6.2.8: G3 conv1x1 input)
 localparam integer G3_PW_WW = `G3_PW_WW; // 9 (Ch 6.2.5: G3 PW weight)
 localparam integer FC_WW = `FC_WW; // 9 (Ch 6.2.5: FC weight)
 localparam integer FC_BIAS_W = `FC_BIAS_W; // 11 (Ch 6.2.5: FC bias)

 reg clk, rst;
 initial clk = 1'b0;
 always #5 clk = ~clk;

 reg start_group;
 wire group3_done;
 wire [9:0] class_idx;
 wire [13:0] extramem_rd_addr;
 wire [13:0] dbg_extramem_addr;
 wire dbg_conv1x1_en;

 // All data inputs driven to zero (structural test only)
 reg [N_CHAN_1X1*G2_FM_W-1:0] extramem_data_in; // Ch 6.2.8
 reg [N_FILT_1X1*N_CHAN_1X1*G3_PW_WW-1:0] pw_weights_flat; // Ch 6.2.5
 reg [N_FILT_1X1*DATA_W-1:0] pw_biases_flat; // G3 PW biases 15-bit
 reg [N_FC_PAR*FC_WW-1:0] fc_weights_flat; // Ch 6.2.5
 reg signed [FC_BIAS_W-1:0] fc_bias_in; // Ch 6.2.5

 group3_top dut (
 .clk (clk),
 .rst (rst),
 .start_group (start_group),
 .group3_done (group3_done),
 .extramem_rd_addr (extramem_rd_addr),
 .extramem_data_in (extramem_data_in),
 .pw_weights_flat (pw_weights_flat),
 .pw_biases_flat (pw_biases_flat),
 .fc_weights_flat (fc_weights_flat),
 .fc_bias_in (fc_bias_in),
 .class_idx (class_idx),
 .dbg_extramem_addr(dbg_extramem_addr),
 .dbg_conv1x1_en (dbg_conv1x1_en)
 );

 integer pass_count, fail_count;

 task check;
 input integer cond;
 input [8*64-1:0] msg;
 begin
 if (cond) pass_count = pass_count + 1;
 else begin
 fail_count = fail_count + 1;
 $display("FAIL: %0s", msg);
 end
 end
 endtask

 initial begin
 pass_count = 0; fail_count = 0;
 rst = 1'b1;
 start_group = 1'b0;
 extramem_data_in = {(N_CHAN_1X1*G2_FM_W){1'b0}};
 pw_weights_flat = {(N_FILT_1X1*N_CHAN_1X1*G3_PW_WW){1'b0}};
 pw_biases_flat = {(N_FILT_1X1*DATA_W){1'b0}};
 fc_weights_flat = {(N_FC_PAR*FC_WW){1'b0}};
 fc_bias_in = {FC_BIAS_W{1'b0}};

 $display("=========================================================");
 $display("group3_top Testbench (Structural Smoke Test)");
 $display("=========================================================");

 // ---- Test 1: Reset behaviour ----
 #20; @(negedge clk); rst = 1'b0;
 @(posedge clk); #1;

 check((group3_done === 1'b0), "group3_done=0 after reset");
 check((dbg_conv1x1_en=== 1'b0), "conv1x1_en=0 after reset");
 check((extramem_rd_addr === 14'd0), "extramem_rd_addr=0 after reset");

 // ---- Test 2: start_group activates conv ----
 @(negedge clk); start_group = 1'b1;
 @(posedge clk); #1;
 start_group = 1'b0;

 check((dbg_conv1x1_en === 1'b1), "conv1x1_en=1 after start_group");
 check((group3_done === 1'b0), "group3_done=0 (not done yet)");

 // ---- Test 3: extramem_rd_addr advances ----
 @(posedge clk); #1;
 check((extramem_rd_addr !== 14'd0), "extramem_rd_addr advanced");

 // ---- Test 4: group3_done stays 0 ----
 repeat(30) @(posedge clk);
 #1;
 check((group3_done === 1'b0), "group3_done=0 (only 33 cycles elapsed)");

 // ---- Test 5: Reset restores idle ----
 @(negedge clk); rst = 1'b1;
 @(negedge clk); rst = 1'b0;
 @(posedge clk); #1;

 check((dbg_conv1x1_en === 1'b0), "conv1x1_en=0 after second reset");
 check((extramem_rd_addr=== 14'd0), "extramem_rd_addr=0 after second reset");

 // ---- Summary ----
 $display("---------------------------------------------------------");
 $display("Tested %0d checks", pass_count + fail_count);
 $display("PASS: %0d / %0d", pass_count, pass_count + fail_count);
 $display("FAIL: %0d / %0d", fail_count, pass_count + fail_count);
 if (fail_count == 0) $display("RESULT: *** ALL TESTS PASSED ***");
 else $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
 $display("=========================================================");
 $finish;
 end

endmodule

`default_nettype wire
// =============================================================================
// END tb_group3_top.v
// =============================================================================
