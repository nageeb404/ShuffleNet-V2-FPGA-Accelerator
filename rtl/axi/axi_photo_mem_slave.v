// =============================================================================
// axi_photo_mem_slave.v -- AXI4-Lite slave: PS image-load + accelerator control
// -----------------------------------------------------------------------------
// Path A, Step 8: connects the Zynq PS AXI master to the photo_mem write port
// and the accelerator photo_ready / busy handshake.
//
// AXI4-Lite address map (byte offsets from slave base address):
//
// Pixel write region (AWADDR[21] = 0):
// AWADDR[20] = pm_mem_select (0 = ping, 1 = pong)
// AWADDR[19:18] = channel (00 = R -> pm_we=001,
// 01 = G -> pm_we=010,
// 10 = B -> pm_we=100)
// AWADDR[17:2] = pm_addr_wr[15:0] (pixel index 0 .. 50175)
// WDATA[14:0] = pm_data_in (Q6.8 pixel value, 8-bit value in [7:0])
//
// Control / status register (AWADDR[21] = 1):
// Write WDATA[0] = photo_ready (1 = new image ready; 0 = clear)
// Read RDATA[0] = photo_ready (current register value)
// Read RDATA[1] = busy (accelerator busy; G1/G2 active)
// Read RDATA[2] = classification_done (1-cycle pulse latched by PS poll)
// Read RDATA[12:3] = class_idx[9:0] (top-1 class 0..999)
//
// pm_we is pulsed for exactly one clock cycle per AXI write transaction.
//
// AXI4-Lite write ordering:
// AW and W channels accepted independently (either may arrive first).
// BVALID is asserted after both are latched; cleared on BREADY.
//
// Read channel:
// AR accepted immediately; R returned next cycle.
// Pixel region always returns 0; CSR returns {30'b0, busy, photo_ready}.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module axi_photo_mem_slave #(
    parameter integer AXI_AW = 32,   // AXI address bus width
    parameter integer AXI_DW = 32    // AXI data bus width (must be 32 for AXI4-Lite)
) (
    // ---- AXI4-Lite global ----
    input  wire                  S_AXI_ACLK,
    input  wire                  S_AXI_ARESETN,

    // ---- AXI4-Lite write address channel ----
    input  wire [AXI_AW-1:0]    S_AXI_AWADDR,
    input  wire                  S_AXI_AWVALID,
    output wire                  S_AXI_AWREADY,

    // ---- AXI4-Lite write data channel ----
    input  wire [AXI_DW-1:0]    S_AXI_WDATA,
    input  wire [AXI_DW/8-1:0]  S_AXI_WSTRB,
    input  wire                  S_AXI_WVALID,
    output wire                  S_AXI_WREADY,

    // ---- AXI4-Lite write response channel ----
    output wire [1:0]            S_AXI_BRESP,
    output wire                  S_AXI_BVALID,
    input  wire                  S_AXI_BREADY,

    // ---- AXI4-Lite read address channel ----
    input  wire [AXI_AW-1:0]    S_AXI_ARADDR,
    input  wire                  S_AXI_ARVALID,
    output wire                  S_AXI_ARREADY,

    // ---- AXI4-Lite read data channel ----
    output wire [AXI_DW-1:0]    S_AXI_RDATA,
    output wire [1:0]            S_AXI_RRESP,
    output wire                  S_AXI_RVALID,
    input  wire                  S_AXI_RREADY,

    // ---- Photo memory write port (to group1_top / accelerator_top) ----
    output reg  [`PHOTO_MEM_AW-1:0]  pm_addr_wr,
    output reg  [`DATA_W-1:0]        pm_data_in,
    output reg  [2:0]                pm_we,
    output reg                       pm_mem_select,

    // ---- Accelerator handshake ----
    output reg                   photo_ready,   // level: PS holds high when image ready
    input  wire                  busy,          // from accelerator_top: G1/G2 active

    // ---- Classification result (PS reads back via CSR) ----
    input  wire [9:0]            class_idx,         // top-1 class (0..999)
    input  wire                  classification_done // 1-cycle pulse when result valid
);

    // =========================================================================
    // Internal registers
    // =========================================================================
    // Write-address latch
    reg [AXI_AW-1:0] aw_addr_r;
    reg               have_aw;   // AW has been accepted, write not yet executed

    // Write-data latch
    reg [AXI_DW-1:0] w_data_r;
    reg               have_w;    // W has been accepted, write not yet executed

    // Write response
    reg               bvalid_r;

    // Read channel
    reg               arready_r;
    reg               rvalid_r;
    reg [AXI_DW-1:0] rdata_r;

    // =========================================================================
    // Write execution: fires for ONE clock cycle when both AW and W are latched
    // =========================================================================
    wire do_write    = have_aw && have_w;
    wire is_ctrl_reg = aw_addr_r[21];

    // =========================================================================
    // AW channel
    // =========================================================================
    assign S_AXI_AWREADY = !have_aw && !bvalid_r;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            have_aw  <= 1'b0;
            aw_addr_r <= {AXI_AW{1'b0}};
        end else begin
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                aw_addr_r <= S_AXI_AWADDR;
                have_aw   <= 1'b1;
            end else if (do_write) begin
                have_aw <= 1'b0;
            end
        end
    end

    // =========================================================================
    // W channel
    // =========================================================================
    assign S_AXI_WREADY = !have_w && !bvalid_r;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            have_w  <= 1'b0;
            w_data_r <= {AXI_DW{1'b0}};
        end else begin
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                w_data_r <= S_AXI_WDATA;
                have_w   <= 1'b1;
            end else if (do_write) begin
                have_w <= 1'b0;
            end
        end
    end

    // =========================================================================
    // B channel
    // =========================================================================
    assign S_AXI_BRESP  = 2'b00;   // OKAY
    assign S_AXI_BVALID = bvalid_r;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            bvalid_r <= 1'b0;
        else if (do_write)
            bvalid_r <= 1'b1;
        else if (S_AXI_BREADY)
            bvalid_r <= 1'b0;
    end

    // =========================================================================
    // Write action: photo_mem or control register
    // =========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            pm_we         <= 3'b0;
            pm_addr_wr    <= {`PHOTO_MEM_AW{1'b0}};
            pm_data_in    <= {`DATA_W{1'b0}};
            pm_mem_select <= 1'b0;
            photo_ready   <= 1'b0;
        end else begin
            pm_we <= 3'b0;   // default: deassert each cycle

            if (do_write) begin
                if (!is_ctrl_reg) begin
                    // Pixel write: decode address -> photo_mem controls
                    pm_addr_wr    <= aw_addr_r[17:2];    // 16-bit pixel index
                    pm_mem_select <= aw_addr_r[20];      // ping / pong
                    pm_data_in    <= w_data_r[`DATA_W-1:0];
                    // one-hot channel enable
                    case (aw_addr_r[19:18])
                        2'b00:   pm_we <= 3'b001;  // R
                        2'b01:   pm_we <= 3'b010;  // G
                        2'b10:   pm_we <= 3'b100;  // B
                        default: pm_we <= 3'b000;
                    endcase
                end else begin
                    // Control register write: update photo_ready
                    photo_ready <= w_data_r[0];
                end
            end
        end
    end

    // =========================================================================
    // Read channel (AR + R)
    // =========================================================================
    assign S_AXI_ARREADY = arready_r;
    assign S_AXI_RDATA   = rdata_r;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RVALID  = rvalid_r;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            arready_r <= 1'b0;
            rvalid_r  <= 1'b0;
            rdata_r   <= {AXI_DW{1'b0}};
        end else begin
            arready_r <= 1'b0;  // one-cycle pulse

            if (S_AXI_ARVALID && !rvalid_r) begin
                arready_r <= 1'b1;
                rvalid_r  <= 1'b1;
                if (S_AXI_ARADDR[21])
                    // CSR read: [31:13]=0 [12:3]=class_idx [2]=done [1]=busy [0]=photo_ready
                    rdata_r <= {{(AXI_DW-13){1'b0}}, class_idx, classification_done, busy, photo_ready};
                else
                    rdata_r <= {AXI_DW{1'b0}};
            end

            if (rvalid_r && S_AXI_RREADY)
                rvalid_r <= 1'b0;
        end
    end

endmodule

`default_nettype wire
// =============================================================================
// END axi_photo_mem_slave.v
// =============================================================================
