// =============================================================================
// accelerator_top.v -- ShuffleNet V2 Accelerator Top-level Integration (Module 4.2)
// -----------------------------------------------------------------------------
// "Accelerator Controller" / Figures 5.69, 5.72
//
// Integrates all three group modules, the accelerator controller, and Extra
// memory (Group 2 -> Group 3 feature-map buffer):
// accelerator_ctrl -- 5-state FSM orchestrating pipelined group execution
// group1_top -- Group 1: 3x3 conv + maxpool
// group2_top -- Group 2: DW 3x3 + 1x1 PW (16 Shuffle blocks)
// extra_mem -- 29 x 1024 x 12-bit BRAM: G2 PW output -> G3 entry
// group3_top -- Group 3: 1x1 conv + avg pool + FC + classification
//
// PIPELINED DATA FLOW ( / Fig 5.69):
// Image source
// --> photo memory (in group1_top, ping-pong)
// --> Group 1 (3x3 conv + maxpool)
// --> maxpool memory (in group1_top, read by Group 2)
// --> Group 2 (Shuffle units)
// --> Extra memory (internal, 29 ch x 1024 words)
// --> Group 3 (FC + classification) --> class_idx output
//
// EXTRA MEMORY ADDRESS ENCODING:
// Written by G2 with addr = pw_wr_addr * N_ACC_PLUS1 + loop
// = pw_wr_addr * 17 + loop (N_ACC_PLUS1 = G3_N_ACC+1 = 17)
// Positions px*17+16 (step-16 slots) are never written -> zero-initialized.
// These zero slots automatically flush the G3 conv1x1 MAC pipeline between
// pixels, so that Group 3 only needs acc_clr=1 for one settling cycle.
// Read by G3 sequentially via extramem_rd_addr[9:0]; group3_ctrl resets
// extramem_rd_addr=0 at each filter-group boundary.
//
// EXTERNAL PORTS:
// Photo memory write port (from AXI slave / board wrapper):
// pm_addr_wr, pm_data_in, pm_we, pm_mem_select
// Control handshake:
// photo_ready -- image source signals new image is ready
// busy -- accelerator back-pressure to image source
// Classification output:
// class_idx[9:0], classification_done
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module accelerator_top (
    input  wire clk,
    input  wire rst,

    // ---- Handshake with image source ----
    input  wire photo_ready,   // new image ready to process
    output wire busy,          // back-pressure: high while G1/G2 active

    // ---- Photo memory write port (from image source / DMA) ----
    input  wire [`PHOTO_MEM_AW-1:0] pm_addr_wr,
    input  wire [`DATA_W-1:0]       pm_data_in,
    input  wire [2:0]               pm_we,
    input  wire                     pm_mem_select,

    // ---- Classification output ----
    output wire [9:0]  class_idx,
    output wire        classification_done  // = group3_done
);

    // =========================================================================
    // Local parameters
    // =========================================================================
    localparam integer G1_FM_W  = `G1_FM_W;          // 10 (Ch 6.2.8)
    localparam integer G1_OUT_C = `G1_OUT_C;          // 24
    localparam integer G2_PAR_F = `G2_DW_PAR_FILT;   // 58
    localparam integer G2_FM_W  = `G2_FM_W;           // 12
    localparam integer G3_CH    = `G3_PW_PAR_CHAN;    // 29

    // N_ACC_PLUS1 for extra_mem write address: G3_N_ACC=16, so N_ACC_PLUS1=17
    localparam integer EM_STRIDE = 17;

    // =========================================================================
    // 1. Accelerator Controller
    // =========================================================================
    wire group1_start_w, group2_start_w, group3_start_w;
    wire group1_done_w,  group2_done_w,  group3_done_w;
    wire ping_pong_sel_w;
    wire [2:0] ctrl_fsm_state;

    accelerator_ctrl u_ctrl (
        .clk         (clk),
        .rst         (rst),
        .photo_ready (photo_ready),
        .busy        (busy),
        .group1_start(group1_start_w),
        .group2_start(group2_start_w),
        .group3_start(group3_start_w),
        .group1_done (group1_done_w),
        .group2_done (group2_done_w),
        .group3_done (group3_done_w),
        .ping_pong_sel(ping_pong_sel_w),
        .fsm_state   (ctrl_fsm_state)
    );

    // =========================================================================
    // 2. Group 1 Top
    // =========================================================================
    wire [`MAXPOOL_MEM_AW-1:0]          mp_addr_rd_w;
    wire [G1_OUT_C*G1_FM_W-1:0]         mp_data_out_w;

    group1_top u_g1 (
        .clk          (clk),
        .rst          (rst),
        .pm_addr_wr   (pm_addr_wr),
        .pm_data_in   (pm_data_in),
        .pm_we        (pm_we),
        .pm_mem_select(pm_mem_select),
        .mp_addr_rd   (mp_addr_rd_w),
        .mp_data_out  (mp_data_out_w),
        .start        (group1_start_w),
        .done         (group1_done_w)
    );

    // =========================================================================
    // 3. Group 2 Top
    // fm_data_in: zero-pad G1 24-channel output to 58 ch for G2 fm_data_in.
    // =========================================================================
    wire [11:0]                   g2_fm_rd_addr_w;
    wire [G2_PAR_F*G2_FM_W-1:0]  g2_pw_results_w;
    wire [11:0]                   g2_pw_wr_addr_w;
    wire                          g2_pw_we_w;
    wire [4:0]                    g2_loops_w;
    wire [1:0]                    g2_fsm_state_w;

    assign mp_addr_rd_w = g2_fm_rd_addr_w[`MAXPOOL_MEM_AW-1:0];

    wire [G2_PAR_F*G1_FM_W-1:0] g2_fm_data_in_w;
    assign g2_fm_data_in_w[G1_OUT_C*G1_FM_W-1:0]           = mp_data_out_w;
    assign g2_fm_data_in_w[G2_PAR_F*G1_FM_W-1:G1_OUT_C*G1_FM_W] =
               {((G2_PAR_F-G1_OUT_C)*G1_FM_W){1'b0}};

    group2_top u_g2 (
        .clk            (clk),
        .rst            (rst),
        .start_group    (group2_start_w),
        .group2_done    (group2_done_w),
        .fm_data_in     (g2_fm_data_in_w),
        .fm_rd_addr     (g2_fm_rd_addr_w),
        .pw_results_flat(g2_pw_results_w),
        .pw_wr_addr     (g2_pw_wr_addr_w),
        .pw_we          (g2_pw_we_w),
        .loops          (g2_loops_w),
        .fsm_state      (g2_fsm_state_w)
    );

    // =========================================================================
    // 3.5 Extra Memory (Group 2 PW output -> Group 3 conv5 input)
    //
    // Write address: pixel * EM_STRIDE + loop
    // EM_STRIDE = 17 = G3_N_ACC + 1
    // pixel = g2_pw_wr_addr_w[5:0] (0..48, lower 6 bits of 12-bit pw addr)
    // loop = g2_loops_w[3:0] (0..15)
    // max addr = 48*17 + 15 = 831 < 1024 = 2^10
    //
    // The unused "step-16" positions (px*17+16) stay zero-initialized and
    // serve as MAC pipeline flush tokens for Group 3's accumulator.
    //
    // Write data: first G3_CH=29 channels of the 58-channel PW result.
    // Read address: extramem_rd_addr[9:0] from group3_ctrl (sequential, resets
    // at each filter-group boundary).
    // =========================================================================
    wire [9:0] em_wr_addr;
    // px*17 = px*16 + px = (px<<4) + px; then + loop
    assign em_wr_addr = ({4'b0, g2_pw_wr_addr_w[5:0]} << 4) +
                         {4'b0, g2_pw_wr_addr_w[5:0]} +
                         {6'b0, g2_loops_w[3:0]};

    wire [13:0] g3_extramem_rd_addr_w;
    wire [G3_CH*G2_FM_W-1:0] em_rd_data_w;

    extra_mem u_extra_mem (
        .clk    (clk),
        .wr_addr(em_wr_addr),
        .wr_data(g2_pw_results_w[G3_CH*G2_FM_W-1:0]),  // lower 29 channels
        .wr_we  (g2_pw_we_w),
        .rd_addr(g3_extramem_rd_addr_w[9:0]),
        .rd_data(em_rd_data_w)
    );

    // =========================================================================
    // 4. Group 3 Top
    // =========================================================================
    wire [13:0] g3_dbg_addr_w;
    wire        g3_dbg_en_w;

    group3_top u_g3 (
        .clk              (clk),
        .rst              (rst),
        .start_group      (group3_start_w),
        .group3_done      (group3_done_w),
        .extramem_rd_addr (g3_extramem_rd_addr_w),
        .extramem_data_in (em_rd_data_w),
        .class_idx        (class_idx),
        .dbg_extramem_addr(g3_dbg_addr_w),
        .dbg_conv1x1_en   (g3_dbg_en_w)
    );

    assign classification_done = group3_done_w;

endmodule

`default_nettype wire
// =============================================================================
// END accelerator_top.v
// =============================================================================
