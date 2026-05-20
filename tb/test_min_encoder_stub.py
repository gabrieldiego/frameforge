import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


@cocotb.test()
async def encoder_stub_ignores_input_and_emits_placeholder(dut):
    """Smoke test for the minimum RTL encoder shell."""

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst_n.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1

    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    dut.s_axis_valid.value = 1
    dut.s_axis_data.value = 0xDEADBEEF
    dut.s_axis_last.value = 1
    await RisingEdge(dut.clk)

    dut.s_axis_valid.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if dut.m_axis_valid.value == 1:
            assert dut.m_axis_data.value == 0x4646454E435F3031
            assert dut.m_axis_last.value == 1
            return

    assert False, "encoder stub did not emit placeholder packet"
