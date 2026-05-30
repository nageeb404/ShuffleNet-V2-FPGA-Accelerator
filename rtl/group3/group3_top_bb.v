`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

(* black_box *)
module group3_top (
    input  wire clk,
    input  wire rst,
    input  wire start_group,
    output wire group3_done,
    output wire [13:0]                          extramem_rd_addr,
    input  wire [`G3_PW_PAR_CHAN*`G2_FM_W-1:0] extramem_data_in,
    output reg  [9:0]                           class_idx,
    output wire [13:0]                          dbg_extramem_addr,
    output wire                                 dbg_conv1x1_en
);
endmodule
