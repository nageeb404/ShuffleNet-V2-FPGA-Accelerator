// =============================================================================
// photo_mem.v -- Ping-pong input image memory (Module 1.10)
// -----------------------------------------------------------------------------
// "Photo Memory" / Figure 5.5
//
// "Since the input photo size expected by the model is 224*224*3 where 3 is
// number of channels as photos in RGB has 3 channels for the red, green and
// blue so we decided to partition the memory into 3 instance one for each
// input channel and to achieve high speed and the pipeline of the model we
// should manage to read new photo while group 1 processing the photo so we
// use a ping-pong structure for the photo memory as shown in the Figure 5.5."
//
// STRUCTURE (Fig 5.5):
// 3 channel instances, each with 2 ping-pong banks (mem1, mem2).
// - mem_select=0: write -> bank0, read -> bank1
// - mem_select=1: write -> bank1, read -> bank0
// Write: single shared data_in bus, per-channel WE bits, shared addr_wr.
// Read : shared addr_rd, one output per channel (1-cycle BRAM latency).
//
// PORT MAP (Fig 5.5):
// addr_wr [AW-1:0] -- write address (from external image loader)
// data_in [DATA_W-1:0] -- write data (15-bit Q6.8, same for all channels)
// we [2:0] -- write enable per channel (we[0]=ch1,..,we[2]=ch3)
// addr_rd [AW-1:0] -- read address (from fifo_ctrl)
// mem_select -- ping-pong bank selector
// data_out_ch{1,2,3} -- 15-bit read output per channel (1-cycle latency)
//
// IMPLEMENTATION:
// 6 inferred SDP Block RAMs (3 channels x 2 banks), each 50176 x 15 bit.
// Write port and read port use separate always blocks (Vivado SDP pattern).
// Output mux uses registered mem_select to match BRAM read latency.
// (* ram_style = "block" *) forces BRAM inference in Vivado.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Ch 6.2.6: Photo memory word width reduced from DATA_W (15) to PHOTO_W (8).
// Input pixels are in [0, 255/256] in Q6.8 so only the lower 8 bits are
// significant; the upper 7 bits are always 0. Storing 8 bits per word
// halves the BRAM data width. Output ports remain DATA_W-wide; the 8-bit
// read value is zero-extended to DATA_W, which is equivalent to the original
// Q6.8 representation (no downstream changes required).
module photo_mem #(
    parameter integer IMG_W   = `IMG_W,         // 224
    parameter integer IMG_H   = `IMG_H,         // 224
    parameter integer PHOTO_W = `PHOTO_W,       // 8 (Ch 6.2.6)
    parameter integer DATA_W  = `DATA_W,        // 15 (output port width)
    parameter integer AW      = `PHOTO_MEM_AW   // 16
) (
    input  wire              clk,
    input  wire              rst,
    // Write port (external image loader writing next frame)
    input  wire [AW-1:0]    addr_wr,
    input  wire [DATA_W-1:0] data_in,           // only lower PHOTO_W bits stored
    input  wire [2:0]        we,                // we[0]=ch1, we[1]=ch2, we[2]=ch3
    // Read port (fifo_ctrl reading current frame)
    input  wire [AW-1:0]    addr_rd,
    // Ping-pong bank select (Sec 5.3.1.1, Fig 5.5)
    input  wire              mem_select,        // 0: write->bank0, read->bank1
                                                // 1: write->bank1, read->bank0
    // Data outputs -- one per channel, 1-cycle synchronous read latency
    // Ch 6.2.8: output is PHOTO_W (8 bits), not DATA_W (no zero-extension)
    output wire [PHOTO_W-1:0] data_out_ch1,
    output wire [PHOTO_W-1:0] data_out_ch2,
    output wire [PHOTO_W-1:0] data_out_ch3
);

    localparam integer DEPTH = IMG_W * IMG_H;   // 50176 per channel per bank

    // -------------------------------------------------------------------------
    // 6 BRAM arrays: 3 channels x 2 banks, PHOTO_W-bit words (Ch 6.2.6).
    // Word width is 8 bits instead of 15, reducing BRAM data width by ~47%.
    // (* ram_style = "block" *) forces Vivado to use BRAM36 resources.
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) reg [PHOTO_W-1:0] ch1_b0 [0:DEPTH-1];
    (* ram_style = "block" *) reg [PHOTO_W-1:0] ch1_b1 [0:DEPTH-1];
    (* ram_style = "block" *) reg [PHOTO_W-1:0] ch2_b0 [0:DEPTH-1];
    (* ram_style = "block" *) reg [PHOTO_W-1:0] ch2_b1 [0:DEPTH-1];
    (* ram_style = "block" *) reg [PHOTO_W-1:0] ch3_b0 [0:DEPTH-1];
    (* ram_style = "block" *) reg [PHOTO_W-1:0] ch3_b1 [0:DEPTH-1];

    // Registered read outputs (1-cycle latency from synchronous BRAM port B)
    reg [PHOTO_W-1:0] ch1_b0_dout, ch1_b1_dout;
    reg [PHOTO_W-1:0] ch2_b0_dout, ch2_b1_dout;
    reg [PHOTO_W-1:0] ch3_b0_dout, ch3_b1_dout;

    // Write enable routing (Fig 5.5 WE DEMUX):
    // bank0 written when mem_select=0, bank1 written when mem_select=1
    wire we_ch1_b0 = we[0] & ~mem_select;
    wire we_ch1_b1 = we[0] &  mem_select;
    wire we_ch2_b0 = we[1] & ~mem_select;
    wire we_ch2_b1 = we[1] &  mem_select;
    wire we_ch3_b0 = we[2] & ~mem_select;
    wire we_ch3_b1 = we[2] &  mem_select;

    // -------------------------------------------------------------------------
    // Ch 6.2.6: write only the lower PHOTO_W bits of data_in (8 bits).
    // Read back PHOTO_W-bit values and zero-extend to DATA_W on output.
    // -------------------------------------------------------------------------

    // Channel 1, Bank 0
    always @(posedge clk) begin
        if (we_ch1_b0)
            ch1_b0[addr_wr] <= data_in[PHOTO_W-1:0];
    end
    always @(posedge clk) begin
        ch1_b0_dout <= ch1_b0[addr_rd];
    end

    // Channel 1, Bank 1
    always @(posedge clk) begin
        if (we_ch1_b1)
            ch1_b1[addr_wr] <= data_in[PHOTO_W-1:0];
    end
    always @(posedge clk) begin
        ch1_b1_dout <= ch1_b1[addr_rd];
    end

    // Channel 2, Bank 0
    always @(posedge clk) begin
        if (we_ch2_b0)
            ch2_b0[addr_wr] <= data_in[PHOTO_W-1:0];
    end
    always @(posedge clk) begin
        ch2_b0_dout <= ch2_b0[addr_rd];
    end

    // Channel 2, Bank 1
    always @(posedge clk) begin
        if (we_ch2_b1)
            ch2_b1[addr_wr] <= data_in[PHOTO_W-1:0];
    end
    always @(posedge clk) begin
        ch2_b1_dout <= ch2_b1[addr_rd];
    end

    // Channel 3, Bank 0
    always @(posedge clk) begin
        if (we_ch3_b0)
            ch3_b0[addr_wr] <= data_in[PHOTO_W-1:0];
    end
    always @(posedge clk) begin
        ch3_b0_dout <= ch3_b0[addr_rd];
    end

    // Channel 3, Bank 1
    always @(posedge clk) begin
        if (we_ch3_b1)
            ch3_b1[addr_wr] <= data_in[PHOTO_W-1:0];
    end
    always @(posedge clk) begin
        ch3_b1_dout <= ch3_b1[addr_rd];
    end

    // -------------------------------------------------------------------------
    // Output mux: registered mem_select matches 1-cycle BRAM read latency
    // mem_select=0 -> bank1 is the read bank -> output from bank1
    // mem_select=1 -> bank0 is the read bank -> output from bank0
    // -------------------------------------------------------------------------
    reg mem_select_r;
    always @(posedge clk or posedge rst) begin
        if (rst) mem_select_r <= 1'b0;
        else     mem_select_r <= mem_select;
    end

    // Ch 6.2.8: output ports are PHOTO_W (8 bits) wide -- no zero-extension.
    // Downstream data path (fifo_3x3, conv3x3_filter_unit) now uses PHOTO_W.
    assign data_out_ch1 = mem_select_r ? ch1_b0_dout : ch1_b1_dout;
    assign data_out_ch2 = mem_select_r ? ch2_b0_dout : ch2_b1_dout;
    assign data_out_ch3 = mem_select_r ? ch3_b0_dout : ch3_b1_dout;

endmodule

`default_nettype wire
// =============================================================================
// END photo_mem.v
// =============================================================================
