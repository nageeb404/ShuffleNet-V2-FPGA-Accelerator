// =============================================================================
// group3_top.v -- Group 3 Top-level Structural Integration (Module 3.5)
// -----------------------------------------------------------------------------
// "Group 3 Design" / Figure 5.56
//
// Integrates all Group 3 modules:
// Module 3.1: conv1x1_g3_core -- 16-parallel 1x1 conv (N_ACC=16, N_CHAN=29)
// Module 3.2: avg_pool_core -- 16-channel global average pooling (7x7)
// Module 3.3: fc_core -- FC layer (32 channels parallel, 1000 classes)
// Module 3.4: group3_ctrl -- 10-counter orchestrator
//
// Ch 6.2.5 + 6.2.8: per-layer widths applied throughout.
// extramem_data_in : G2_FM_W = 12 bits (Group 2 feature map output)
// PW weights : G3_PW_WW = 9 bits
// PW biases : DATA_W = 15 bits (original format)
// conv1x1 output : G3_CONV_OUT_W = 27 bits (full-precision, no quantizer)
// avgpool output : G3_FM_W = 9 bits
// register file : G3_FM_W = 9 bits per entry
// FC weights : FC_WW = 9 bits
// FC biases : FC_BIAS_W = 11 bits
// fc_result : G3_FM_W = 9 bits
//
// DATA FLOW ( / Fig 5.55):
// Extra memory (464-ch x 7x7)
// -> 1x1 conv (16 out-channels at a time, 64 groups to cover 1024 output ch)
// -> avg pool (accumulate 49 pixels per channel, output 1 value)
// -> register file (1024 values after all 64 groups complete)
// Register file (1024 channels)
// -> FC core (32 channels at a time, 1000 classes sequentially)
// -> Classification unit (running max)
// -> class_idx output
//
// REGISTER FILE:
// 1024 registers holding avgpool results, indexed by filter group and channel.
// Implemented as a simple register array. Loaded via regfile_shift pulses
// from group3_ctrl (one shift per filter-group completion).
// Read using regfile_sel_ch to select the current 32-channel group for FC.
//
// EXTERNAL PORTS (memories not yet implemented -- exposed as ports):
// extramem_rd_addr -- from group3_ctrl (addr for Extra memory read)
// extramem_data_in -- 29 channels from Extra memory (to 1x1 conv)
// pw_weights_flat -- 1x1 conv filter weights (16 filters x 29 channels)
// pw_biases_flat -- 1x1 conv biases (16 values)
// fc_weights_rom_out -- FC layer weights (32 channels, one class per cycle)
// fc_bias_in -- FC bias for current class
// class_idx -- output: index of winning class (0..999)
// group3_done -- to Accelerator controller
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module group3_top (
    input  wire clk,
    input  wire rst,

    // ---- Group control ----
    input  wire start_group,
    output wire group3_done,

    // ---- Extra memory interface ----
    output wire [13:0] extramem_rd_addr,
    // 29 input channels from Extra memory (current pixel, current filter group)
    // Ch 6.2.8: each channel is G2_FM_W=12 bits (was DATA_W=15)
    input  wire [`G3_PW_PAR_CHAN*`G2_FM_W-1:0] extramem_data_in,

    // ---- Classification output ----
    output reg  [9:0]  class_idx,   // winning class index

    // ---- Status ----
    output wire [13:0] dbg_extramem_addr,
    output wire        dbg_conv1x1_en
);

    // =========================================================================
    // Localparams
    // =========================================================================
    localparam integer DATA_W        = `DATA_W;           // 15 (bias format)
    localparam integer G2_FM_W       = `G2_FM_W;          // 12 (1x1 input)
    localparam integer G3_PW_WW      = `G3_PW_WW;         // 9 (1x1 weight)
    localparam integer G3_FM_W       = `G3_FM_W;          // 9 (avgpool/FC output)
    localparam integer FC_WW         = `FC_WW;             // 9 (FC weight)
    localparam integer FC_BIAS_W     = `FC_BIAS_W;        // 11 (FC bias)
    localparam integer N_CHAN_1X1    = `G3_PW_PAR_CHAN;   // 29
    localparam integer N_FILT_1X1   = `G3_PW_PAR_FILT;   // 16
    localparam integer N_FC_PAR     = `G3_FC_PAR_CHAN;    // 32
    localparam integer FC_IN        = `G3_FC_IN;          // 1024
    localparam integer FC_OUT       = `G3_FC_OUT;         // 1000
    localparam integer REGFILE_D    = FC_IN;              // 1024 registers
    // Ch 6.2.7+6.2.5+6.2.8: conv1x1_g3 outputs 27-bit full-precision values
    localparam integer CONV1X1_OUT_W = `G3_CONV_OUT_W;   // 27

    // =========================================================================
    // 1. group3_ctrl -- 10-counter orchestrator
    // =========================================================================
    wire        conv1x1_en, conv1x1_acc_clr;
    wire [9:0]  conv1x1_step_out;
    wire        avgpool_acc_en, avgpool_acc_clr, avgpool_result_we;
    wire        regfile_shift;
    wire        fc_en, fc_acc_clr;
    wire [14:0] fc_acc_addr;
    wire [9:0]  fc_bias_addr;
    wire        class_we_ctrl, max_update;
    wire [9:0]  class_idx_ctrl;
    wire [9:0]  regfile_sel_ch;

    group3_ctrl u_ctrl (
        .clk              (clk),
        .rst              (rst),
        .start_group      (start_group),
        .conv1x1_en       (conv1x1_en),
        .conv1x1_acc_clr  (conv1x1_acc_clr),
        .conv1x1_step_out (conv1x1_step_out),
        .avgpool_acc_en   (avgpool_acc_en),
        .avgpool_acc_clr  (avgpool_acc_clr),
        .avgpool_result_we(avgpool_result_we),
        .regfile_shift    (regfile_shift),
        .fc_en            (fc_en),
        .fc_acc_clr       (fc_acc_clr),
        .fc_acc_addr      (fc_acc_addr),
        .fc_bias_addr     (fc_bias_addr),
        .class_we         (class_we_ctrl),
        .max_update       (max_update),
        .class_idx        (class_idx_ctrl),
        .extramem_rd_addr (extramem_rd_addr),
        .regfile_sel_ch   (regfile_sel_ch),
        .group3_done      (group3_done)
    );

    assign dbg_extramem_addr = extramem_rd_addr;
    assign dbg_conv1x1_en    = conv1x1_en;

    // =========================================================================
    // 2. Weight / bias ROMs (G3 PW and FC, all internal -- no external weight ports)
    // =========================================================================
    wire [4175:0] pw_weights_rom_out;
    wire [239:0]  pw_biases_rom_out;
    wire [287:0]  fc_weights_rom_out;
    wire [10:0]   fc_bias_rom_out;

    g3_pw_weight_rom u_g3pw_w_rom (
        .clk     (clk),
        .addr    (conv1x1_step_out),
        .data_out(pw_weights_rom_out)
    );

    g3_pw_bias_rom u_g3pw_b_rom (
        .addr    (conv1x1_step_out[9:4]),
        .data_out(pw_biases_rom_out)
    );

    g3_fc_weight_rom u_fc_w_rom (
        .clk     (clk),
        .addr    (fc_acc_addr),
        .data_out(fc_weights_rom_out)
    );

    g3_fc_bias_rom u_fc_b_rom (
        .addr    (fc_bias_addr),
        .data_out(fc_bias_rom_out)
    );

    // =========================================================================
    // 3. conv1x1_g3_core -- 16-parallel 1x1 conv
    // Input: 29 channels from Extra memory (shared across all 16 filters)
    // Ch 6.2.7: results are full-precision (no output quantizer)
    // Ch 6.2.5+6.2.8: IN_W=G2_FM_W=12, W_W=G3_PW_WW=9, OUT_W=G3_CONV_OUT_W=27
    // =========================================================================
    wire [N_FILT_1X1*CONV1X1_OUT_W-1:0] conv1x1_results;

    conv1x1_g3_core #(
        .N_FILT     (N_FILT_1X1),
        .N_CHAN     (N_CHAN_1X1),
        .IN_W       (G2_FM_W),
        .W_W        (G3_PW_WW),
        .BIAS_WD    (DATA_W),
        .BIAS_OUT_W (CONV1X1_OUT_W)
    ) u_conv1x1 (
        .clk(clk), .rst(rst),
        .en(conv1x1_en), .acc_clr(conv1x1_acc_clr),
        .d0 (extramem_data_in[ 0*G2_FM_W +: G2_FM_W]),
        .d1 (extramem_data_in[ 1*G2_FM_W +: G2_FM_W]),
        .d2 (extramem_data_in[ 2*G2_FM_W +: G2_FM_W]),
        .d3 (extramem_data_in[ 3*G2_FM_W +: G2_FM_W]),
        .d4 (extramem_data_in[ 4*G2_FM_W +: G2_FM_W]),
        .d5 (extramem_data_in[ 5*G2_FM_W +: G2_FM_W]),
        .d6 (extramem_data_in[ 6*G2_FM_W +: G2_FM_W]),
        .d7 (extramem_data_in[ 7*G2_FM_W +: G2_FM_W]),
        .d8 (extramem_data_in[ 8*G2_FM_W +: G2_FM_W]),
        .d9 (extramem_data_in[ 9*G2_FM_W +: G2_FM_W]),
        .d10(extramem_data_in[10*G2_FM_W +: G2_FM_W]),
        .d11(extramem_data_in[11*G2_FM_W +: G2_FM_W]),
        .d12(extramem_data_in[12*G2_FM_W +: G2_FM_W]),
        .d13(extramem_data_in[13*G2_FM_W +: G2_FM_W]),
        .d14(extramem_data_in[14*G2_FM_W +: G2_FM_W]),
        .d15(extramem_data_in[15*G2_FM_W +: G2_FM_W]),
        .d16(extramem_data_in[16*G2_FM_W +: G2_FM_W]),
        .d17(extramem_data_in[17*G2_FM_W +: G2_FM_W]),
        .d18(extramem_data_in[18*G2_FM_W +: G2_FM_W]),
        .d19(extramem_data_in[19*G2_FM_W +: G2_FM_W]),
        .d20(extramem_data_in[20*G2_FM_W +: G2_FM_W]),
        .d21(extramem_data_in[21*G2_FM_W +: G2_FM_W]),
        .d22(extramem_data_in[22*G2_FM_W +: G2_FM_W]),
        .d23(extramem_data_in[23*G2_FM_W +: G2_FM_W]),
        .d24(extramem_data_in[24*G2_FM_W +: G2_FM_W]),
        .d25(extramem_data_in[25*G2_FM_W +: G2_FM_W]),
        .d26(extramem_data_in[26*G2_FM_W +: G2_FM_W]),
        .d27(extramem_data_in[27*G2_FM_W +: G2_FM_W]),
        .d28(extramem_data_in[28*G2_FM_W +: G2_FM_W]),
        .weights_flat(pw_weights_rom_out),
        .biases_flat (pw_biases_rom_out),
        .results_flat(conv1x1_results)
    );

    // =========================================================================
    // 3. avg_pool_core -- 16-channel global average pooling
    // Input: conv1x1_results (27-bit per channel, Ch 6.2.7+6.2.5)
    // Ch 6.2.3: sum only + quantizer at end (no divide by 49)
    // Ch 6.2.8: DATA_W=G3_FM_W=9 (output width)
    // =========================================================================
    wire [N_FILT_1X1*G3_FM_W-1:0] avgpool_results;

    avg_pool_core #(
        .N_CHAN (N_FILT_1X1),
        .IN_W   (CONV1X1_OUT_W),
        .DATA_W (G3_FM_W)
    ) u_avgpool (
        .clk        (clk),
        .rst        (rst),
        .acc_en     (avgpool_acc_en),
        .acc_clr    (avgpool_acc_clr),
        .result_we  (avgpool_result_we),
        .data_in_flat(conv1x1_results),
        .results_flat(avgpool_results)
    );

    // =========================================================================
    // 4. Register file -- 1024 x G3_FM_W registers, shifted in from avgpool
    // Ch 6.2.8: G3_FM_W=9 bits per register (was DATA_W=15 bits)
    // Written 16 at a time (one filter group), shift-loaded.
    // Read: 32 channels at a time via regfile_sel_ch (0..31 selects group).
    //
    // Organization: 64 filter groups x 16 channels each = 1024 total.
    // regfile_shift loads the avgpool_results into the NEXT 16 slots.
    // regfile_sel_ch selects which group of 32 channels to present to FC.
    // =========================================================================
    (* ram_style = "registers" *) reg signed [G3_FM_W-1:0] regfile [0:REGFILE_D-1];
    reg [9:0] regfile_wr_ptr;  // points to next write slot (0..63)

    integer ri;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            regfile_wr_ptr <= 10'd0;
            for (ri = 0; ri < REGFILE_D; ri = ri + 1)
                regfile[ri] <= {G3_FM_W{1'b0}};
        end else if (regfile_shift) begin
            // Write 16 avgpool results into next slot
            regfile[regfile_wr_ptr*N_FILT_1X1 + 0]  <= avgpool_results[ 0*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 1]  <= avgpool_results[ 1*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 2]  <= avgpool_results[ 2*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 3]  <= avgpool_results[ 3*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 4]  <= avgpool_results[ 4*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 5]  <= avgpool_results[ 5*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 6]  <= avgpool_results[ 6*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 7]  <= avgpool_results[ 7*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 8]  <= avgpool_results[ 8*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 9]  <= avgpool_results[ 9*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 10] <= avgpool_results[10*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 11] <= avgpool_results[11*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 12] <= avgpool_results[12*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 13] <= avgpool_results[13*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 14] <= avgpool_results[14*G3_FM_W +: G3_FM_W];
            regfile[regfile_wr_ptr*N_FILT_1X1 + 15] <= avgpool_results[15*G3_FM_W +: G3_FM_W];
            if (regfile_wr_ptr < 63)
                regfile_wr_ptr <= regfile_wr_ptr + 10'd1;
            else
                regfile_wr_ptr <= 10'd0;
        end
    end

    // Read 32 channels at a time for FC (regfile_sel_ch selects the group)
    // sel_ch 0: regfile[0..31], sel_ch 1: regfile[32..63], ... (groups of 32)
    wire signed [G3_FM_W-1:0] fc_d0  = regfile[regfile_sel_ch*N_FC_PAR +  0];
    wire signed [G3_FM_W-1:0] fc_d1  = regfile[regfile_sel_ch*N_FC_PAR +  1];
    wire signed [G3_FM_W-1:0] fc_d2  = regfile[regfile_sel_ch*N_FC_PAR +  2];
    wire signed [G3_FM_W-1:0] fc_d3  = regfile[regfile_sel_ch*N_FC_PAR +  3];
    wire signed [G3_FM_W-1:0] fc_d4  = regfile[regfile_sel_ch*N_FC_PAR +  4];
    wire signed [G3_FM_W-1:0] fc_d5  = regfile[regfile_sel_ch*N_FC_PAR +  5];
    wire signed [G3_FM_W-1:0] fc_d6  = regfile[regfile_sel_ch*N_FC_PAR +  6];
    wire signed [G3_FM_W-1:0] fc_d7  = regfile[regfile_sel_ch*N_FC_PAR +  7];
    wire signed [G3_FM_W-1:0] fc_d8  = regfile[regfile_sel_ch*N_FC_PAR +  8];
    wire signed [G3_FM_W-1:0] fc_d9  = regfile[regfile_sel_ch*N_FC_PAR +  9];
    wire signed [G3_FM_W-1:0] fc_d10 = regfile[regfile_sel_ch*N_FC_PAR + 10];
    wire signed [G3_FM_W-1:0] fc_d11 = regfile[regfile_sel_ch*N_FC_PAR + 11];
    wire signed [G3_FM_W-1:0] fc_d12 = regfile[regfile_sel_ch*N_FC_PAR + 12];
    wire signed [G3_FM_W-1:0] fc_d13 = regfile[regfile_sel_ch*N_FC_PAR + 13];
    wire signed [G3_FM_W-1:0] fc_d14 = regfile[regfile_sel_ch*N_FC_PAR + 14];
    wire signed [G3_FM_W-1:0] fc_d15 = regfile[regfile_sel_ch*N_FC_PAR + 15];
    wire signed [G3_FM_W-1:0] fc_d16 = regfile[regfile_sel_ch*N_FC_PAR + 16];
    wire signed [G3_FM_W-1:0] fc_d17 = regfile[regfile_sel_ch*N_FC_PAR + 17];
    wire signed [G3_FM_W-1:0] fc_d18 = regfile[regfile_sel_ch*N_FC_PAR + 18];
    wire signed [G3_FM_W-1:0] fc_d19 = regfile[regfile_sel_ch*N_FC_PAR + 19];
    wire signed [G3_FM_W-1:0] fc_d20 = regfile[regfile_sel_ch*N_FC_PAR + 20];
    wire signed [G3_FM_W-1:0] fc_d21 = regfile[regfile_sel_ch*N_FC_PAR + 21];
    wire signed [G3_FM_W-1:0] fc_d22 = regfile[regfile_sel_ch*N_FC_PAR + 22];
    wire signed [G3_FM_W-1:0] fc_d23 = regfile[regfile_sel_ch*N_FC_PAR + 23];
    wire signed [G3_FM_W-1:0] fc_d24 = regfile[regfile_sel_ch*N_FC_PAR + 24];
    wire signed [G3_FM_W-1:0] fc_d25 = regfile[regfile_sel_ch*N_FC_PAR + 25];
    wire signed [G3_FM_W-1:0] fc_d26 = regfile[regfile_sel_ch*N_FC_PAR + 26];
    wire signed [G3_FM_W-1:0] fc_d27 = regfile[regfile_sel_ch*N_FC_PAR + 27];
    wire signed [G3_FM_W-1:0] fc_d28 = regfile[regfile_sel_ch*N_FC_PAR + 28];
    wire signed [G3_FM_W-1:0] fc_d29 = regfile[regfile_sel_ch*N_FC_PAR + 29];
    wire signed [G3_FM_W-1:0] fc_d30 = regfile[regfile_sel_ch*N_FC_PAR + 30];
    wire signed [G3_FM_W-1:0] fc_d31 = regfile[regfile_sel_ch*N_FC_PAR + 31];

    // =========================================================================
    // 5. fc_core -- 32-parallel-channel FC computation
    // Weights and bias come from external ROMs (fc_weights_rom_out, fc_bias_in)
    // Ch 6.2.5+6.2.8: DATA_W=G3_FM_W=9, W_W=FC_WW=9, BIAS_WD=FC_BIAS_W=11
    // =========================================================================
    wire signed [G3_FM_W-1:0] fc_result;

    fc_core #(
        .N_PAR  (N_FC_PAR),
        .DATA_W (G3_FM_W),
        .W_W    (FC_WW),
        .BIAS_WD(FC_BIAS_W)
    ) u_fc (
        .clk(clk), .rst(rst),
        .en(fc_en), .acc_clr(fc_acc_clr),
        .d0(fc_d0),   .d1(fc_d1),   .d2(fc_d2),   .d3(fc_d3),
        .d4(fc_d4),   .d5(fc_d5),   .d6(fc_d6),   .d7(fc_d7),
        .d8(fc_d8),   .d9(fc_d9),   .d10(fc_d10), .d11(fc_d11),
        .d12(fc_d12), .d13(fc_d13), .d14(fc_d14), .d15(fc_d15),
        .d16(fc_d16), .d17(fc_d17), .d18(fc_d18), .d19(fc_d19),
        .d20(fc_d20), .d21(fc_d21), .d22(fc_d22), .d23(fc_d23),
        .d24(fc_d24), .d25(fc_d25), .d26(fc_d26), .d27(fc_d27),
        .d28(fc_d28), .d29(fc_d29), .d30(fc_d30), .d31(fc_d31),
        .w0 (fc_weights_rom_out[ 0*FC_WW +: FC_WW]),
        .w1 (fc_weights_rom_out[ 1*FC_WW +: FC_WW]),
        .w2 (fc_weights_rom_out[ 2*FC_WW +: FC_WW]),
        .w3 (fc_weights_rom_out[ 3*FC_WW +: FC_WW]),
        .w4 (fc_weights_rom_out[ 4*FC_WW +: FC_WW]),
        .w5 (fc_weights_rom_out[ 5*FC_WW +: FC_WW]),
        .w6 (fc_weights_rom_out[ 6*FC_WW +: FC_WW]),
        .w7 (fc_weights_rom_out[ 7*FC_WW +: FC_WW]),
        .w8 (fc_weights_rom_out[ 8*FC_WW +: FC_WW]),
        .w9 (fc_weights_rom_out[ 9*FC_WW +: FC_WW]),
        .w10(fc_weights_rom_out[10*FC_WW +: FC_WW]),
        .w11(fc_weights_rom_out[11*FC_WW +: FC_WW]),
        .w12(fc_weights_rom_out[12*FC_WW +: FC_WW]),
        .w13(fc_weights_rom_out[13*FC_WW +: FC_WW]),
        .w14(fc_weights_rom_out[14*FC_WW +: FC_WW]),
        .w15(fc_weights_rom_out[15*FC_WW +: FC_WW]),
        .w16(fc_weights_rom_out[16*FC_WW +: FC_WW]),
        .w17(fc_weights_rom_out[17*FC_WW +: FC_WW]),
        .w18(fc_weights_rom_out[18*FC_WW +: FC_WW]),
        .w19(fc_weights_rom_out[19*FC_WW +: FC_WW]),
        .w20(fc_weights_rom_out[20*FC_WW +: FC_WW]),
        .w21(fc_weights_rom_out[21*FC_WW +: FC_WW]),
        .w22(fc_weights_rom_out[22*FC_WW +: FC_WW]),
        .w23(fc_weights_rom_out[23*FC_WW +: FC_WW]),
        .w24(fc_weights_rom_out[24*FC_WW +: FC_WW]),
        .w25(fc_weights_rom_out[25*FC_WW +: FC_WW]),
        .w26(fc_weights_rom_out[26*FC_WW +: FC_WW]),
        .w27(fc_weights_rom_out[27*FC_WW +: FC_WW]),
        .w28(fc_weights_rom_out[28*FC_WW +: FC_WW]),
        .w29(fc_weights_rom_out[29*FC_WW +: FC_WW]),
        .w30(fc_weights_rom_out[30*FC_WW +: FC_WW]),
        .w31(fc_weights_rom_out[31*FC_WW +: FC_WW]),
        .bias  (fc_bias_rom_out),
        .result(fc_result)
    );

    // =========================================================================
    // 6. Classification: running max tracker
    // class_we: latch fc_result; max_update: compare and keep if larger
    // Ch 6.2.8: max_score / fc_result_latched are G3_FM_W=9 bits
    // =========================================================================
    reg signed [G3_FM_W-1:0] max_score;
    reg signed [G3_FM_W-1:0] fc_result_latched;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            max_score        <= {1'b1, {(G3_FM_W-1){1'b0}}};  // most negative
            fc_result_latched<= {G3_FM_W{1'b0}};
            class_idx        <= 10'd0;
        end else begin
            if (class_we_ctrl)
                fc_result_latched <= fc_result;
            if (max_update) begin
                if ($signed(fc_result) > $signed(max_score)) begin
                    max_score <= fc_result;
                    class_idx <= class_idx_ctrl;
                end
            end
        end
    end

endmodule

`default_nettype wire
// =============================================================================
// END group3_top.v
// =============================================================================
