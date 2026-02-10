`timescale 1ns/1ps
module cpu_5stage (
    input  wire        clk,
    input  wire        reset
);

    // -----------------------------
    // Instruction memory (simple ROM)
    // -----------------------------
    reg [31:0] imem [0:255];
    initial $readmemh("program.hex", imem);

    // -----------------------------
    // Register file
    // -----------------------------
    reg [31:0] regfile [0:31];

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1)
                regfile[i] <= 32'd0;
        end
    end

    // -----------------------------
    // Program Counter
    // -----------------------------
    reg [31:0] pc;
    always @(posedge clk) begin
        if (reset)
            pc <= 32'd0;
        else
            pc <= pc + 4;
    end

    // =============================
    // PIPELINE REGISTERS
    // =============================

    // IF/ID
    reg [31:0] if_id_instr;

    // ID/EX
    reg [31:0] id_ex_rs1_val, id_ex_rs2_val;
    reg [4:0]  id_ex_rd;
    reg [31:0] id_ex_imm;
    reg        id_ex_is_addi;
    reg        id_ex_regwrite;

    // EX/MEM
    reg [31:0] ex_mem_alu;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_regwrite;

    // MEM/WB
    reg [31:0] mem_wb_result;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_regwrite;

    // =============================
    // IF stage
    // =============================
    always @(posedge clk) begin
        if (reset)
            if_id_instr <= 32'd0;
        else
            if_id_instr <= imem[pc[9:2]];
    end

    // =============================
    // ID stage
    // =============================
    wire [6:0] opcode = if_id_instr[6:0];
    wire [4:0] rd     = if_id_instr[11:7];
    wire [2:0] funct3 = if_id_instr[14:12];
    wire [4:0] rs1    = if_id_instr[19:15];
    wire [4:0] rs2    = if_id_instr[24:20];

    wire is_add  = (opcode == 7'b0110011);
    wire is_addi = (opcode == 7'b0010011);

    wire [31:0] imm_i = {{20{if_id_instr[31]}}, if_id_instr[31:20]};

    always @(posedge clk) begin
        if (reset) begin
            id_ex_regwrite <= 1'b0;
        end else begin
            id_ex_rs1_val  <= regfile[rs1];
            id_ex_rs2_val  <= regfile[rs2];
            id_ex_rd       <= rd;
            id_ex_imm      <= imm_i;
            id_ex_is_addi  <= is_addi;
            id_ex_regwrite <= is_add | is_addi;
        end
    end

    // =============================
    // EX stage
    // =============================
    always @(posedge clk) begin
        if (reset) begin
            ex_mem_regwrite <= 1'b0;
        end else begin
            ex_mem_alu <= id_ex_is_addi ?
                          (id_ex_rs1_val + id_ex_imm) :
                          (id_ex_rs1_val + id_ex_rs2_val);
            ex_mem_rd       <= id_ex_rd;
            ex_mem_regwrite <= id_ex_regwrite;
        end
    end

    // =============================
    // MEM stage (pass-through)
    // =============================
    always @(posedge clk) begin
        if (reset) begin
            mem_wb_regwrite <= 1'b0;
        end else begin
            mem_wb_result   <= ex_mem_alu;
            mem_wb_rd       <= ex_mem_rd;
            mem_wb_regwrite <= ex_mem_regwrite;
        end
    end

    // =============================
    // WB stage (THIS WAS THE BUG)
    // =============================
    always @(posedge clk) begin
        if (!reset && mem_wb_regwrite && mem_wb_rd != 0) begin
            regfile[mem_wb_rd] <= mem_wb_result;
        end
    end

endmodule
