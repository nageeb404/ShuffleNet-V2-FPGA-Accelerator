// =============================================================================
// conv1x1_ctrl.v -- 1x1 pointwise conv accumulation controller (Module 2.9)
// -----------------------------------------------------------------------------
// "The 1by1 Conv controller is used to control the 1by1 Conv core, the filter
// and bias memories and the feature map memory by controlling the enable,
// acc_clr, and addresses." --
// DESIGN NOTE ( 7-state FSM vs this module):
// 7 control states (IDLE/S2_Right_1st/Left_1st/S1_Right_1st/
// Right_2nd/Write_Sh_data/Write_Extra_Mem) that route the 1x1 conv output to
// different memories (Y, Shuffle, Extra) per Shuffle unit invocation. This
// module implements the CORE ACCUMULATION SEQUENCING (IDLE/RUNNING) that is
// identical across all active states. The higher-level 7-state orchestration
// (memory routing, done1_1/done3_3 coordination) belongs in group2_ctrl (2.10).
// ACCUMULATION SEQUENCE (N_ACC=7, matching conv1x1_filter_unit pipeline):
// Due to the MAC pipeline register (1-cycle delay), acc_clr=1 is held for the
// first TWO steps of each pixel so that step-0 products settle correctly:
// step 0: acc_clr=1, en=1 (MAC registers step-0 products; acc = 0 + old)
// step 1: acc_clr=1, en=1 (acc = 0 + step-0 sum; MAC registers step-1)
// steps 2..N_ACC-1: acc_clr=0, en=1 (acc = acc + step products)
// step N_ACC (wait cycle): acc_clr=0, en=1, we=1 (final sum ready; write)
// Total cycles per output pixel: N_ACC + 1 = 8.
// ADDRESS / TIMING OUTPUTS:
// wr_addr : combinational from pix_cnt -- valid address when we=1
// step_out : combinational from step_cnt (0..N_ACC-1); for weight ROM address
// we : combinational; high on step N_ACC (wait cycle)
// PORT MAP:
// clk, rst -- system clock / async reset
// start -- 1-cycle start pulse (from group2_ctrl)
// en -- to conv1x1_core MAC units
// acc_clr -- to conv1x1_core accumulator MUX
// we -- write enable for output feature map memory
// wr_addr -- write address (= pix_cnt, combinational)
// step_out -- current accumulation step (for weight/bias ROM address)
// done -- 1-cycle pulse: all W*H output pixels complete
// fsm_state -- 0=IDLE 1=RUNNING
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module conv1x1_ctrl #(
 parameter integer W = `G2_W_MAX, // output feature map width
 parameter integer H = `G2_W_MAX, // output feature map height
 parameter integer N_ACC = 7, // accumulation steps per pixel
 parameter integer AW = 12 // address width (>= ceil(log2(W*H)))
) (
 input wire clk,
 input wire rst,
 input wire start, // 1-cycle start pulse (from group2_ctrl)

 // conv1x1_core interface
 output reg en, // MAC register enable
 output reg acc_clr, // 1 for steps 0,1; 0 for steps 2..N_ACC

 // Output memory interface
 output wire we, // write enable (high on step N_ACC)
 output wire [AW-1:0] wr_addr, // write address (combinational from pix_cnt)

 // Step index for weight/bias ROM address generation (combinational)
 output wire [4:0] step_out, // 0..N_ACC-1 (5 bits for N_ACC <= 31)

 // Status
 output reg done, // 1-cycle pulse: all W*H pixels complete
 output wire fsm_state // 0=IDLE 1=RUNNING
);

 // -------------------------------------------------------------------------
 // State encoding
 // -------------------------------------------------------------------------
 localparam [0:0] S_IDLE = 1'b0;
 localparam [0:0] S_RUNNING = 1'b1;

 // step_cnt: 0..N_ACC (N_ACC+1 values; N_ACC+1 = 21 for N_ACC=20, needs 5 bits)
 localparam integer STEP_BITS = 5; // safe for N_ACC <= 31
 localparam [STEP_BITS-1:0] STEP_MAX = N_ACC[STEP_BITS-1:0];

 reg state;
 reg [STEP_BITS-1:0] step_cnt;
 reg [AW-1:0] pix_cnt;

 assign fsm_state = state;

 // Combinational outputs
 assign we = (state == S_RUNNING) & (step_cnt == STEP_MAX);
 assign wr_addr = pix_cnt; // valid when we=1
 assign step_out = step_cnt[4:0]; // 0..N_ACC-1

 // -------------------------------------------------------------------------
 // Sequential FSM + counters
 // -------------------------------------------------------------------------
 always @(posedge clk or posedge rst) begin : fsm_main
 if (rst) begin
 state <= S_IDLE;
 step_cnt <= {STEP_BITS{1'b0}};
 pix_cnt <= {AW{1'b0}};
 en <= 1'b0;
 acc_clr <= 1'b0;
 done <= 1'b0;
 end else begin
 done <= 1'b0;

 case (state)

 // =============================================================
 // IDLE: wait for start pulse; hold all outputs low
 // =============================================================
 S_IDLE: begin
 en <= 1'b0;
 acc_clr <= 1'b0;
 step_cnt <= {STEP_BITS{1'b0}};
 pix_cnt <= {AW{1'b0}};
 if (start)
 state <= S_RUNNING;
 end

 // =============================================================
 // RUNNING: sequence N_ACC+1 cycles per output pixel.
 // step_cnt 0..N_ACC-1: accumulation
 // acc_clr=1 for steps 0,1 (MAC pipeline settling period)
 // acc_clr=0 for steps 2..N_ACC-1
 // step_cnt N_ACC: wait cycle
 // we=1 (combinational), write output pixel at wr_addr=pix_cnt
 // acc_clr=0, en=1
 // pix_cnt increments; step_cnt resets to 0
 // =============================================================
 S_RUNNING: begin
 en <= 1'b1;

 // acc_clr=1 for first two accumulation steps
 if (step_cnt == {STEP_BITS{1'b0}} ||
 step_cnt == {{STEP_BITS-1{1'b0}}, 1'b1})
 acc_clr <= 1'b1;
 else
 acc_clr <= 1'b0;

 if (step_cnt == STEP_MAX) begin
 // Wait cycle: output is valid, we=1 (combinational)
 step_cnt <= {STEP_BITS{1'b0}};

 if (pix_cnt == (W * H - 1)) begin
 // Last pixel complete
 state <= S_IDLE;
 pix_cnt <= {AW{1'b0}};
 done <= 1'b1;
 en <= 1'b0;
 acc_clr <= 1'b0;
 end else begin
 pix_cnt <= pix_cnt + 1'b1;
 end
 end else begin
 step_cnt <= step_cnt + {{STEP_BITS-1{1'b0}}, 1'b1};
 end
 end

 default: state <= S_IDLE;

 endcase
 end
 end

endmodule

`default_nettype wire
// =============================================================================
// END conv1x1_ctrl.v
// =============================================================================
