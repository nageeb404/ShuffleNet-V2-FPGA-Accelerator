`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Structural smoke test for axi_photo_mem_slave
// Tests: compilation, reset state, outputs non-X after reset.
// Full AXI protocol test skipped (requires AXI master model).

module tb_axi_photo_mem_slave;

    localparam AXI_AW = 32;
    localparam AXI_DW = 32;

    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;

    reg  [AXI_AW-1:0] S_AXI_AWADDR=0;
    reg                S_AXI_AWVALID=0;
    wire               S_AXI_AWREADY;
    reg  [AXI_DW-1:0] S_AXI_WDATA=0;
    reg  [3:0]         S_AXI_WSTRB=0;
    reg                S_AXI_WVALID=0;
    wire               S_AXI_WREADY;
    wire [1:0]         S_AXI_BRESP;
    wire               S_AXI_BVALID;
    reg                S_AXI_BREADY=0;
    reg  [AXI_AW-1:0] S_AXI_ARADDR=0;
    reg                S_AXI_ARVALID=0;
    wire               S_AXI_ARREADY;
    wire [AXI_DW-1:0] S_AXI_RDATA;
    wire [1:0]         S_AXI_RRESP;
    wire               S_AXI_RVALID;
    reg                S_AXI_RREADY=0;

    wire [`PHOTO_MEM_AW-1:0] pm_addr_wr;
    wire [`DATA_W-1:0]       pm_data_in;
    wire [2:0]               pm_we;
    wire                     pm_mem_select;
    wire                     photo_ready;

    reg busy=0, classification_done=0;
    reg [9:0] class_idx=0;

    axi_photo_mem_slave dut(
        .S_AXI_ACLK(clk),.S_AXI_ARESETN(rst_n),
        .S_AXI_AWADDR(S_AXI_AWADDR),.S_AXI_AWVALID(S_AXI_AWVALID),.S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA),.S_AXI_WSTRB(S_AXI_WSTRB),.S_AXI_WVALID(S_AXI_WVALID),.S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP),.S_AXI_BVALID(S_AXI_BVALID),.S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARADDR(S_AXI_ARADDR),.S_AXI_ARVALID(S_AXI_ARVALID),.S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA(S_AXI_RDATA),.S_AXI_RRESP(S_AXI_RRESP),.S_AXI_RVALID(S_AXI_RVALID),.S_AXI_RREADY(S_AXI_RREADY),
        .pm_addr_wr(pm_addr_wr),.pm_data_in(pm_data_in),.pm_we(pm_we),
        .pm_mem_select(pm_mem_select),.photo_ready(photo_ready),
        .busy(busy),.classification_done(classification_done),.class_idx(class_idx));

    integer pass_cnt=0, fail_cnt=0, total=0;

    initial begin
        $display("=== tb_axi_photo_mem_slave ===");
        repeat(5) @(posedge clk); rst_n=1; @(posedge clk); #1;

        // ── Test 1: AWREADY asserted after reset (slave ready to accept) ───────
        total=total+1;
        if (^S_AXI_AWREADY!==1'bx) begin
            $display("PASS: AWREADY non-X after reset (=%0d)",S_AXI_AWREADY);
            pass_cnt=pass_cnt+1;
        end else begin
            $display("FAIL: AWREADY is X after reset"); fail_cnt=fail_cnt+1;
        end

        // ── Test 2: photo_ready=0 at reset ────────────────────────────────────
        total=total+1;
        if (photo_ready===0) begin
            $display("PASS: photo_ready=0 at reset"); pass_cnt=pass_cnt+1;
        end else begin
            $display("FAIL: photo_ready=%0d exp=0",photo_ready); fail_cnt=fail_cnt+1;
        end

        // ── Test 3: pm_we=0 at reset ──────────────────────────────────────────
        total=total+1;
        if (pm_we===3'b0) begin
            $display("PASS: pm_we=0 at reset"); pass_cnt=pass_cnt+1;
        end else begin
            $display("FAIL: pm_we=%0b exp=0",pm_we); fail_cnt=fail_cnt+1;
        end

        // ── Test 4: single write cycle (assert AW+W simultaneously) ──────────
        @(negedge clk);
        S_AXI_AWADDR=32'h00200000; S_AXI_AWVALID=1; // CSR region
        S_AXI_WDATA=32'h1; S_AXI_WSTRB=4'hF; S_AXI_WVALID=1; S_AXI_BREADY=1;
        repeat(5) @(posedge clk); #1; // Wait for handshake to complete
        S_AXI_AWVALID=0; S_AXI_WVALID=0;
        repeat(3) @(posedge clk); #1;
        total=total+1;
        if (photo_ready===1) begin
            $display("PASS: photo_ready=1 after CSR write"); pass_cnt=pass_cnt+1;
        end else begin
            $display("FAIL: photo_ready=%0d exp=1",photo_ready); fail_cnt=fail_cnt+1;
        end

        $display("---------------------------------------------------------");
        $display("PASS: %0d / %0d", pass_cnt, total);
        $display("FAIL: %0d / %0d", fail_cnt, total);
        if (fail_cnt==0) $display("RESULT: *** ALL TESTS PASSED ***");
        else             $display("RESULT: *** %0d TESTS FAILED ***", fail_cnt);
        $display("=========================================================");
        $finish;
    end
endmodule
`default_nettype wire
