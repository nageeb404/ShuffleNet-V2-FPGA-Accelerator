// =============================================================================
// group1_top.v -- Group 1 Top-level Integration (Module 1.13)
// -----------------------------------------------------------------------------
// Integrates all Group 1 modules:
// Module 1.10: photo_mem -- ping-pong input image BRAM (3 ch)
// Module 1.7 : fifo_ctrl x2 -- FIFO controllers (conv + pool)
// Module 1.5 : fifo_3x3 x3 -- shift-register FIFOs per input channel
// Module 1.3b: conv3x3_core -- 24-filter 3x3 convolution + ReLU
// Module 1.8 : weights_rom_3x3 -- LUT weight ROM (3 kernel columns)
// Module 1.9 : bias_rom_3x3 -- LUT bias ROM (24 biases)
// Module 1.12: group1_ctrl -- col_cnt counter + signal generation
// Module 1.6 : fifo_pool x72 -- maxpool shift-reg FIFOs
// (3 per output channel: col offsets 0,1,2)
// Module 1.4 : maxpool_core -- 24-ch x 9-win max-of-9
// Module 1.11: maxpool_mem -- 24-channel output BRAM
// POOL FIFO STRUCTURE (9 taps per channel for maxpool 3x3 window):
// Each of 24 output channels has 3 fifo_pool instances:
// - fifo_pool_c0: data from conv output at current cycle (column 0)
// - fifo_pool_c1: data from conv output delayed 1 cycle (column 1)
// - fifo_pool_c2: data from conv output delayed 2 cycles (column 2)
// Each fifo_pool provides 3 row taps -> 3 fifo_pool x 3 taps = 9 taps/ch
// Taps packed into maxpool_core.data_flat[(c*9+t)*DW +: DW]:
// t=0,1,2: col0 tap0,1,2 ; t=3,4,5: col1 tap0,1,2 ; t=6,7,8: col2 tap0,1,2
// Ch 6.2.5 + 6.2.8: per-layer widths applied throughout.
// Photo pixels : 8 bits (PHOTO_W)
// Conv weights : 12 bits (G1_CONV_WW)
// Conv/maxpool output: 10 bits (G1_FM_W)
// Biases : 15 bits (DATA_W, original format)
// EXTERNAL PORTS:
// Photo memory write (from external image loader):
// pm_addr_wr, pm_data_in, pm_we, pm_mem_select
// Maxpool memory read (to Group 2):
// mp_addr_rd, mp_data_out [G1_OUT_C*G1_FM_W-1:0]
// Control:
// start -> asserts start_fifo to both FIFO controllers
// done <- from conv FIFO controller (all rows processed)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module group1_top (
 input wire clk,
 input wire rst,

 // Photo memory write interface (external image loader / accelerator ctrl)
 input wire [`PHOTO_MEM_AW-1:0] pm_addr_wr,
 input wire [`DATA_W-1:0] pm_data_in,
 input wire [2:0] pm_we,
 input wire pm_mem_select,

 // Maxpool memory read interface (Group 2)
 // Ch 6.2.8: output width is G1_OUT_C*G1_FM_W (was G1_OUT_C*DATA_W)
 input wire [`MAXPOOL_MEM_AW-1:0] mp_addr_rd,
 output wire [`G1_OUT_C*`G1_FM_W-1:0] mp_data_out,

 // Control
 input wire start, // begin Group 1 processing
 output wire done // all rows complete (from conv FIFO ctrl)
);

 // =========================================================================
 // Localparams
 // =========================================================================
 localparam integer DATA_W = `DATA_W; // 15 (bias format)
 localparam integer PHOTO_W = `PHOTO_W; // 8 (Ch 6.2.8)
 localparam integer G1_CONV_WW = `G1_CONV_WW; // 12 (Ch 6.2.5)
 localparam integer G1_FM_W = `G1_FM_W; // 10 (Ch 6.2.8)
 localparam integer N_FILT = `G1_CONV_PAR_FILT; // 24
 localparam integer PHOTO_AW = `PHOTO_MEM_AW; // 16
 localparam integer POOL_AW = `MAXPOOL_MEM_AW; // 12
 localparam integer FLAT_CONV = N_FILT * 9 * G1_CONV_WW; // 2592 weight bus
 localparam integer FLAT_BIAS = N_FILT * DATA_W; // 360 bias bus (15-bit)
 localparam integer FLAT_RES = N_FILT * G1_FM_W; // 240 result bus (10-bit)
 localparam integer FLAT_POOL = N_FILT * 9 * G1_FM_W; // 2160 pool data bus

 // =========================================================================
 // 1. photo_mem -- ping-pong input image memory
 // =========================================================================
 wire [PHOTO_W-1:0] photo_ch1, photo_ch2, photo_ch3;

 photo_mem u_photo (
 .clk (clk),
 .rst (rst),
 .addr_wr (pm_addr_wr),
 .data_in (pm_data_in),
 .we (pm_we),
 .addr_rd (conv_rd_addr), // driven by conv fifo_ctrl
 .mem_select (pm_mem_select),
 .data_out_ch1(photo_ch1),
 .data_out_ch2(photo_ch2),
 .data_out_ch3(photo_ch3)
 );

 // =========================================================================
 // 2. group1_ctrl -- col_cnt counter + signal routing
 // =========================================================================
 wire ctrl_start_fifo;
 wire ctrl_en;
 wire ctrl_acc_clr;
 wire [1:0] ctrl_addr;
 wire ctrl_conv_valid;
 wire [1:0] conv_fsm_state;

 group1_ctrl u_ctrl (
 .clk (clk),
 .rst (rst),
 .start (start),
 .fsm_state (conv_fsm_state),
 .en (ctrl_en),
 .acc_clr (ctrl_acc_clr),
 .addr (ctrl_addr),
 .start_fifo (ctrl_start_fifo),
 .conv_valid (ctrl_conv_valid)
 );

 // =========================================================================
 // 3. fifo_ctrl (conv) -- controls 3x3 conv FIFOs and photo_mem reads
 // =========================================================================
 wire [`PHOTO_MEM_AW-1:0] conv_rd_addr;
 wire conv_shift_and_load;
 wire conv_padding_sel;

 fifo_ctrl u_fifo_ctrl_conv (
 .clk (clk),
 .rst (rst),
 .start (ctrl_start_fifo),
 .shift_and_load(conv_shift_and_load),
 .padding_sel (conv_padding_sel),
 .rd_addr (conv_rd_addr),
 .fsm_state (conv_fsm_state),
 .done (done)
 );

 // =========================================================================
 // 4. fifo_3x3 x3 -- shift-register FIFOs for 3 input channels
 // Ch 6.2.8: DATA_W=PHOTO_W (8 bits) -- photo pixels are 8-bit
 // =========================================================================
 wire signed [PHOTO_W-1:0] tap_ch0_r0, tap_ch0_r1, tap_ch0_r2;
 wire signed [PHOTO_W-1:0] tap_ch1_r0, tap_ch1_r1, tap_ch1_r2;
 wire signed [PHOTO_W-1:0] tap_ch2_r0, tap_ch2_r1, tap_ch2_r2;

 fifo_3x3 #(.DATA_W(PHOTO_W)) u_fifo_ch0 (
 .clk (clk), .rst(rst),
 .shift_and_load(conv_shift_and_load),
 .padding_sel (conv_padding_sel),
 .data_in (photo_ch1),
 .tap0(tap_ch0_r0), .tap1(tap_ch0_r1), .tap2(tap_ch0_r2)
 );

 fifo_3x3 #(.DATA_W(PHOTO_W)) u_fifo_ch1 (
 .clk (clk), .rst(rst),
 .shift_and_load(conv_shift_and_load),
 .padding_sel (conv_padding_sel),
 .data_in (photo_ch2),
 .tap0(tap_ch1_r0), .tap1(tap_ch1_r1), .tap2(tap_ch1_r2)
 );

 fifo_3x3 #(.DATA_W(PHOTO_W)) u_fifo_ch2 (
 .clk (clk), .rst(rst),
 .shift_and_load(conv_shift_and_load),
 .padding_sel (conv_padding_sel),
 .data_in (photo_ch3),
 .tap0(tap_ch2_r0), .tap1(tap_ch2_r1), .tap2(tap_ch2_r2)
 );

 // =========================================================================
 // 5. weights_rom_3x3 + bias_rom_3x3 -- filter memories
 // =========================================================================
 wire [FLAT_CONV-1:0] weights_flat;
 wire [FLAT_BIAS-1:0] biases_flat;

 weights_rom_3x3 u_weights (
 .addr (ctrl_addr),
 .weights_flat(weights_flat)
 );

 bias_rom_3x3 u_biases (
 .biases_flat(biases_flat)
 );

 // =========================================================================
 // 6. conv3x3_core -- 24-parallel-filter computation
 // =========================================================================
 wire [FLAT_RES-1:0] conv_results;

 conv3x3_core u_conv (
 .clk (clk),
 .rst (rst),
 .en (ctrl_en),
 .acc_clr (ctrl_acc_clr),
 // 9 shared data inputs: 3 channels x 3 row taps (PHOTO_W bits each)
 .d0(tap_ch0_r0), .d1(tap_ch0_r1), .d2(tap_ch0_r2),
 .d3(tap_ch1_r0), .d4(tap_ch1_r1), .d5(tap_ch1_r2),
 .d6(tap_ch2_r0), .d7(tap_ch2_r1), .d8(tap_ch2_r2),
 .weights_flat(weights_flat),
 .biases_flat (biases_flat),
 .results_flat(conv_results)
 );

 // =========================================================================
 // 7. Pool FIFO column-delay registers (for 3x3 maxpool window columns)
 // conv_results is valid when ctrl_conv_valid=1.
 // Shift into pool FIFOs on each ctrl_conv_valid pulse.
 // =========================================================================
 reg [FLAT_RES-1:0] conv_results_d1, conv_results_d2;

 always @(posedge clk or posedge rst) begin
 if (rst) begin
 conv_results_d1 <= {FLAT_RES{1'b0}};
 conv_results_d2 <= {FLAT_RES{1'b0}};
 end else if (ctrl_conv_valid) begin
 conv_results_d1 <= conv_results;
 conv_results_d2 <= conv_results_d1;
 end
 end

 // pool_shift = shift pool FIFOs when conv produces a new output pixel
 wire pool_shift = ctrl_conv_valid;

 // =========================================================================
 // 8. Pool FIFO controller (for maxpool FIFOs --)
 // Manages the pool FIFO shift timing and produces en for maxpool_core.
 // Uses same fifo_ctrl with maxpool output dimensions (112x112, stride=2).
 // =========================================================================
 wire [1:0] pool_fsm_state;
 wire pool_shift_and_load, pool_padding_sel;
 wire [`PHOTO_MEM_AW-1:0] pool_rd_addr_unused; // pool FIFOs fed from conv, not mem

 fifo_ctrl #(
 .IMG_W (`G1_CONV_OUT_W), // 112
 .IMG_H (`G1_CONV_OUT_H) // 112
 ) u_fifo_ctrl_pool (
 .clk (clk),
 .rst (rst),
 .start (ctrl_start_fifo),
 .shift_and_load(pool_shift_and_load),
 .padding_sel (pool_padding_sel),
 .rd_addr (pool_rd_addr_unused),
 .fsm_state (pool_fsm_state),
 .done // not needed; use conv done
 );

 wire pool_en = (pool_fsm_state == 2'd3); // S_PROCESS

 // =========================================================================
 // 9. fifo_pool x72 -- 24 channels x 3 column offsets
 // Ch 6.2.8: DATA_W=G1_FM_W (10 bits) -- conv results are 10-bit
 // data_flat packing for maxpool_core:
 // t=0,1,2 -> col0 row0,1,2 (fifo_pool_c0)
 // t=3,4,5 -> col1 row0,1,2 (fifo_pool_c1)
 // t=6,7,8 -> col2 row0,1,2 (fifo_pool_c2)
 // pool_padding_sel driven by pool fifo_ctrl.
 // pool_shift_and_load driven by pool fifo_ctrl.
 // data_in driven by conv result (current, -1cycle, -2cycle).
 // =========================================================================
 wire [FLAT_POOL-1:0] pool_data_flat;

 genvar ch;
 generate
 for (ch = 0; ch < N_FILT; ch = ch + 1) begin : gen_pool

 // Column 0: current conv result
 wire signed [G1_FM_W-1:0] p0_t0, p0_t1, p0_t2;
 fifo_pool #(.DATA_W(G1_FM_W)) u_p0 (
 .clk (clk), .rst(rst),
 .shift_and_load(pool_shift_and_load),
 .padding_sel (pool_padding_sel),
 .data_in (conv_results [ch*G1_FM_W +: G1_FM_W]),
 .tap0(p0_t0), .tap1(p0_t1), .tap2(p0_t2)
 );

 // Column 1: one-cycle delayed conv result
 wire signed [G1_FM_W-1:0] p1_t0, p1_t1, p1_t2;
 fifo_pool #(.DATA_W(G1_FM_W)) u_p1 (
 .clk (clk), .rst(rst),
 .shift_and_load(pool_shift_and_load),
 .padding_sel (pool_padding_sel),
 .data_in (conv_results_d1[ch*G1_FM_W +: G1_FM_W]),
 .tap0(p1_t0), .tap1(p1_t1), .tap2(p1_t2)
 );

 // Column 2: two-cycle delayed conv result
 wire signed [G1_FM_W-1:0] p2_t0, p2_t1, p2_t2;
 fifo_pool #(.DATA_W(G1_FM_W)) u_p2 (
 .clk (clk), .rst(rst),
 .shift_and_load(pool_shift_and_load),
 .padding_sel (pool_padding_sel),
 .data_in (conv_results_d2[ch*G1_FM_W +: G1_FM_W]),
 .tap0(p2_t0), .tap1(p2_t1), .tap2(p2_t2)
 );

 // Pack 9 taps into pool_data_flat
 assign pool_data_flat[(ch*9+0)*G1_FM_W +: G1_FM_W] = p0_t0;
 assign pool_data_flat[(ch*9+1)*G1_FM_W +: G1_FM_W] = p0_t1;
 assign pool_data_flat[(ch*9+2)*G1_FM_W +: G1_FM_W] = p0_t2;
 assign pool_data_flat[(ch*9+3)*G1_FM_W +: G1_FM_W] = p1_t0;
 assign pool_data_flat[(ch*9+4)*G1_FM_W +: G1_FM_W] = p1_t1;
 assign pool_data_flat[(ch*9+5)*G1_FM_W +: G1_FM_W] = p1_t2;
 assign pool_data_flat[(ch*9+6)*G1_FM_W +: G1_FM_W] = p2_t0;
 assign pool_data_flat[(ch*9+7)*G1_FM_W +: G1_FM_W] = p2_t1;
 assign pool_data_flat[(ch*9+8)*G1_FM_W +: G1_FM_W] = p2_t2;

 end
 endgenerate

 // =========================================================================
 // 10. maxpool_core -- 24-channel 9-win max-of-9
 // =========================================================================
 wire [FLAT_RES-1:0] maxpool_results; // 24*G1_FM_W = 240 bits

 maxpool_core u_maxpool (
 .clk (clk),
 .rst (rst),
 .en (pool_en),
 .data_flat (pool_data_flat),
 .results_flat(maxpool_results)
 );

 // =========================================================================
 // 11. maxpool_mem write address counter
 // Increments on each valid maxpool output (pool_en cycle).
 // Wraps at G1_OUT_H * G1_OUT_W = 56*56 = 3136.
 // =========================================================================
 reg [`MAXPOOL_MEM_AW-1:0] maxpool_wr_addr;
 wire maxpool_we = pool_en;

 always @(posedge clk or posedge rst) begin
 if (rst)
 maxpool_wr_addr <= {`MAXPOOL_MEM_AW{1'b0}};
 else if (maxpool_we) begin
 if (maxpool_wr_addr == `MAXPOOL_MEM_DEPTH - 1)
 maxpool_wr_addr <= {`MAXPOOL_MEM_AW{1'b0}};
 else
 maxpool_wr_addr <= maxpool_wr_addr + 1'b1;
 end
 end

 // =========================================================================
 // 12. maxpool_mem -- 24-channel SDP BRAM output memory
 // =========================================================================
 maxpool_mem u_maxpool_mem (
 .clk (clk),
 .rst (rst),
 .addr_wr (maxpool_wr_addr),
 .data_in (maxpool_results),
 .we (maxpool_we),
 .addr_rd (mp_addr_rd),
 .data_out(mp_data_out)
 );

endmodule

`default_nettype wire
// =============================================================================
// END group1_top.v
// =============================================================================
