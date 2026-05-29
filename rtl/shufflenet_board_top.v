// =============================================================================
// shufflenet_board_top.v -- Board wrapper for iWave ZU19EG Dev Kit
// -----------------------------------------------------------------------------
// Target : XCZU19EG-FFVC1760-2-I (Zynq UltraScale+ MPSoC)
// Clock : PS provides pl_clk0 at 100 MHz via M_AXI_HPM0_FPD clock domain.
// MMCME4_BASE re-generates a 100 MHz clock for the PL fabric to
// improve jitter and allow timing analysis isolation.
// Reset : s_axi_aresetn (active-low, from PS pl_resetn0). Synchronized to
// the MMCM output clock. Asserted until MMCM lock acquired.
//
// AXI4-Lite slave (s_axi_*) is auto-recognized by Vivado Block Design when
// this module is added as a Module Reference.
//
// Memory map (byte offsets from base address assigned in block design):
// Pixel writes : AWADDR[21]=0 -- see axi_photo_mem_slave.v header
// CSR reads : AWADDR[21]=1 -- {class_idx[9:0], done, busy, photo_ready}
//
// PS software flow:
// 1. Write all 224x224x3 pixels via AXI pixel-write region.
// 2. Write CSR with WDATA=1 to assert photo_ready.
// 3. Poll CSR until busy=0 and classification_done=1.
// 4. Read CSR[12:3] for top-1 class index.
// 5. Write CSR with WDATA=0 to clear photo_ready.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module shufflenet_board_top #(
    parameter integer AXI_AW = 32,
    parameter integer AXI_DW = 32
) (
    // ---- PS-provided clock and reset (connected by block design) ----
    input  wire                  s_axi_aclk,    // 100 MHz from PS pl_clk0
    input  wire                  s_axi_aresetn, // active-low, from PS pl_resetn0

    // ---- AXI4-Lite slave (from PS M_AXI_HPM0_FPD via AXI interconnect) ----
    input  wire [AXI_AW-1:0]    s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [AXI_DW-1:0]    s_axi_wdata,
    input  wire [AXI_DW/8-1:0]  s_axi_wstrb,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
    input  wire [AXI_AW-1:0]    s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    output wire [AXI_DW-1:0]    s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready,

    // ---- Status LEDs ----
    output wire                  busy_led,   // high while accelerator active
    output wire                  done_led    // pulses when classification done
);

    // =========================================================================
    // 1. MMCM: s_axi_aclk (100 MHz) -> clk (100 MHz, re-generated)
    // MMCME4_BASE is the UltraScale+ mixed-mode clock manager primitive.
    // VCO = 100 MHz * MULT_F = 100 * 10 = 1000 MHz (within 800-1600 MHz)
    // CLKOUT0 = 1000 / DIVIDE_F = 1000 / 10 = 100 MHz
    // =========================================================================
    wire mmcm_fb_w;        // feedback clock (loop-back)
    wire clk_100m_unbuf;   // MMCM raw output (before BUFG)
    wire mmcm_locked;      // MMCM lock indicator

    MMCME4_BASE #(
        .CLKIN1_PERIOD   (10.0),   // 100 MHz input = 10 ns period
        .CLKFBOUT_MULT_F (10.0),   // VCO = 100 * 10 = 1000 MHz
        .CLKOUT0_DIVIDE_F(10.0),   // Output = 1000 / 10 = 100 MHz
        .BANDWIDTH       ("OPTIMIZED"),
        .CLKFBOUT_PHASE  (0.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE   (0.0),
        .DIVCLK_DIVIDE   (1),
        .REF_JITTER1     (0.01),
        .STARTUP_WAIT    ("FALSE")
    ) u_mmcm (
        .CLKIN1   (s_axi_aclk),
        .CLKFBIN  (mmcm_fb_w),
        .CLKFBOUT (mmcm_fb_w),
        .CLKOUT0  (clk_100m_unbuf),
        .LOCKED   (mmcm_locked),
        .PWRDWN   (1'b0),
        .RST      (~s_axi_aresetn)
    );

    BUFG u_clk_buf (
        .I (clk_100m_unbuf),
        .O (clk)
    );

    wire clk;  // 100 MHz MMCM output, drives all PL fabric

    // =========================================================================
    // 2. Reset synchronizer
    // rst_async: asserted whenever PS reset is low OR MMCM not locked.
    // rst_sync: 4-stage metastability chain on the MMCM output clock.
    // rst: active-high synchronous reset for all PL fabric.
    // =========================================================================
    wire rst_async = ~s_axi_aresetn | ~mmcm_locked;

    reg [3:0] rst_shreg;
    always @(posedge clk or posedge rst_async) begin
        if (rst_async) rst_shreg <= 4'hF;
        else           rst_shreg <= {rst_shreg[2:0], 1'b0};
    end
    wire rst = rst_shreg[3];   // active-high synchronous reset

    // AXI slave reset: active-low, synchronous to clk
    wire axi_aresetn = ~rst;

    // =========================================================================
    // 3. Internal wires connecting AXI slave to accelerator
    // =========================================================================
    wire [`PHOTO_MEM_AW-1:0] pm_addr_wr_w;
    wire [`DATA_W-1:0]        pm_data_in_w;
    wire [2:0]                pm_we_w;
    wire                      pm_mem_select_w;
    wire                      photo_ready_w;
    wire                      busy_w;
    wire [9:0]                class_idx_w;
    wire                      classification_done_w;

    // =========================================================================
    // 4. AXI4-Lite slave
    // =========================================================================
    axi_photo_mem_slave #(
        .AXI_AW(AXI_AW),
        .AXI_DW(AXI_DW)
    ) u_axi_slave (
        .S_AXI_ACLK     (clk),
        .S_AXI_ARESETN  (axi_aresetn),

        .S_AXI_AWADDR   (s_axi_awaddr),
        .S_AXI_AWVALID  (s_axi_awvalid),
        .S_AXI_AWREADY  (s_axi_awready),

        .S_AXI_WDATA    (s_axi_wdata),
        .S_AXI_WSTRB    (s_axi_wstrb),
        .S_AXI_WVALID   (s_axi_wvalid),
        .S_AXI_WREADY   (s_axi_wready),

        .S_AXI_BRESP    (s_axi_bresp),
        .S_AXI_BVALID   (s_axi_bvalid),
        .S_AXI_BREADY   (s_axi_bready),

        .S_AXI_ARADDR   (s_axi_araddr),
        .S_AXI_ARVALID  (s_axi_arvalid),
        .S_AXI_ARREADY  (s_axi_arready),

        .S_AXI_RDATA    (s_axi_rdata),
        .S_AXI_RRESP    (s_axi_rresp),
        .S_AXI_RVALID   (s_axi_rvalid),
        .S_AXI_RREADY   (s_axi_rready),

        .pm_addr_wr         (pm_addr_wr_w),
        .pm_data_in         (pm_data_in_w),
        .pm_we              (pm_we_w),
        .pm_mem_select      (pm_mem_select_w),
        .photo_ready        (photo_ready_w),
        .busy               (busy_w),
        .class_idx          (class_idx_w),
        .classification_done(classification_done_w)
    );

    // =========================================================================
    // 5. ShuffleNet V2 Accelerator
    // =========================================================================
    accelerator_top u_accel (
        .clk                (clk),
        .rst                (rst),
        .photo_ready        (photo_ready_w),
        .busy               (busy_w),
        .pm_addr_wr         (pm_addr_wr_w),
        .pm_data_in         (pm_data_in_w),
        .pm_we              (pm_we_w),
        .pm_mem_select      (pm_mem_select_w),
        .class_idx          (class_idx_w),
        .classification_done(classification_done_w)
    );

    // =========================================================================
    // 6. Status LEDs
    // =========================================================================
    assign busy_led = busy_w;
    assign done_led = classification_done_w;

endmodule

`default_nettype wire
// =============================================================================
// END shufflenet_board_top.v
// =============================================================================
