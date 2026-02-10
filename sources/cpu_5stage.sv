`timescale 1ns/1ps
`timescale 1ns/1ps

module cpu_5stage (
    input  wire clk,
    input  wire rst
);

    // -----------------------------
    // State
    // -----------------------------
    reg [31:0] pc;

    // Register file (EXPOSED FOR COCOTB)
    reg [31:0] regfile [0:31];

    // Instruction memory (loaded by cocotb)
    reg [31:0] instr_mem [0:255];

    // -----------------------------
    // Instruction fields (MIPS-like)
    // -----------------------------
    wire [31:0] instr;
    wire [5:0]  opcode;
    wire [4:0]  rs, rt, rd;
    wire [15:0] imm;

    assign instr  = instr_mem[pc[9:2]];
    assign opcode = instr[31:26];
    assign rs     = instr[25:21];
    assign rt     = instr[20:16];
    assign rd     = instr[15:11];
    assign imm    = instr[15:0];

    // -----------------------------
    // Immediate
    // -----------------------------
    wire [31:0] imm_ext = {{16{imm[15]}}, imm};

    // -----------------------------
    // Execute values
    // -----------------------------
    reg [31:0] alu_result;
    reg        reg_write;
    reg [4:0]  reg_dst;
    reg [31:0] reg_wdata;

    // -----------------------------
    // Sequential logic
    // -----------------------------
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            pc <= 0;
            for (i = 0; i < 32; i = i + 1)
                regfile[i] <= 0;
        end else begin
            // -----------------------------
            // Default
            // -----------------------------
            reg_write <= 0;
            alu_result <= 0;
            reg_dst <= 0;
            reg_wdata <= 0;

            // -----------------------------
            // Decode + Execute
            // -----------------------------
            case (opcode)

                // ADDI rt, rs, imm
                6'b001000: begin
                    alu_result = regfile[rs] + imm_ext;
                    reg_dst    = rt;
                    reg_wdata  = alu_result;
                    reg_write  = 1;
                end

                // ADD rd, rs, rt
                6'b000000: begin
                    alu_result = regfile[rs] + regfile[rt];
                    reg_dst    = rd;
                    reg_wdata  = alu_result;
                    reg_write  = 1;
                end

                // NOP / unsupported
                default: begin
                    reg_write = 0;
                end
            endcase

            // -----------------------------
            // Writeback
            // -----------------------------
            if (reg_write && reg_dst != 0) begin
                regfile[reg_dst] <= reg_wdata;
            end

            // -----------------------------
            // Next PC
            // -----------------------------
            pc <= pc + 4;
        end
    end

endmodule
