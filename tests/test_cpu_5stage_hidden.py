
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def setup_dut(dut):
    """Initialize clock and reset the DUT"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    dut.instr.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_cpu_exhaustive_forwarding(dut):
    """Exhaustive test for data hazards and forwarding"""
    await setup_dut(dut)

    # Pre-load Register File via backdoor to avoid X-states
    # Note: R1=10, R2=20
    dut.rf[1].value = 10
    dut.rf[2].value = 20
    await RisingEdge(dut.clk)

    # --- Program Macro ---
    # 1. ADD R3, R1, R2  -> R3 = 30
    # 2. ADD R4, R3, R1  -> R4 = 40 (Forward from EX/MEM)
    # 3. ADD R5, R4, R3  -> R5 = 70 (Forward from MEM/WB)
    # 4. ADD R6, R5, R0  -> R6 = 70
    instructions = [
        0x00221820, # ADD R3, R1, R2
        0x00612020, # ADD R4, R3, R1
        0x00832820, # ADD R5, R4, R3
        0x00A03020, # ADD R6, R5, R0
        0x00000000, # NOP
        0x00000000  # NOP
    ]

    # Feed instructions
    for instr_hex in instructions:
        dut.instr.value = instr_hex
        await RisingEdge(dut.clk)

    # Wait for the last instruction to clear the WB stage
    for _ in range(5):
        await RisingEdge(dut.clk)

    # --- Verification ---
    results = {
        3: 30,
        4: 40,
        5: 70,
        6: 70
    }

    for reg_idx, expected in results.items():
        actual = dut.rf[reg_idx].value
        if actual.is_resolvable:
            actual_int = actual.integer
            assert actual_int == expected, f"Reg R{reg_idx} failed: Expected {expected}, got {actual_int}"
            dut._log.info(f"Reg R{reg_idx} passed: {actual_int}")
        else:
            raise ValueError(f"Reg R{reg_idx} contains X/Z bits: {actual.binstr}")

    dut._log.info("All exhaustive tests passed with forwarding!")    

@cocotb.test()
async def ultra_comprehensive_test(dut):
    """Stress testing hazards, priority, and memory atomicity."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    dut.rst.value = 1
    await Timer(25, "ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    async def tick(instr=0, rdata=0):
        dut.instr.value = instr
        dut.d_rdata.value = rdata
        await RisingEdge(dut.clk)

    # CORNER CASE 1: The "Waterfall" Priority Forwarding
    # We write to R1 three times in a row, then use it.
    # The CPU must only see the absolute latest value.
    await tick(0x2001000A) # ADDI R1, R0, 10
    await tick(0x20010014) # ADDI R1, R0, 20
    await tick(0x2001001E) # ADDI R1, R0, 30
    await tick(0x00211020) # ADD  R2, R1, R1 (Should be 30 + 30 = 60)
    for _ in range(5): await tick()
    assert dut.rf[2].value == 60, f"Waterfall Forwarding Failed! Got {int(dut.rf[2].value)}"

    # CORNER CASE 2: The Load-Use Interlock "Trap"
    # LW followed by an instruction that uses it, followed by one that doesn't.
    # Verifies the stall doesn't accidentally delay unrelated instructions.
    await tick(0x8C030004, rdata=100) # LW R3, 4(R0) -> returns 100
    await tick(0x00632020)           # ADD R4, R3, R3 (Requires stall, result 200)
    await tick(0x20050001)           # ADDI R5, R0, 1 (Unrelated)
    for _ in range(7): await tick()
    assert dut.rf[4].value == 200, "Load-Use Stall failed!"
    assert dut.rf[5].value == 1, "Stall over-extended to unrelated instructions!"

    # CORNER CASE 3: Register 0 Immortality
    # Attempting to write to R0 via every possible path (ALU, Memory)
    await tick(0x2000FFFF) # ADDI R0, R0, -1
    await tick(0x8C000000, rdata=0xFFFFFFFF) # LW R0, 0(R0)
    for _ in range(5): await tick()
    assert dut.rf[0].value == 0, "R0 was corrupted!"

    # CORNER CASE 4: Simultaneous SW and RAW Hazard
    # Store a value that was just calculated.
    await tick(0x200A0005) # ADDI R10, R0, 5
    await tick(0xAC0A0000) # SW R10, 0(R0) -> Should forward R10 from EX to MEM
    await tick()
    await RisingEdge(dut.clk)
    assert dut.d_wdata.value == 5, "Forwarding to Store-Data failed!"

    dut._log.info("ULTRA COMPREHENSIVE TESTING COMPLETE: STATUS PASSED")   
    
# CRITICAL: Pytest wrapper function
def test_cpu_5stage_hidden_runner():
    import os
    from pathlib import Path
    from cocotb_tools.runner import get_runner
    
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    
    sources = [proj_path / "sources/cpu_5stage.sv"]
    
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="cpu_5stage",
        always=True,
    )
    
    runner.test(
        hdl_toplevel="cpu_5stage",
        test_module="test_cpu_5stage_hidden",
   )
if __name__ == "__main__":
    test_cpu_5stage_hidden_runner()
