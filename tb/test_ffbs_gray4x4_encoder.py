import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


@cocotb.test()
async def ffbs_encoder_matches_rust_format_for_4x4_gray(dut):
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

    samples = list(range(16))
    for index, sample in enumerate(samples):
        dut.s_axis_valid.value = 1
        dut.s_axis_data.value = sample
        dut.s_axis_last.value = index == len(samples) - 1
        await RisingEdge(dut.clk)

    dut.s_axis_valid.value = 0
    dut.s_axis_last.value = 0

    expected = [
        0x46,
        0x46,
        0x42,
        0x53,
        0x01,
        0x01,
        0x00,
        0x04,
        0x00,
        0x04,
        0x01,
        0x00,
        0x00,
        0x00,
        0x10,
        *samples,
    ]
    observed = []

    for _ in range(80):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if dut.m_axis_valid.value == 1:
            observed.append(int(dut.m_axis_data.value))
            if dut.m_axis_last.value == 1:
                break

    assert observed == expected
