import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.visible_width.value = 64
    dut.visible_height.value = 64
    dut.chroma_format_idc.value = 1
    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_stream(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    await RisingEdge(dut.clk)


async def send_byte(dut, value, last=False):
    dut.s_axis_data.value = value
    dut.s_axis_last.value = int(last)
    dut.s_axis_valid.value = 1
    while True:
        await ReadOnly()
        ready = int(dut.s_axis_ready.value)
        await RisingEdge(dut.clk)
        if ready:
            break
    dut.s_axis_valid.value = 0
    dut.s_axis_last.value = 0


async def collect_until_last(dut, max_cycles=128):
    observed = []
    for _ in range(max_cycles):
        await ReadOnly()
        if int(dut.m_axis_valid.value):
            last = int(dut.m_axis_last.value)
            observed.append((int(dut.m_axis_data.value), last))
            if last:
                await RisingEdge(dut.clk)
                await ReadOnly()
                assert int(dut.busy.value) == 0
                return observed
        await RisingEdge(dut.clk)
    raise AssertionError("timed out waiting for AV2 encoder output")


@cocotb.test()
async def av2_encoder_passes_bytes_until_last(dut):
    await reset_dut(dut)
    await start_stream(dut)

    async def sender():
        for index, value in enumerate([0x12, 0x34, 0x56]):
            await send_byte(dut, value, last=(index == 2))

    cocotb.start_soon(sender())
    observed = await collect_until_last(dut)
    assert observed == [(0x12, 0), (0x34, 0), (0x56, 1)]


@cocotb.test()
async def av2_encoder_waits_for_start(dut):
    await reset_dut(dut)
    await ReadOnly()
    assert int(dut.s_axis_ready.value) == 0
    assert int(dut.busy.value) == 0

    await RisingEdge(dut.clk)
    await start_stream(dut)
    await ReadOnly()
    assert int(dut.busy.value) == 1
    assert int(dut.input_error.value) == 0


@cocotb.test()
async def av2_encoder_reports_invalid_geometry(dut):
    await reset_dut(dut)
    dut.visible_width.value = 0
    await start_stream(dut)
    await ReadOnly()
    assert int(dut.busy.value) == 0
    assert int(dut.input_error.value) == 1
