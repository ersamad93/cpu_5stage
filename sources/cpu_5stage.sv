`timescale 1ns/1ps
module cpu_5stage (
    input wire clk,
    input wire rst,
    output reg [31:0] pc,
    input wire [31:0] instr,
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    input wire [31:0] d_rdata,
    output wire d_we
);

    // --- Pipeline Registers ---
    reg [31:0] if_id_instr;
    reg [31:0] id_ex_instr, id_ex_reg_a, id_ex_reg_b;
    reg [4:0]  id_ex_rs, id_ex_rt, id_ex_rd;
    
    reg [31:0] ex_mem_alu_res, ex_mem_reg_b;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_write;

    reg [31:0] mem_wb_alu_res;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write;

    // Register File
    reg [31:0] rf [0:31];

    // --- IF Stage ---
    always @(posedge clk or posedge rst) begin
        if (rst) pc <= 0;
        else     pc <= pc + 4;
    end

    // --- ID Stage ---
    always @(posedge clk) begin
        if_id_instr <= instr;
        id_ex_instr <= if_id_instr;
        id_ex_reg_a <= rf[if_id_instr[25:21]];
        id_ex_reg_b <= rf[if_id_instr[20:16]];
        id_ex_rs    <= if_id_instr[25:21];
        id_ex_rt    <= if_id_instr[20:16];
        id_ex_rd    <= if_id_instr[15:11];
    end

    // --- EX Stage (Forwarding Logic) ---
    wire [31:0] forward_a, forward_b;
    
    // Forwarding for Operand A
    assign forward_a = (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs)) ? ex_mem_alu_res :
                       (mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs)) ? mem_wb_alu_res :
                       id_ex_reg_a;

    // Forwarding for Operand B
    assign forward_b = (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rt)) ? ex_mem_alu_res :
                       (mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rt)) ? mem_wb_alu_res :
                       id_ex_reg_b;

    wire [31:0] alu_out = forward_a + forward_b; // Assume ADD

    always @(posedge clk) begin
        ex_mem_alu_res   <= alu_out;
        ex_mem_reg_b     <= forward_b;
        ex_mem_rd        <= id_ex_rd;
        ex_mem_reg_write <= 1'b1;
    end

    // --- MEM Stage ---
    assign d_addr = ex_mem_alu_res;
    assign d_we   = 0; 

    always @(posedge clk) begin
        mem_wb_alu_res   <= ex_mem_alu_res;
        mem_wb_rd        <= ex_mem_rd;
        mem_wb_reg_write <= ex_mem_reg_write;
    end

    // --- WB Stage ---
    always @(posedge clk) begin
        if (mem_wb_reg_write && mem_wb_rd != 0)
            rf[mem_wb_rd] <= mem_wb_alu_res;
    end
endmodule