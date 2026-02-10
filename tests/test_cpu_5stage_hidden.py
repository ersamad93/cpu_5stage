import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock


# -----------------------------
# Helpers
# -----------------------------

def encode_addi(rt, rs, imm):
    return (0b001000 << 26) | (rs << 21) | (rt << 16) | (imm & 0xFFFF)

def encode_add(rd, rs, rt):
    return (0 << 26) | (rs << 21) | (rt << 16) | (rd << 11)

def read_reg(dut, idx):
    return int(dut.regfile[idx].value)

def load_program(dut, program):
    for i, instr in enumerate(program):
        dut.instr_mem[i].value = instr


async def reset_dut(dut):
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)


# -----------------------------
# Main Exhaustive Test
# -----------------------------

@cocotb.test()
async def test_cpu_exhaustive(dut):
    """
    Exhaustive architectural verification of cpu_5stage
    """

    # Clock
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # Reset
    await reset_dut(dut)

    # -----------------------------------------
    # PROGRAM
    #
    # R1 = 5
    # R2 = 10
    # R3 = R1 + R2 = 15
    # R4 = R3 + (-5) = 10
    # R5 = R4 + R4 = 20
    # -----------------------------------------

    program = [
        encode_addi(1, 0, 5),        # R1 = 5
        encode_addi(2, 0, 10),       # R2 = 10
        encode_add(3, 1, 2),         # R3 = 15
        encode_addi(4, 3, -5),       # R4 = 10
        encode_add(5, 4, 4),         # R5 = 20
        0                            # NOP
    ]

    load_program(dut, program)

    # Run enough cycles
    for _ in range(10):
        await RisingEdge(dut.clk)

    # -----------------------------------------
    # REGISTER CHECKS
    # -----------------------------------------

    assert read_reg(dut, 0) == 0, "R0 must always be zero"
    assert read_reg(dut, 1) == 5, f"R1 incorrect: {read_reg(dut,1)}"
    assert read_reg(dut, 2) == 10, f"R2 incorrect: {read_reg(dut,2)}"
    assert read_reg(dut, 3) == 15, f"R3 incorrect: {read_reg(dut,3)}"
    assert read_reg(dut, 4) == 10, f"R4 incorrect: {read_reg(dut,4)}"
    assert read_reg(dut, 5) == 20, f"R5 incorrect: {read_reg(dut,5)}"

    # -----------------------------------------
    # PC CHECK
    # -----------------------------------------
    assert int(dut.pc.value) == 4 * len(program), \
        f"PC incorrect: {int(dut.pc.value)}"

    # -----------------------------------------
    # RESET RE-TEST
    # -----------------------------------------
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    for i in range(32):
        assert read_reg(dut, i) == 0, f"Register R{i} not cleared on reset"

