// =============================================================================
// group3_ctrl.v -- Group 3 Counter-based Controller (Module 3.4)
// -----------------------------------------------------------------------------
// "The Group 3 controller is used to orchestrate the execution of all Group 3
// operations." --
// ARCHITECTURE: Counter-datapath (NOT FSM-based).
// Group 3 sequencing driven by 10 counters :
// OPERATION SEQUENCE:
// 1. Wait for start_group from accelerator controller.
// 2. For each of G3_FC_IN/N_PAR_1x1 = 464/29 = 16 accumulation rounds:
// a. Read 29 channels from Extra memory (extramem_read_address advances each cycle)
// b. Feed to 1x1 conv core (en=1 for 29 cycles, acc_clr=1 for first 2 cycles)
// c. Feed to avgpool (acc_en=1 for 16 conv outputs per 7x7 pixel)
// 3. After 1x1 conv done: register file receives avgpool outputs (shift)
// 4. For each of G3_FC_OUT=1000 classes:
// a. Accumulate 32 channels at a time from register file, 1024/32=32 steps
// b. Add bias, quantize, compare with running max (classification)
// 5. Assert group3_done.
// COUNTERS :
// cycle_cnt : main cycle counter (0 to TOTAL_CYCLES-1)
// acc_step_cnt : 0..G3_1X1_N_ACC-1 (=15 steps of 29 channels)
// pix_cnt : 0..G3_1X1_PIXELS-1 (=48 pixels per channel group)
// fc_acc_cnt : 0..G3_FC_ACC_STEPS-1 (=31 steps of 32 channels)
// class_cnt : 0..G3_FC_OUT-1 (=999 classes)
// KEY TIMING PARAMETERS :
// 1x1 conv: N_ACC=16 acc steps, 29 channels each, 7x7=49 pixels
// -> 16*(N_ACC+1)*(7*7) = 16*17*49 = 13328 cycles for 1x1 phase
// Avgpool: accumulates 49 outputs, one per pixel
// FC: 1000 classes * (32+1) steps = 33000 cycles for FC phase
// SIMPLIFIED CONTROL SIGNALS ( /):
// conv1x1_en -- en to conv1x1_g3_core MAC units
// conv1x1_acc_clr -- acc_clr (1 for first 2 steps of each pixel)
// avgpool_acc_en -- accumulate 1 avgpool input per 1x1 output pixel
// avgpool_acc_clr -- clear before first pixel of each channel group
// avgpool_result_we -- capture avgpool result (after 49 pixels)
// regfile_shift -- shift register file (after avgpool done)
// fc_en -- en to fc_core MAC units
// fc_acc_clr -- acc_clr for FC accumulator (1 for first 2 of 32 steps)
// class_we -- latch fc_core result into classification register
// max_update -- update running-maximum register (classification)
// group3_done -- 1-cycle pulse when all 1000 classes processed
// ADDRESS OUTPUTS:
// extramem_rd_addr -- read address for Extra memory (advances each cycle)
// conv1x1_step_out -- current accumulation step (for weight ROM address)
// fc_acc_addr -- current FC accumulation address (for weight ROM)
// fc_bias_addr -- FC bias address (advances each class)
// class_idx -- current class index (for classification output)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module group3_ctrl #(
 // 1x1 conv parameters
 parameter integer G3_N_ACC = 16, // 464 input channels / 29 per step
 parameter integer G3_PIX = 49, // 7x7 output pixels per channel
 parameter integer G3_1X1_FILT = 1024, // total output channels (filter groups)
 parameter integer G3_FILT_PAR = `G3_PW_PAR_FILT, // 16 parallel filters

 // FC layer parameters
 parameter integer G3_FC_IN = `G3_FC_IN, // 1024 input channels
 parameter integer G3_FC_OUT = `G3_FC_OUT, // 1000 output classes
 parameter integer G3_FC_PAR = `G3_FC_PAR_CHAN // 32 parallel channels
) (
 input wire clk,
 input wire rst,
 input wire start_group, // from Accelerator controller

 // 1x1 conv control
 output reg conv1x1_en,
 output reg conv1x1_acc_clr,
 output reg [9:0] conv1x1_step_out, // accumulation step (weight ROM addr)

 // Average pool control
 output reg avgpool_acc_en,
 output reg avgpool_acc_clr,
 output reg avgpool_result_we,

 // Register file control
 output reg regfile_shift,

 // FC core control
 output reg fc_en,
 output reg fc_acc_clr,
 output reg [14:0] fc_acc_addr, // FC weight ROM address (0..32*1000-1)
 output reg [9:0] fc_bias_addr, // FC bias ROM address (0..999)

 // Classification / output
 output reg class_we, // latch FC result
 output reg max_update, // update running max
 output reg [9:0] class_idx, // current class index (0..999)

 // External memory addresses
 output reg [13:0] extramem_rd_addr, // Extra memory read address
 output reg [9:0] regfile_sel_ch, // register file channel select (0..31)

 // Status
 output reg group3_done // 1-cycle pulse
);

 // -------------------------------------------------------------------------
 // FSM states (simplified 3-state machine)
 // -------------------------------------------------------------------------
 localparam [1:0] S_IDLE = 2'd0;
 localparam [1:0] S_CONV = 2'd1; // 1x1 conv + avgpool phase
 localparam [1:0] S_FC = 2'd2; // FC + classification phase

 reg [1:0] state;

 // -------------------------------------------------------------------------
 // Counters
 // -------------------------------------------------------------------------
 // S_CONV phase:
 // For each of G3_1X1_FILT/G3_FILT_PAR = 64 filter groups:
 // For each of G3_PIX = 49 pixels:
 // For each of G3_N_ACC+1 = 17 steps (including wait):
 // 1 cycle: advance extramem_rd_addr
 reg [6:0] filt_grp_cnt; // 0..63 (64 filter groups = 1024/16)
 reg [5:0] pix_cnt; // 0..48 (49 pixels)
 reg [4:0] acc_step_cnt; // 0..16 (17 steps per pixel: N_ACC+1)

 // S_FC phase:
 // For each of G3_FC_OUT=1000 classes:
 // For each of G3_FC_IN/G3_FC_PAR = 32 accumulation steps:
 // 1 cycle
 reg [9:0] fc_class_cnt; // 0..999
 reg [4:0] fc_step_cnt; // 0..32 (33 steps: 32 acc + 1 bias/output)

 // Derived constants
 localparam integer FILT_GROUPS = G3_1X1_FILT / G3_FILT_PAR; // 64
 localparam integer FC_ACC_STEPS = G3_FC_IN / G3_FC_PAR; // 32
 localparam integer N_ACC_PLUS1 = G3_N_ACC + 1; // 17

 // -------------------------------------------------------------------------
 // Sequential state machine + counters
 // -------------------------------------------------------------------------
 always @(posedge clk or posedge rst) begin : ctrl_main
 if (rst) begin
 state <= S_IDLE;
 filt_grp_cnt <= 7'd0;
 pix_cnt <= 6'd0;
 acc_step_cnt <= 5'd0;
 fc_class_cnt <= 10'd0;
 fc_step_cnt <= 5'd0;
 conv1x1_en <= 1'b0;
 conv1x1_acc_clr <= 1'b0;
 conv1x1_step_out <= 10'd0;
 avgpool_acc_en <= 1'b0;
 avgpool_acc_clr <= 1'b0;
 avgpool_result_we<= 1'b0;
 regfile_shift <= 1'b0;
 fc_en <= 1'b0;
 fc_acc_clr <= 1'b0;
 fc_acc_addr <= 15'd0;
 fc_bias_addr <= 10'd0;
 class_we <= 1'b0;
 max_update <= 1'b0;
 class_idx <= 10'd0;
 extramem_rd_addr <= 14'd0;
 regfile_sel_ch <= 10'd0;
 group3_done <= 1'b0;
 end else begin
 // Default: clear single-cycle pulses
 conv1x1_en <= 1'b0;
 conv1x1_acc_clr <= 1'b0;
 avgpool_acc_en <= 1'b0;
 avgpool_acc_clr <= 1'b0;
 avgpool_result_we<= 1'b0;
 regfile_shift <= 1'b0;
 fc_en <= 1'b0;
 fc_acc_clr <= 1'b0;
 class_we <= 1'b0;
 max_update <= 1'b0;
 group3_done <= 1'b0;

 case (state)

 // =============================================================
 // IDLE: wait for start_group
 // =============================================================
 S_IDLE: begin
 filt_grp_cnt <= 7'd0;
 pix_cnt <= 6'd0;
 acc_step_cnt <= 5'd0;
 fc_class_cnt <= 10'd0;
 fc_step_cnt <= 5'd0;
 fc_acc_addr <= 15'd0;
 fc_bias_addr <= 10'd0;
 class_idx <= 10'd0;
 extramem_rd_addr <= 14'd0;
 regfile_sel_ch <= 10'd0;

 if (start_group) begin
 state <= S_CONV;
 conv1x1_en <= 1'b1;
 conv1x1_acc_clr <= 1'b1; // first step: clear acc
 extramem_rd_addr<= 14'd0;
 avgpool_acc_clr <= 1'b1; // clear pool before first pixel
 end
 end

 // =============================================================
 // S_CONV: 1x1 conv + avgpool phase
 // 64 filter groups x 49 pixels x 17 steps
 // =============================================================
 S_CONV: begin
 // Advance extramem read address every cycle
 extramem_rd_addr <= extramem_rd_addr + 14'd1;

 // Increment step counter
 if (acc_step_cnt < N_ACC_PLUS1[4:0] - 1)
 acc_step_cnt <= acc_step_cnt + 5'd1;
 else begin
 acc_step_cnt <= 5'd0;

 // Pixel done
 if (pix_cnt < G3_PIX[5:0] - 1) begin
 pix_cnt <= pix_cnt + 6'd1;
 // Enable avgpool for this pixel's 1x1 output
 avgpool_acc_en <= 1'b1;
 end else begin
 pix_cnt <= 6'd0;
 // Last pixel: capture avgpool result, shift reg file
 avgpool_result_we <= 1'b1;
 regfile_shift <= 1'b1;
 avgpool_acc_clr <= 1'b1; // clear for next group

 // Filter group done
 if (filt_grp_cnt < FILT_GROUPS[6:0] - 1) begin
 filt_grp_cnt <= filt_grp_cnt + 7'd1;
 extramem_rd_addr <= 14'd0; // reset for next fg
 end else begin
 // All 1x1 conv groups done -> switch to FC
 filt_grp_cnt <= 7'd0;
 extramem_rd_addr <= 14'd0;
 state <= S_FC;
 fc_en <= 1'b1;
 fc_acc_clr <= 1'b1;
 regfile_sel_ch <= 10'd0;
 end
 end
 end

 // 1x1 conv control signals
 conv1x1_en <= 1'b1;
 conv1x1_acc_clr <= (acc_step_cnt == 0) ? 1'b1 : 1'b0;
 conv1x1_step_out <= {5'd0, acc_step_cnt};
 end

 // =============================================================
 // S_FC: FC + classification phase
 // 1000 classes x 33 steps (32 acc + 1 output)
 // =============================================================
 S_FC: begin
 regfile_sel_ch <= {5'd0, fc_step_cnt};

 if (fc_step_cnt < FC_ACC_STEPS[4:0]) begin
 // Accumulation step
 fc_en <= 1'b1;
 fc_acc_clr <= (fc_step_cnt == 0) ? 1'b1 : 1'b0;
 fc_acc_addr<= fc_acc_addr + 15'd1;
 fc_step_cnt<= fc_step_cnt + 5'd1;
 end else begin
 // Output step: latch result and update max
 fc_step_cnt <= 5'd0;
 class_we <= 1'b1;
 max_update <= 1'b1;
 class_idx <= fc_class_cnt;

 if (fc_class_cnt < G3_FC_OUT[9:0] - 1) begin
 fc_class_cnt <= fc_class_cnt + 10'd1;
 fc_bias_addr <= fc_bias_addr + 10'd1;
 fc_en <= 1'b1;
 fc_acc_clr <= 1'b1;
 end else begin
 // All classes processed
 state <= S_IDLE;
 group3_done <= 1'b1;
 end
 end
 end

 default: state <= S_IDLE;

 endcase
 end
 end

endmodule

`default_nettype wire
// =============================================================================
// END group3_ctrl.v
// =============================================================================
