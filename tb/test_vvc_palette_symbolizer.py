import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.enable.value = 1
    dut.visible_width.value = 8
    dut.visible_height.value = 8
    dut.sample_valid.value = 0
    dut.sample_plane.value = 0
    dut.sample.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_plane.value = 0
    dut.s_axis_sample.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def send_plane(dut, plane, value, last=False):
    for index in range(64):
        while int(dut.s_axis_ready.value) != 1:
            await RisingEdge(dut.clk)
        dut.s_axis_valid.value = 1
        dut.s_axis_plane.value = plane
        dut.s_axis_sample.value = value
        dut.s_axis_last.value = last and index == 63
        await RisingEdge(dut.clk)
    dut.s_axis_valid.value = 0
    dut.s_axis_last.value = 0


@cocotb.test()
async def palette_symbolizer_streams_anchor_symbol(dut):
    await reset(dut)

    await send_plane(dut, 0, 10)
    await send_plane(dut, 1, 20)
    await send_plane(dut, 2, 30, last=True)
    await ReadOnly()

    assert int(dut.symbol_count.value) == 1
    assert int(dut.m_axis_valid.value) == 1
    assert int(dut.m_axis_data.value) == 0x000A141E
    assert int(dut.m_axis_last.value) == 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
