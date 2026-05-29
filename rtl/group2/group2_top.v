// =============================================================================
// group2_top.v -- Group 2 Top-level Structural Integration (Module 2.11)
// -----------------------------------------------------------------------------
// Path A modification (ZU19EG): internal DW buffer replaces external
// dw_results_flat / dw_wr_addr / dw_we ports and the pw_data_in external port.
// The DW 3x3 conv output is stored in a 58-instance x 784-word x G2_FM_W
// distributed RAM (combinational read). After DW phase completes, the PW
// conv reads directly from this buffer, stepping through 12 channels per
// accumulation step.
// The G2_PW_PAR_CHAN was reduced from 29 to 12 for ZU19EG DSP budget.
// N_ACC per config: cfg0=2(24ch), cfg1=5(58ch), cfg2=5(58ch),
// cfg3=10(116ch), cfg4=10(116ch), cfg5=20(232ch).
// For configs with N_ACC>5 (cfg3-5), PW steps 0-4 draw real DW output
// (channels 0-57), and steps 5+ receive zeros from the 58-channel buffer.
// Full multi-pass DW support for stages 3-4 is handled in Step 7 (weight ROMs).
// SIX CONFIGURATIONS (unique (W_in, H_in, STRIDE)):
// Config 0: W=56, H=56, STRIDE=2 -> OUT=28x28 (loops=0)
// Config 1: W=28, H=28, STRIDE=1 -> OUT=28x28 (loops=1..3)
// Config 2: W=28, H=28, STRIDE=2 -> OUT=14x14 (loops=4)
// Config 3: W=14, H=14, STRIDE=1 -> OUT=14x14 (loops=5..11)
// Config 4: W=14, H=14, STRIDE=2 -> OUT=7x7 (loops=12)
// Config 5: W=7, H=7, STRIDE=1 -> OUT=7x7 (loops=13..15)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module group2_top (
 input wire clk,
 input wire rst,

 // ---- Group-level control ----
 input wire start_group,
 output wire group2_done,

 // ---- Feature map FIFO input (per DW channel) ----
 input wire [`G2_DW_PAR_FILT*`G1_FM_W-1:0] fm_data_in,

 // Feature map read address (from active fifo_ctrl -> external maxpool memory)
 output wire [11:0] fm_rd_addr,

 // ---- 1x1 PW conv output (to extra_mem via accelerator_top) ----
 output wire [`G2_PW_PAR_FILT*`G2_FM_W-1:0] pw_results_flat,
 output wire [11:0] pw_wr_addr,
 output wire pw_we,

 // ---- Status / debug ----
 output wire [4:0] loops,
 output wire [1:0] fsm_state
);

 // =========================================================================
 // Localparams
 // =========================================================================
 localparam integer DATA_W = `DATA_W;
 localparam integer G1_FM_W = `G1_FM_W; // 10
 localparam integer G2_DW_WW = `G2_DW_WW; // 15
 localparam integer G2_FM_W = `G2_FM_W; // 12
 localparam integer G2_PW_WW = `G2_PW_WW; // 11
 localparam integer G2_BIAS_W = `G2_BIAS_W; // 13
 localparam integer N_FILT = `G2_DW_PAR_FILT; // 58
 localparam integer N_CHAN = `G2_PW_PAR_CHAN; // 12
 localparam integer AW = 12;

 // DW buffer sizing: 784 = 16 acc_groups x 49 pixels (7x7 max spatial size)
 localparam integer DW_BUF_WORDS = 784;
 localparam integer DW_BUF_AW = 10; // ceil(log2(784)) = 10

 // Number of valid PW steps from 58-ch DW buffer: ceil(58/12) = 5
 // Steps 0-4: channels 0-11, 12-23, 24-35, 36-47, 48-59 (ch58,59=zero-pad)
 // Steps 5+: return zeros (for N_ACC=10/20 configs; full accuracy needs Step7 ROMs)
 localparam integer DW_BUF_PAD_CH = 60; // ceil(58/12)*12 = 5*12 = 60

 // =========================================================================
 // 1. group2_ctrl -- sequential DW-then-PW orchestrator
 // =========================================================================
 wire [1:0] gc_start;
 wire [5:0] gc_width;
 wire gc_stride;
 wire gc_done_dw;
 wire gc_done_1x1;

 group2_ctrl u_ctrl (
 .clk (clk),
 .rst (rst),
 .start_group(start_group),
 .done_dw (gc_done_dw),
 .done_1x1 (gc_done_1x1),
 .start (gc_start),
 .width (gc_width),
 .stride (gc_stride),
 .fsm_state (fsm_state),
 .loops (loops),
 .group2_done(group2_done)
 );

 // =========================================================================
 // 2. Config select: gc_start[0]=DW start, gc_start[1]=PW start.
 // Config identified by (gc_width, gc_stride); stable during both phases.
 // =========================================================================

 // Config 0: W=56 input, STRIDE=2 (loops=0)
 wire cfg_start_dw_0 = gc_start[0] & (gc_width == 6'd56) & gc_stride;
 wire cfg_start_pw_0 = gc_start[1] & (gc_width == 6'd56) & gc_stride;
 // Config 1: W=28 input, STRIDE=1 (loops=1,2,3)
 wire cfg_start_dw_1 = gc_start[0] & (gc_width == 6'd28) & ~gc_stride;
 wire cfg_start_pw_1 = gc_start[1] & (gc_width == 6'd28) & ~gc_stride;
 // Config 2: W=28 input, STRIDE=2 (loops=4)
 wire cfg_start_dw_2 = gc_start[0] & (gc_width == 6'd28) & gc_stride;
 wire cfg_start_pw_2 = gc_start[1] & (gc_width == 6'd28) & gc_stride;
 // Config 3: W=14 input, STRIDE=1 (loops=5..11)
 wire cfg_start_dw_3 = gc_start[0] & (gc_width == 6'd14) & ~gc_stride;
 wire cfg_start_pw_3 = gc_start[1] & (gc_width == 6'd14) & ~gc_stride;
 // Config 4: W=14 input, STRIDE=2 (loops=12)
 wire cfg_start_dw_4 = gc_start[0] & (gc_width == 6'd14) & gc_stride;
 wire cfg_start_pw_4 = gc_start[1] & (gc_width == 6'd14) & gc_stride;
 // Config 5: W=7 input, STRIDE=1 (loops=13..15)
 wire cfg_start_dw_5 = gc_start[0] & (gc_width == 6'd7) & ~gc_stride;
 wire cfg_start_pw_5 = gc_start[1] & (gc_width == 6'd7) & ~gc_stride;

 // =========================================================================
 // 3. width_sel for group2_fifo instances
 // =========================================================================
 reg [1:0] cur_width_sel;
 always @(*) begin
 case (gc_width)
 6'd7: cur_width_sel = 2'b00;
 6'd14: cur_width_sel = 2'b01;
 6'd28: cur_width_sel = 2'b10;
 default: cur_width_sel = 2'b11; // 56
 endcase
 end

 // =========================================================================
 // 4. Per-config ctrl triplets: group2_fifo_ctrl + dw_conv3x3_ctrl + conv1x1_ctrl
 // =========================================================================

 wire sal_0, sal_1, sal_2, sal_3, sal_4, sal_5;
 wire ps_0, ps_1, ps_2, ps_3, ps_4, ps_5;
 wire [AW-1:0] fra_0, fra_1, fra_2, fra_3, fra_4, fra_5;
 wire [2:0] fst_0, fst_1, fst_2, fst_3, fst_4, fst_5;
 wire dff_0, dff_1, dff_2, dff_3, dff_4, dff_5;

 wire sf_0, sf_1, sf_2, sf_3, sf_4, sf_5;

 wire en_dw_0, en_dw_1, en_dw_2, en_dw_3, en_dw_4, en_dw_5;
 wire [AW-1:0] dw_wa_0, dw_wa_1, dw_wa_2, dw_wa_3, dw_wa_4, dw_wa_5;
 wire we_dw_0, we_dw_1, we_dw_2, we_dw_3, we_dw_4, we_dw_5;
 wire dn_dw_0, dn_dw_1, dn_dw_2, dn_dw_3, dn_dw_4, dn_dw_5;

 wire en_pw_0, en_pw_1, en_pw_2, en_pw_3, en_pw_4, en_pw_5;
 wire ac_pw_0, ac_pw_1, ac_pw_2, ac_pw_3, ac_pw_4, ac_pw_5;
 wire [AW-1:0] pw_wa_0, pw_wa_1, pw_wa_2, pw_wa_3, pw_wa_4, pw_wa_5;
 wire we_pw_0, we_pw_1, we_pw_2, we_pw_3, we_pw_4, we_pw_5;
 wire dn_pw_0, dn_pw_1, dn_pw_2, dn_pw_3, dn_pw_4, dn_pw_5;
 wire [4:0] pw_step_0, pw_step_1, pw_step_2, pw_step_3, pw_step_4, pw_step_5;

 // ---- Config 0: W=56, H=56, STRIDE=2, OUT=28x28 ----
 group2_fifo_ctrl #(.W(56), .H(56), .STRIDE(2), .AW(AW)) u_fctl_0 (
 .clk(clk), .rst(rst), .start(sf_0),
 .shift_and_load(sal_0), .padding_sel(ps_0),
 .width_sel, .rd_addr(fra_0), .fsm_state(fst_0), .done(dff_0));

 dw_conv3x3_ctrl #(.AW(AW)) u_dw_0 (
 .clk(clk), .rst(rst), .start(cfg_start_dw_0),
 .fifo_state(fst_0), .done_fifo(dff_0), .shift_and_load(sal_0),
 .start_fifo(sf_0), .en(en_dw_0), .data_valid, .wr_addr(dw_wa_0),
 .we(we_dw_0), .done(dn_dw_0), .fsm_state);

 conv1x1_ctrl #(.W(28), .H(28), .N_ACC(2), .AW(AW)) u_pw_0 (
 .clk(clk), .rst(rst), .start(cfg_start_pw_0),
 .en(en_pw_0), .acc_clr(ac_pw_0), .we(we_pw_0),
 .wr_addr(pw_wa_0), .step_out(pw_step_0), .done(dn_pw_0), .fsm_state);

 // ---- Config 1: W=28, H=28, STRIDE=1, OUT=28x28 ----
 group2_fifo_ctrl #(.W(28), .H(28), .STRIDE(1), .AW(AW)) u_fctl_1 (
 .clk(clk), .rst(rst), .start(sf_1),
 .shift_and_load(sal_1), .padding_sel(ps_1),
 .width_sel, .rd_addr(fra_1), .fsm_state(fst_1), .done(dff_1));

 dw_conv3x3_ctrl #(.AW(AW)) u_dw_1 (
 .clk(clk), .rst(rst), .start(cfg_start_dw_1),
 .fifo_state(fst_1), .done_fifo(dff_1), .shift_and_load(sal_1),
 .start_fifo(sf_1), .en(en_dw_1), .data_valid, .wr_addr(dw_wa_1),
 .we(we_dw_1), .done(dn_dw_1), .fsm_state);

 conv1x1_ctrl #(.W(28), .H(28), .N_ACC(5), .AW(AW)) u_pw_1 (
 .clk(clk), .rst(rst), .start(cfg_start_pw_1),
 .en(en_pw_1), .acc_clr(ac_pw_1), .we(we_pw_1),
 .wr_addr(pw_wa_1), .step_out(pw_step_1), .done(dn_pw_1), .fsm_state);

 // ---- Config 2: W=28, H=28, STRIDE=2, OUT=14x14 ----
 group2_fifo_ctrl #(.W(28), .H(28), .STRIDE(2), .AW(AW)) u_fctl_2 (
 .clk(clk), .rst(rst), .start(sf_2),
 .shift_and_load(sal_2), .padding_sel(ps_2),
 .width_sel, .rd_addr(fra_2), .fsm_state(fst_2), .done(dff_2));

 dw_conv3x3_ctrl #(.AW(AW)) u_dw_2 (
 .clk(clk), .rst(rst), .start(cfg_start_dw_2),
 .fifo_state(fst_2), .done_fifo(dff_2), .shift_and_load(sal_2),
 .start_fifo(sf_2), .en(en_dw_2), .data_valid, .wr_addr(dw_wa_2),
 .we(we_dw_2), .done(dn_dw_2), .fsm_state);

 conv1x1_ctrl #(.W(14), .H(14), .N_ACC(5), .AW(AW)) u_pw_2 (
 .clk(clk), .rst(rst), .start(cfg_start_pw_2),
 .en(en_pw_2), .acc_clr(ac_pw_2), .we(we_pw_2),
 .wr_addr(pw_wa_2), .step_out(pw_step_2), .done(dn_pw_2), .fsm_state);

 // ---- Config 3: W=14, H=14, STRIDE=1, OUT=14x14 ----
 group2_fifo_ctrl #(.W(14), .H(14), .STRIDE(1), .AW(AW)) u_fctl_3 (
 .clk(clk), .rst(rst), .start(sf_3),
 .shift_and_load(sal_3), .padding_sel(ps_3),
 .width_sel, .rd_addr(fra_3), .fsm_state(fst_3), .done(dff_3));

 dw_conv3x3_ctrl #(.AW(AW)) u_dw_3 (
 .clk(clk), .rst(rst), .start(cfg_start_dw_3),
 .fifo_state(fst_3), .done_fifo(dff_3), .shift_and_load(sal_3),
 .start_fifo(sf_3), .en(en_dw_3), .data_valid, .wr_addr(dw_wa_3),
 .we(we_dw_3), .done(dn_dw_3), .fsm_state);

 conv1x1_ctrl #(.W(14), .H(14), .N_ACC(10), .AW(AW)) u_pw_3 (
 .clk(clk), .rst(rst), .start(cfg_start_pw_3),
 .en(en_pw_3), .acc_clr(ac_pw_3), .we(we_pw_3),
 .wr_addr(pw_wa_3), .step_out(pw_step_3), .done(dn_pw_3), .fsm_state);

 // ---- Config 4: W=14, H=14, STRIDE=2, OUT=7x7 ----
 group2_fifo_ctrl #(.W(14), .H(14), .STRIDE(2), .AW(AW)) u_fctl_4 (
 .clk(clk), .rst(rst), .start(sf_4),
 .shift_and_load(sal_4), .padding_sel(ps_4),
 .width_sel, .rd_addr(fra_4), .fsm_state(fst_4), .done(dff_4));

 dw_conv3x3_ctrl #(.AW(AW)) u_dw_4 (
 .clk(clk), .rst(rst), .start(cfg_start_dw_4),
 .fifo_state(fst_4), .done_fifo(dff_4), .shift_and_load(sal_4),
 .start_fifo(sf_4), .en(en_dw_4), .data_valid, .wr_addr(dw_wa_4),
 .we(we_dw_4), .done(dn_dw_4), .fsm_state);

 conv1x1_ctrl #(.W(7), .H(7), .N_ACC(10), .AW(AW)) u_pw_4 (
 .clk(clk), .rst(rst), .start(cfg_start_pw_4),
 .en(en_pw_4), .acc_clr(ac_pw_4), .we(we_pw_4),
 .wr_addr(pw_wa_4), .step_out(pw_step_4), .done(dn_pw_4), .fsm_state);

 // ---- Config 5: W=7, H=7, STRIDE=1, OUT=7x7 ----
 group2_fifo_ctrl #(.W(7), .H(7), .STRIDE(1), .AW(AW)) u_fctl_5 (
 .clk(clk), .rst(rst), .start(sf_5),
 .shift_and_load(sal_5), .padding_sel(ps_5),
 .width_sel, .rd_addr(fra_5), .fsm_state(fst_5), .done(dff_5));

 dw_conv3x3_ctrl #(.AW(AW)) u_dw_5 (
 .clk(clk), .rst(rst), .start(cfg_start_dw_5),
 .fifo_state(fst_5), .done_fifo(dff_5), .shift_and_load(sal_5),
 .start_fifo(sf_5), .en(en_dw_5), .data_valid, .wr_addr(dw_wa_5),
 .we(we_dw_5), .done(dn_dw_5), .fsm_state);

 conv1x1_ctrl #(.W(7), .H(7), .N_ACC(20), .AW(AW)) u_pw_5 (
 .clk(clk), .rst(rst), .start(cfg_start_pw_5),
 .en(en_pw_5), .acc_clr(ac_pw_5), .we(we_pw_5),
 .wr_addr(pw_wa_5), .step_out(pw_step_5), .done(dn_pw_5), .fsm_state);

 // =========================================================================
 // 5. OR-reduce shared control signals (only one config active at a time)
 // =========================================================================
 wire shared_sal = sal_0 | sal_1 | sal_2 | sal_3 | sal_4 | sal_5;
 wire shared_ps = ps_0 | ps_1 | ps_2 | ps_3 | ps_4 | ps_5;

 assign fm_rd_addr = fra_0 | fra_1 | fra_2 | fra_3 | fra_4 | fra_5;

 wire shared_en_dw = en_dw_0 | en_dw_1 | en_dw_2 | en_dw_3 | en_dw_4 | en_dw_5;

 // DW buffer write controls (internal)
 wire [AW-1:0] shared_dw_wr_addr = dw_wa_0 | dw_wa_1 | dw_wa_2 | dw_wa_3 | dw_wa_4 | dw_wa_5;
 wire shared_dw_we = we_dw_0 | we_dw_1 | we_dw_2 | we_dw_3 | we_dw_4 | we_dw_5;

 wire shared_en_pw = en_pw_0 | en_pw_1 | en_pw_2 | en_pw_3 | en_pw_4 | en_pw_5;
 wire shared_ac_pw = ac_pw_0 | ac_pw_1 | ac_pw_2 | ac_pw_3 | ac_pw_4 | ac_pw_5;

 assign pw_wr_addr = pw_wa_0 | pw_wa_1 | pw_wa_2 | pw_wa_3 | pw_wa_4 | pw_wa_5;
 assign pw_we = we_pw_0 | we_pw_1 | we_pw_2 | we_pw_3 | we_pw_4 | we_pw_5;

 assign gc_done_dw = dn_dw_0 | dn_dw_1 | dn_dw_2 | dn_dw_3 | dn_dw_4 | dn_dw_5;
 assign gc_done_1x1 = dn_pw_0 | dn_pw_1 | dn_pw_2 | dn_pw_3 | dn_pw_4 | dn_pw_5;

 // PW step and pixel address for DW buffer read (combinational from active pw_ctrl)
 wire [4:0] shared_pw_step = pw_step_0 | pw_step_1 | pw_step_2 | pw_step_3 | pw_step_4 | pw_step_5;
 wire [AW-1:0] shared_pw_rd_addr = pw_wa_0 | pw_wa_1 | pw_wa_2 | pw_wa_3 | pw_wa_4 | pw_wa_5;

 // =========================================================================
 // 6. group2_fifo x58: one per DW channel
 // =========================================================================
 wire [N_FILT*9*G1_FM_W-1:0] dw_data_flat;

 genvar f;
 generate
 for (f = 0; f < N_FILT; f = f + 1) begin : gen_fifo

 wire signed [G1_FM_W-1:0] t00, t01, t02;
 wire signed [G1_FM_W-1:0] t10, t11, t12;
 wire signed [G1_FM_W-1:0] t20, t21, t22;

 group2_fifo u_fifo (
 .clk (clk),
 .rst (rst),
 .shift_and_load(shared_sal),
 .padding_sel (shared_ps),
 .width_sel (cur_width_sel),
 .data_in (fm_data_in[f*G1_FM_W +: G1_FM_W]),
 .tap00(t00), .tap01(t01), .tap02(t02),
 .tap10(t10), .tap11(t11), .tap12(t12),
 .tap20(t20), .tap21(t21), .tap22(t22)
 );

 assign dw_data_flat[(f*9+0)*G1_FM_W +: G1_FM_W] = t00;
 assign dw_data_flat[(f*9+1)*G1_FM_W +: G1_FM_W] = t01;
 assign dw_data_flat[(f*9+2)*G1_FM_W +: G1_FM_W] = t02;
 assign dw_data_flat[(f*9+3)*G1_FM_W +: G1_FM_W] = t10;
 assign dw_data_flat[(f*9+4)*G1_FM_W +: G1_FM_W] = t11;
 assign dw_data_flat[(f*9+5)*G1_FM_W +: G1_FM_W] = t12;
 assign dw_data_flat[(f*9+6)*G1_FM_W +: G1_FM_W] = t20;
 assign dw_data_flat[(f*9+7)*G1_FM_W +: G1_FM_W] = t21;
 assign dw_data_flat[(f*9+8)*G1_FM_W +: G1_FM_W] = t22;
 end
 endgenerate

 // =========================================================================
 // 7. Weight / bias ROMs (DW and PW, all internal -- no external weight ports)
 // =========================================================================
 wire [7829:0] dw_weights_rom_out;
 wire [869:0] dw_biases_rom_out;
 wire [7655:0] pw_weights_rom_out;
 wire [753:0] pw_biases_rom_out;

 g2_dw_weight_rom u_dw_w_rom (
 .addr (loops[3:0]),
 .data_out(dw_weights_rom_out)
 );

 g2_dw_bias_rom u_dw_b_rom (
 .addr (loops[3:0]),
 .data_out(dw_biases_rom_out)
 );

 // PW weight ROM addr: loop*20 + step = (loop<<4) + (loop<<2) + step
 wire [8:0] pw_w_loops_9b = {5'b0, loops[3:0]};
 wire [8:0] pw_w_step_9b = {4'b0, shared_pw_step};
 wire [8:0] pw_w_addr = (pw_w_loops_9b << 4) + (pw_w_loops_9b << 2) + pw_w_step_9b;

 g2_pw_weight_rom u_pw_w_rom (
 .addr (pw_w_addr),
 .data_out(pw_weights_rom_out)
 );

 g2_pw_bias_rom u_pw_b_rom (
 .addr (loops[3:0]),
 .data_out(pw_biases_rom_out)
 );

 // =========================================================================
 // 8. dw_conv3x3_core -- 58-parallel DW 3x3 convolution
 // =========================================================================
 wire [N_FILT*G2_FM_W-1:0] dw_results_int; // internal (was external output)

 dw_conv3x3_core u_dw_core (
 .clk (clk),
 .rst (rst),
 .en (shared_en_dw),
 .data_flat (dw_data_flat),
 .weights_flat(dw_weights_rom_out),
 .biases_flat (dw_biases_rom_out),
 .results_flat(dw_results_int)
 );

 // =========================================================================
 // 8. Internal DW buffer: 58 instances x 784 words x G2_FM_W bits
 // Distributed RAM with combinational read (zero latency at pixel boundary).
 // Vivado infers LUT-RAM from (* ram_style = "distributed" *).
 // Write: synchronous, from dw_conv3x3_core results on shared_dw_we.
 // Read: combinational, addressed by current PW pixel (shared_pw_rd_addr).
 // =========================================================================
 wire [N_FILT*G2_FM_W-1:0] dw_buf_out_flat; // 58*12 = 696 bits combinational

 genvar c;
 generate
 for (c = 0; c < N_FILT; c = c + 1) begin : gen_dw_buf

 (* ram_style = "distributed" *) reg [G2_FM_W-1:0] dw_buf_mem [0:DW_BUF_WORDS-1];

 integer bi;
 initial begin
 for (bi = 0; bi < DW_BUF_WORDS; bi = bi + 1)
 dw_buf_mem[bi] = {G2_FM_W{1'b0}};
 end

 // Write: synchronous on DW write-enable
 always @(posedge clk) begin
 if (shared_dw_we)
 dw_buf_mem[shared_dw_wr_addr[DW_BUF_AW-1:0]] <=
 dw_results_int[c*G2_FM_W +: G2_FM_W];
 end

 // Read: combinational (no registered latency)
 assign dw_buf_out_flat[c*G2_FM_W +: G2_FM_W] =
 dw_buf_mem[shared_pw_rd_addr[DW_BUF_AW-1:0]];

 end
 endgenerate

 // =========================================================================
 // 9. PW channel MUX: select 12 channels from DW buffer per PW step.
 // 60-channel zero-padded view: channels 0-57 valid, 58-59 = zero.
 // Case on shared_pw_step (0-4 read real DW; 5+ return zeros).
 // =========================================================================

 // Build 60-channel padded bus (720 bits)
 wire [G2_FM_W*DW_BUF_PAD_CH-1:0] dw_buf_padded;
 assign dw_buf_padded[G2_FM_W*N_FILT-1:0] = dw_buf_out_flat;
 assign dw_buf_padded[G2_FM_W*DW_BUF_PAD_CH-1:G2_FM_W*N_FILT] =
 {((DW_BUF_PAD_CH-N_FILT)*G2_FM_W){1'b0}};

 // PW input bus: 12 channels x G2_FM_W bits
 localparam integer PW_STEP_W = N_CHAN * G2_FM_W; // 12*12 = 144 bits per step

 reg [PW_STEP_W-1:0] pw_data_in_int;
 always @(*) begin
 case (shared_pw_step)
 5'd0: pw_data_in_int = dw_buf_padded[0*PW_STEP_W +: PW_STEP_W];
 5'd1: pw_data_in_int = dw_buf_padded[1*PW_STEP_W +: PW_STEP_W];
 5'd2: pw_data_in_int = dw_buf_padded[2*PW_STEP_W +: PW_STEP_W];
 5'd3: pw_data_in_int = dw_buf_padded[3*PW_STEP_W +: PW_STEP_W];
 5'd4: pw_data_in_int = dw_buf_padded[4*PW_STEP_W +: PW_STEP_W];
 default: pw_data_in_int = {PW_STEP_W{1'b0}}; // steps 5-20: zero
 endcase
 end

 // =========================================================================
 // 10. conv1x1_core -- 58-parallel 1x1 PW convolution
 // 12 data inputs driven from DW buffer via PW channel MUX.
 // =========================================================================
 conv1x1_core u_pw_core (
 .clk (clk),
 .rst (rst),
 .en (shared_en_pw),
 .acc_clr (shared_ac_pw),
 .d0 (pw_data_in_int[ 0*G2_FM_W +: G2_FM_W]),
 .d1 (pw_data_in_int[ 1*G2_FM_W +: G2_FM_W]),
 .d2 (pw_data_in_int[ 2*G2_FM_W +: G2_FM_W]),
 .d3 (pw_data_in_int[ 3*G2_FM_W +: G2_FM_W]),
 .d4 (pw_data_in_int[ 4*G2_FM_W +: G2_FM_W]),
 .d5 (pw_data_in_int[ 5*G2_FM_W +: G2_FM_W]),
 .d6 (pw_data_in_int[ 6*G2_FM_W +: G2_FM_W]),
 .d7 (pw_data_in_int[ 7*G2_FM_W +: G2_FM_W]),
 .d8 (pw_data_in_int[ 8*G2_FM_W +: G2_FM_W]),
 .d9 (pw_data_in_int[ 9*G2_FM_W +: G2_FM_W]),
 .d10(pw_data_in_int[10*G2_FM_W +: G2_FM_W]),
 .d11(pw_data_in_int[11*G2_FM_W +: G2_FM_W]),
 .weights_flat(pw_weights_rom_out),
 .biases_flat (pw_biases_rom_out),
 .results_flat(pw_results_flat)
 );

endmodule

`default_nettype wire
// =============================================================================
// END group2_top.v
// =============================================================================
