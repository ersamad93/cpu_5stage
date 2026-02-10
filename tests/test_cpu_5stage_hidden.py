import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

@cocotb.test()
async def test_cpu_forwarding(dut):
    """Verify that back-to-back ADDs work via forwarding"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset System
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    
    # Initialize RF
    dut.rf[1].value = 5
    dut.rf[2].value = 5

    # Instruction Stream:
    # 1. ADD R3, R1, R2  (Result 10)
    # 2. ADD R4, R3, R1  (Result 15) -> Requires Forwarding from EX/MEM
    # 3. ADD R5, R4, R3  (Result 25) -> Requires Forwarding from MEM/WB
    
    instructions = [0x00221820, 0x00612020, 0x00832820]
    
    for i in range(10): # Run for 10 cycles to clear pipeline
        if i < len(instructions):
            dut.instr.value = instructions[i]
        else:
            dut.instr.value = 0 # NOP
        await RisingEdge(dut.clk)

    # Final Checks
    r3 = dut.rf[3].value.integer
    r4 = dut.rf[4].value.integer
    r5 = dut.rf[5].value.integer

    dut._log.info(f"R3: {r3}, R4: {r4}, R5: {r5}")
    
    assert r3 == 10, f"R3 fail: {r3}"
    assert r4 == 15, f"R4 fail: {r4}" # This proves forwarding works!
    assert r5 == 25, f"R5 fail: {r5}"
    
    
    
    
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

