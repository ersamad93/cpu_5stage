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

    // --- Internal Registers ---
    reg [31:0] if_id_instr;
    reg [31:0] id_ex_instr, id_ex_reg_a, id_ex_reg_b, id_ex_imm;
    reg [4:0]  id_ex_rs, id_ex_rt, id_ex_rd;
    reg [31:0] ex_mem_alu_res, ex_mem_reg_b, ex_mem_instr;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_write;
    reg [31:0] mem_wb_alu_res, mem_wb_mem_data, mem_wb_instr;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write;

    reg [31:0] rf [0:31];

    // --- Decode Logic ---
    wire [5:0] opcode = if_id_instr[31:26];
    wire [4:0] rs = if_id_instr[25:21];
    wire [4:0] rt = if_id_instr[20:16];
    wire [4:0] rd = if_id_instr[15:11];
    wire [31:0] sign_imm = {{16{if_id_instr[15]}}, if_id_instr[15:0]};

    // --- Hazard Detection Unit (Corner Case 2: Load-Use) ---
    wire is_lw_ex = (id_ex_instr[31:26] == 6'h23);
    wire load_use_stall = is_lw_ex && ((id_ex_instr[20:16] == rs) || (id_ex_instr[20:16] == rt));

    // --- IF Stage ---
    always @(posedge clk or posedge rst) begin
        if (rst) pc <= 32'h0;
        else if (!load_use_stall) pc <= pc + 4;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) if_id_instr <= 32'h0;
        else if (!load_use_stall) if_id_instr <= instr;
    end

    // --- ID Stage ---
    // Combinational read for timing alignment with testbench
    wire [31:0] rf_data_a = (rs == 0) ? 32'h0 : rf[rs];
    wire [31:0] rf_data_b = (rt == 0) ? 32'h0 : rf[rt];

    always @(posedge clk or posedge rst) begin
        if (rst || load_use_stall) begin
            id_ex_instr <= 0;
            id_ex_reg_write <= 0;
        end else begin
            id_ex_instr <= if_id_instr;
            id_ex_reg_a <= rf_data_a;
            id_ex_reg_b <= rf_data_b;
            id_ex_imm   <= sign_imm;
            id_ex_rs    <= rs;
            id_ex_rt    <= rt;
            id_ex_rd    <= (opcode == 6'h0) ? rd : rt; // R-type uses rd, I-type uses rt
        end
    end

    // --- EX Stage (Corner Case 1: Waterfall Priority) ---
    reg [31:0] fwd_a, fwd_b;
    always @(*) begin
        // Priority Forwarding A
        if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == id_ex_rs) fwd_a = ex_mem_alu_res;
        else if (mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == id_ex_rs) fwd_a = wb_data;
        else fwd_a = id_ex_reg_a;
        // Priority Forwarding B
        if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == id_ex_rt) fwd_b = ex_mem_alu_res;
        else if (mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == id_ex_rt) fwd_b = wb_data;
        else fwd_b = id_ex_reg_b;
    end

    wire [31:0] alu_in2 = (id_ex_instr[31:26] == 6'h0) ? fwd_b : id_ex_imm;
    reg [31:0] alu_out;
    always @(*) begin
        if (id_ex_instr[31:26] == 6'h0) alu_out = fwd_a + fwd_b; // ADD
        else alu_out = fwd_a + id_ex_imm; // ADDI, LW, SW
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_mem_alu_res <= 0;
            ex_mem_instr <= 0;
            ex_mem_reg_write <= 0;
        end else begin
            ex_mem_alu_res <= alu_out;
            ex_mem_reg_b   <= fwd_b; // Corner Case 4: SW Forwarding
            ex_mem_instr   <= id_ex_instr;
            ex_mem_rd      <= id_ex_rd;
            ex_mem_reg_write <= (id_ex_instr != 0 && id_ex_instr[31:26] != 6'h2b); // No write for SW or NOP
        end
    end

    // --- MEM Stage ---
    assign d_addr = ex_mem_alu_res;
    assign d_wdata = ex_mem_reg_b;
    assign d_we = (ex_mem_instr[31:26] == 6'h2b); // SW Enable

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_wb_alu_res <= 0;
            mem_wb_mem_data <= 0;
            mem_wb_instr <= 0;
            mem_wb_reg_write <= 0;
        end else begin
            mem_wb_alu_res <= ex_mem_alu_res;
            mem_wb_mem_data <= d_rdata;
            mem_wb_instr <= ex_mem_instr;
            mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
        end
    end

    // --- WB Stage (Corner Case 3: R0 Immortality) ---
    wire [31:0] wb_data = (mem_wb_instr[31:26] == 6'h23) ? mem_wb_mem_data : mem_wb_alu_res;
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) for (i=0; i<32; i=i+1) rf[i] <= 0;
        else if (mem_wb_reg_write && mem_wb_rd != 0) rf[mem_wb_rd] <= wb_data;
    end

endmodule
