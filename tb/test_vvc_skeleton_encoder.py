import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


@cocotb.test()
async def vvc_skeleton_encoder_matches_rust_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.m_axis_ready.value = 1

    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    dut.start.value = 1
    await RisingEdge(dut.clk)
    await ReadOnly()

    expected = [
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x71,
        0x80,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x79,
        0x80,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x81,
        0x80,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x41,
        0x80,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0xA9,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0xB1,
    ]
    observed = []
    if dut.m_axis_valid.value == 1:
        observed.append(int(dut.m_axis_data.value))

    for cycle in range(80):
        await RisingEdge(dut.clk)
        if cycle == 0:
            dut.start.value = 0
        await ReadOnly()
        if dut.m_axis_valid.value == 1:
            observed.append(int(dut.m_axis_data.value))
            if dut.m_axis_last.value == 1:
                break

    assert observed == expected
