import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


# -------------------------
# ISA encoding helpers
# -------------------------
OP_ADD = 0b000
OP_SUB = 0b001
OP_LW  = 0b010
OP_SW  = 0b011
OP_BEQ = 0b100
OP_NOP = 0b111


def encode_instr(op, rd=0, rs1=0, rs2=0, imm=0):
    """
    [31:29] op
    [28:26] rd
    [25:23] rs1
    [22:20] rs2
    [19:0]  imm
    """
    return (
        (op  << 29) |
        (rd  << 26) |
        (rs1 << 23) |
        (rs2 << 20) |
        (imm & 0xFFFFF)
    )


async def reset_dut(dut):
    dut.rst.value = 1
    await Timer(20, units="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)


def read_reg(dut, idx):
    return int(dut.regfile[idx].value)


def read_mem(dut, idx):
    return int(dut.dmem[idx].value)


# -------------------------
# MAIN TEST
# -------------------------
@cocotb.test()
async def test_cpu_basic_program(dut):
    """Test arithmetic, load/store, and pipeline correctness"""

    # Clock: 100 MHz
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # -------------------------
    # Load program into IMEM
    # -------------------------
    # R1 = 5
    dut.imem[0].value = encode_instr(OP_ADD, rd=1, rs1=0, rs2=0, imm=5)

    # R2 = R1 + R1 = 10
    dut.imem[1].value = encode_instr(OP_ADD, rd=2, rs1=1, rs2=1)

    # MEM[4] = R2
    dut.imem[2].value = encode_instr(OP_SW, rs1=0, rs2=2, imm=4)

    # R3 = MEM[4]
    dut.imem[3].value = encode_instr(OP_LW, rd=3, rs1=0, imm=4)

    # R4 = R3 - R1 = 5
    dut.imem[4].value = encode_instr(OP_SUB, rd=4, rs1=3, rs2=1)

    # NOPs to drain pipeline
    for i in range(5, 10):
        dut.imem[i].value = encode_instr(OP_NOP)

    # -------------------------
    # Run simulation
    # -------------------------
    for _ in range(20):
        await RisingEdge(dut.clk)

    # -------------------------
    # CHECK RESULTS
    # -------------------------
    assert read_reg(dut, 1) == 5,  f"R1 incorrect: {read_reg(dut,1)}"
    assert read_reg(dut, 2) == 10, f"R2 incorrect: {read_reg(dut,2)}"
    assert read_mem(dut, 1) == 10, "Memory store failed"
    assert read_reg(dut, 3) == 10, f"R3 incorrect: {read_reg(dut,3)}"
    assert read_reg(dut, 4) == 5,  f"R4 incorrect: {read_reg(dut,4)}"

    dut._log.info("✅ BASIC PROGRAM TEST PASSED")
    
    

# CRITICAL: Pytest wrapper function
def test_cpu_5stage_hidden_runner():
    import os
    from pathlib import Path
    from cocotb_tools.runner import get_runner
    
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    
    sources = [
        proj_path / "sources/cpu_5stage.sv",
    ]
    
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="cpu_5stage",
        always=True,
    )
    
    runner.test(
        hdl_toplevel="cpu_5stage",
        test_module="test_cpu_5stage_hidden"
    )

