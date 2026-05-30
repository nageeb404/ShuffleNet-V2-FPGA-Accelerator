`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

(* black_box *)
module group1_top (
    input  wire                             clk,
    input  wire                             rst,
    input  wire [`PHOTO_MEM_AW-1:0]        pm_addr_wr,
    input  wire [`DATA_W-1:0]              pm_data_in,
    input  wire [2:0]                      pm_we,
    input  wire                            pm_mem_select,
    input  wire [`MAXPOOL_MEM_AW-1:0]      mp_addr_rd,
    output wire [`G1_OUT_C*`G1_FM_W-1:0]  mp_data_out,
    input  wire                            start,
    output wire                            done
);
endmodule
