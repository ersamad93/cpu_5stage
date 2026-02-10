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

