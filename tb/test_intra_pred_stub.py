import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


@cocotb.test()
async def pass_through_respects_ready_valid(dut):
    """Basic AXI-stream-style handshake smoke test.

    TODO: compare future RTL block outputs with Rust/Python software golden
    models for block-level co-verification.
    """

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
    dut.s_axis_data.value = 0x1234
    dut.s_axis_last.value = 1
    await RisingEdge(dut.clk)
    await ReadOnly()

    assert dut.m_axis_valid.value == 1
    assert dut.m_axis_data.value == 0x1234
    assert dut.m_axis_last.value == 1
