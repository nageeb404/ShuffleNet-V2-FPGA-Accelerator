// =============================================================================
// dw_conv3x3_ctrl.v -- DW 3x3 conv + FIFO sequencing controller (Module 2.8)
// -----------------------------------------------------------------------------
// "The 3by3 DWconv controller controls the operation of the 3by3 DWconv core
// and its connected read and write memories by determining the write enable
// signals and addresses of the memories at the core clock cycle to write the
// processed data either in the X_Left or X_Right memories." --
// DESIGN NOTE ( vs this module):
// 4 FSM states (IDLE/LEFT_S2/RIGHT_S1/RIGHT_S2):
// correspond to different Shuffle Unit invocations with different memory
// routing. This module implements the CORE SEQUENCING LOGIC (IDLE/RUNNING)
// that is identical across all active states. The higher-level 4-state
// orchestration (which memory to read/write, when to coordinate with the
// 1x1 conv controller) is handled by group2_ctrl (Module 2.10) which
// instantiates separate parametric instances for each (W, H, STRIDE)
// configuration and selects between them.
// WHAT THIS MODULE DOES:
// 1. On start pulse: asserts start_fifo for one cycle to trigger
// group2_fifo_ctrl (Module 2.7).
// 2. Drives en=1 to the DW conv core (enables MAC registers) whenever
// the FIFO is shifting data (shift_and_load from FIFO ctrl).
// 3. Asserts data_valid when fifo_state == PROCESS -- this is when the 9
// FIFO taps form a valid 3x3 window and the MAC+adder_tree output is
// correct (1-cycle pipeline: MAC registers product at posedge, adder
// tree gives sum combinationally, result captured on next cycle).
// 4. Counts valid output pixels and generates write address/enable.
// 5. On done_fifo: pulses done and returns to IDLE.
// COUNTER:
// "X_mem Address counter: generates write address to write either in
// X_Left or X_Right memories"
// The write address increments once per data_valid cycle, producing a
// linear raster-scan address 0 .. (OUT_W * OUT_H) - 1.
// PORT MAP:
// clk, rst -- system clock / async reset
// start -- 1-cycle pulse to begin a DW conv frame
// fifo_state -- from group2_fifo_ctrl (to detect PROCESS state)
// done_fifo -- from group2_fifo_ctrl (frame complete)
// shift_and_load -- from group2_fifo_ctrl (forwarded to DW conv core en)
// start_fifo -- to group2_fifo_ctrl
// en -- to DW conv core (MAC register enable)
// data_valid -- DW conv output is valid; capture and write to memory
// wr_addr -- write address for output memory (X_Left or X_Right)
// we -- write enable
// done -- 1-cycle pulse: frame complete
// fsm_state -- 0=IDLE 1=RUNNING (for group2_ctrl / dw_conv3x3_block)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module dw_conv3x3_ctrl #(
 parameter integer AW = 11 // write address width (ceil log2 of max output pixels)
) (
 input wire clk,
 input wire rst,
 input wire start, // 1-cycle start pulse (from group2_ctrl)

 // Interface with group2_fifo_ctrl (Module 2.7)
 input wire [2:0] fifo_state, // current FIFO FSM state
 input wire done_fifo, // frame complete from FIFO controller
 input wire shift_and_load, // forwarded to MAC en (FIFO is shifting)
 output reg start_fifo, // start pulse to FIFO controller

 // DW conv core interface
 output wire en, // MAC register enable (= shift_and_load when RUNNING)

 // Output memory interface
 output wire data_valid, // valid DW conv output pixel (FIFO in PROCESS)
 output reg [AW-1:0] wr_addr, // write address for X_Left or X_Right memory
 output wire we, // write enable (= data_valid)

 // Status
 output reg done, // 1-cycle pulse: all output pixels written
 output wire fsm_state // 0=IDLE 1=RUNNING
);

 // -------------------------------------------------------------------------
 // State encoding (simplified: IDLE=0, RUNNING=1)
 // 4 states (IDLE/LEFT_S2/RIGHT_S1/RIGHT_S2) at the
 // Shuffle-unit level; that orchestration lives in group2_ctrl (Module 2.10).
 // -------------------------------------------------------------------------
 localparam [0:0] S_IDLE = 1'b0;
 localparam [0:0] S_RUNNING = 1'b1;

 // PROCESS state encoding from group2_fifo_ctrl (Module 2.7)
 localparam [2:0] FIFO_PROCESS = 3'd3;

 reg state;
 assign fsm_state = state;

 // MAC units are enabled whenever the FIFO is shifting (so MAC registers
 // track the latest window tap products). Only active in RUNNING state.
 assign en = (state == S_RUNNING) & shift_and_load;

 // data_valid: FIFO is in PROCESS state, valid 3x3 window on the taps.
 // The MAC products are ready 1 cycle after shift_and_load, but since
 // the adder tree is combinational from the registered MAC outputs, the
 // result is already stable at the posedge when en=1 (previous window's
 // products registered at previous posedge). This matches Group 1's
 // convention (en=1 during PROCESS, capture every PROCESS cycle).
 assign data_valid = (state == S_RUNNING) & (fifo_state == FIFO_PROCESS);

 // Write enable mirrors data_valid
 assign we = data_valid;

 // -------------------------------------------------------------------------
 // Sequential FSM + address counter
 // -------------------------------------------------------------------------
 // Ch 6.2.2: rst removed from FSM sensitivity list and body to eliminate the
 // async-reset high-fanout net. FFs initialize to 0 at FPGA configuration,
 // placing the FSM in S_IDLE (= 1'b0) with wr_addr=0 -- correct initial
 // state. rst port kept for interface compatibility.
 always @(posedge clk) begin : fsm_main
 begin
 done <= 1'b0;
 start_fifo <= 1'b0;

 case (state)

 // =============================================================
 // IDLE: wait for start pulse from group2_ctrl
 // =============================================================
 S_IDLE: begin
 wr_addr <= {AW{1'b0}};
 if (start) begin
 start_fifo <= 1'b1; // trigger FIFO controller
 state <= S_RUNNING;
 end
 end

 // =============================================================
 // RUNNING: FIFO controller is processing the feature map.
 // Capture one output pixel per data_valid cycle and write it
 // to the output memory (X_Left or X_Right via external MUX).
 // When done_fifo arrives, pulse done and return to IDLE.
 // =============================================================
 S_RUNNING: begin
 if (data_valid)
 wr_addr <= wr_addr + 1'b1;

 if (done_fifo) begin
 state <= S_IDLE;
 done <= 1'b1;
 end
 end

 default: state <= S_IDLE;

 endcase
 end
 end

endmodule

`default_nettype wire
// =============================================================================
// END dw_conv3x3_ctrl.v
// =============================================================================
