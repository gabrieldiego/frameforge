import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.enable.value = 1
    dut.cu_active_mask.value = (1 << 64) - 1
    dut.cu_index.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_sample.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    dut.luma_samples.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def residual_stream_emits_quantized_packets(dut):
    await reset(dut)
    assert int(dut.cu_active.value) == 1

    for index in range(16):
        while int(dut.s_axis_ready.value) != 1:
            await RisingEdge(dut.clk)
        dut.s_axis_valid.value = 1
        dut.s_axis_sample.value = 64
        dut.s_axis_last.value = index == 15
        await RisingEdge(dut.clk)
    dut.s_axis_valid.value = 0
    dut.s_axis_last.value = 0

    observed = []
    for _ in range(16):
        await ReadOnly()
        if int(dut.m_axis_valid.value) == 1:
            observed.append(
                (
                    int(dut.m_axis_kind.value),
                    int(dut.m_axis_data.value),
                    int(dut.m_axis_last.value),
                )
            )
            if int(dut.m_axis_last.value) == 1:
                break
        await RisingEdge(dut.clk)

    expected = [
        (1, 7, 0),
        (2, 0x40404040, 0),
        (3, 0x40404040, 0),
        (4, 0x40404040, 0),
        (5, 0x40404000, 0),
        (6, 0, 0),
        (7, 0, 0),
        (8, 0, 0),
        (9, 1, 0),
        (10, 0, 0),
        (11, 1, 0),
        (12, 5, 0),
        (13, 1, 1),
    ]
    assert observed == expected, (observed, expected)
