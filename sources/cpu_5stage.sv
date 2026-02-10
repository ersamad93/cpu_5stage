`timescale 1ns/1ps
module cpu_5stage (
    input  wire        clk,
    input  wire        rst,
    // Instruction Memory
    output reg  [31:0] pc,
    input  wire [31:0] instr,
    // Data Memory
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    input  wire [31:0] d_rdata,
    output wire        d_we
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

    // --- Register File ---
    reg [31:0] rf [0:31];
    integer i;

    // --- IF Stage ---
    always @(posedge clk or posedge rst) begin
        if (rst) 
            pc <= 32'h0;
        else     
            pc <= pc + 4;
    end

    // --- IF/ID Pipeline Register ---
    always @(posedge clk or posedge rst) begin
        if (rst) 
            if_id_instr <= 32'h0;
        else     
            if_id_instr <= instr;
    end

    // --- ID Stage & ID/EX Pipeline Register ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            id_ex_instr <= 32'h0;
            id_ex_reg_a <= 32'h0;
            id_ex_reg_b <= 32'h0;
            id_ex_rs    <= 5'h0;
            id_ex_rt    <= 5'h0;
            id_ex_rd    <= 5'h0;
        end else begin
            id_ex_instr <= if_id_instr;
            id_ex_reg_a <= rf[if_id_instr[25:21]];
            id_ex_reg_b <= rf[if_id_instr[20:16]];
            id_ex_rs    <= if_id_instr[25:21];
            id_ex_rt    <= if_id_instr[20:16];
            id_ex_rd    <= if_id_instr[15:11];
        end
    end

    // --- EX Stage (Forwarding Logic) ---
    wire [31:0] fwd_val_a, fwd_val_b;
    
    // Forwarding Unit: Prioritize EX/MEM (most recent) over MEM/WB
    assign fwd_val_a = (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs)) ? ex_mem_alu_res :
                       (mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs)) ? mem_wb_alu_res :
                       id_ex_reg_a;

    assign fwd_val_b = (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rt)) ? ex_mem_alu_res :
                       (mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rt)) ? mem_wb_alu_res :
                       id_ex_reg_b;

    // Simplified ALU: Only ADD for now
    wire [31:0] alu_out = fwd_val_a + fwd_val_b;

    // --- EX/MEM Pipeline Register ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_mem_alu_res   <= 32'h0;
            ex_mem_reg_b     <= 32'h0;
            ex_mem_rd        <= 5'h0;
            ex_mem_reg_write <= 1'b0;
        end else begin
            ex_mem_alu_res   <= alu_out;
            ex_mem_reg_b     <= fwd_val_b;
            ex_mem_rd        <= id_ex_rd;
            ex_mem_reg_write <= (id_ex_instr != 0); // Only write if instruction is not NOP
        end
    end

    // --- MEM Stage & MEM/WB Pipeline Register ---
    assign d_addr  = ex_mem_alu_res;
    assign d_wdata = ex_mem_reg_b;
    assign d_we    = 1'b0; // Static read-only for this example

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_wb_alu_res   <= 32'h0;
            mem_wb_rd        <= 5'h0;
            mem_wb_reg_write <= 1'b0;
        end else begin
            mem_wb_alu_res   <= ex_mem_alu_res;
            mem_wb_rd        <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
        end
    end

    // --- WB Stage (Write Back to Register File) ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) rf[i] <= 32'h0;
        end else begin
            if (mem_wb_reg_write && mem_wb_rd != 5'd0) begin
                rf[mem_wb_rd] <= mem_wb_alu_res;
            end
        end
    end

endmodule