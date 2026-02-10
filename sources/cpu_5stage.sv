`timescale 1ns/1ps
module cpu_5stage (
    input  wire        clk,
    input  wire        rst,

    output reg  [31:0] pc,
    input  wire [31:0] instr,
  
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    input  wire [31:0] d_rdata,
    output wire        d_we
);

//Add Verilog Code here
endmodule