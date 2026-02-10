`timescale 1ns/1ps
module cpu_5stage (
    input  logic clk,
    input  logic rst
);

    /* ---------------- OPCODES ---------------- */
    localparam OP_ADD = 3'b000;
    localparam OP_SUB = 3'b001;
    localparam OP_LW  = 3'b010;
    localparam OP_SW  = 3'b011;
    localparam OP_BEQ = 3'b100;
    localparam OP_NOP = 3'b111;

    /* ---------------- STATE ---------------- */
    logic [31:0] pc;
    logic [31:0] imem [0:255];
    logic [31:0] dmem [0:255];
    logic [31:0] regfile [0:7];

    /* ---------------- IF / ID ---------------- */
    logic [31:0] ifid_instr;
    logic [31:0] ifid_pc;

    /* ---------------- ID / EX ---------------- */
    logic [2:0]  idex_op;
    logic [2:0]  idex_rd, idex_rs1, idex_rs2;
    logic [31:0] idex_imm;
    logic [31:0] idex_a, idex_b;

    /* ---------------- EX / MEM ---------------- */
    logic [2:0]  exmem_op;
    logic [2:0]  exmem_rd;
    logic [31:0] exmem_alu;
    logic [31:0] exmem_b;

    /* ---------------- MEM / WB ---------------- */
    logic [2:0]  memwb_op;
    logic [2:0]  memwb_rd;
    logic [31:0] memwb_val;

    integer i;

    /* ---------------- FETCH ---------------- */
    always_ff @(posedge clk) begin
        if (rst) begin
            pc          <= 32'd0;
            ifid_instr <= 32'd0;
            ifid_pc    <= 32'd0;
        end else begin
            ifid_instr <= imem[pc[9:2]];
            ifid_pc    <= pc;
            pc <= pc + 4;
        end
    end

    /* ---------------- DECODE ---------------- */
    always_ff @(posedge clk) begin
        if (rst) begin
            idex_op  <= OP_NOP;
            idex_rd  <= 3'd0;
            idex_rs1 <= 3'd0;
            idex_rs2 <= 3'd0;
            idex_imm <= 32'd0;
            idex_a   <= 32'd0;
            idex_b   <= 32'd0;
        end else begin
            idex_op  <= ifid_instr[31:29];
            idex_rd  <= ifid_instr[28:26];
            idex_rs1 <= ifid_instr[25:23];
            idex_rs2 <= ifid_instr[22:20];
            idex_imm <= {{20{ifid_instr[19]}}, ifid_instr[19:0]};
            idex_a   <= regfile[ifid_instr[25:23]];
            idex_b   <= regfile[ifid_instr[22:20]];
        end
    end

    /* ---------------- EXECUTE ---------------- */
    always_ff @(posedge clk) begin
        if (rst) begin
            exmem_op  <= OP_NOP;
            exmem_rd  <= 3'd0;
            exmem_alu <= 32'd0;
            exmem_b   <= 32'd0;
        end else begin
            exmem_op <= idex_op;
            exmem_rd <= idex_rd;
            exmem_b  <= idex_b;

            case (idex_op)
                // ✅ FIX: ADD uses immediate
                OP_ADD: exmem_alu <= idex_a + idex_b + idex_imm;

                OP_SUB: exmem_alu <= idex_a - idex_b;
                OP_LW,
                OP_SW : exmem_alu <= idex_a + idex_imm;
                OP_BEQ: exmem_alu <= (idex_a == idex_b);
                default: exmem_alu <= 32'd0;
            endcase
        end
    end

    /* ---------------- MEMORY ---------------- */
    always_ff @(posedge clk) begin
        if (rst) begin
            memwb_op  <= OP_NOP;
            memwb_rd  <= 3'd0;
            memwb_val <= 32'd0;

            for (i = 0; i < 256; i = i + 1)
                dmem[i] <= 32'd0;
        end else begin
            memwb_op <= exmem_op;
            memwb_rd <= exmem_rd;

            case (exmem_op)
                OP_LW: memwb_val <= dmem[exmem_alu[9:2]];
                OP_SW: begin
                    dmem[exmem_alu[9:2]] <= exmem_b;
                    memwb_val <= 32'd0;
                end
                default: memwb_val <= exmem_alu;
            endcase
        end
    end

    /* ---------------- WRITEBACK + RESET ---------------- */
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 8; i = i + 1)
                regfile[i] <= 32'd0;
        end else begin
            regfile[0] <= 32'd0; // R0 hardwired

            if (memwb_rd != 3'd0 &&
                (memwb_op == OP_ADD ||
                 memwb_op == OP_SUB ||
                 memwb_op == OP_LW)) begin
                regfile[memwb_rd] <= memwb_val;
            end
        end
    end

endmodule
