import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


def palette_symbols():
    return [
        (0x1 << 28) | (1 << 24) | (2 << 16),
        (0x2 << 28) | 10,
        (0x2 << 28) | 200,
        (0x4 << 28) | 20,
        (0x4 << 28) | 210,
        (0x5 << 28) | 30,
        (0x5 << 28) | 220,
        (0x3 << 28) | 0,
        (0x3 << 28) | 1,
        (0x3 << 28) | 0,
        (0x3 << 28) | 1,
    ]


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    if hasattr(dut, "clear"):
        dut.clear.value = 0
    dut.enable.value = 1
    if hasattr(dut, "mode_palette_444"):
        dut.mode_palette_444.value = 1
        dut.visible_width.value = 8
        dut.visible_height.value = 8
        dut.luma_rem.value = 0
        dut.cb_rem.value = 0
        dut.cr_rem.value = 0
    dut.coded_width.value = 8
    dut.coded_height.value = 8
    dut.symbol_count.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def drive_and_collect(dut, symbols, backpressure=False, max_cycles=512):
    observed = []
    index = 0
    saw_last = False
    dut.symbol_count.value = len(symbols)

    for cycle in range(max_cycles):
        dut.m_axis_ready.value = 0 if backpressure and (cycle % 5 == 2) else 1
        if index < len(symbols) and int(dut.s_axis_ready.value):
            dut.s_axis_valid.value = 1
            dut.s_axis_data.value = symbols[index]
            dut.s_axis_last.value = index == len(symbols) - 1
        else:
            dut.s_axis_valid.value = 0
            dut.s_axis_last.value = 0

        await ReadOnly()
        if int(dut.s_axis_valid.value) and int(dut.s_axis_ready.value):
            index += 1
        if int(dut.m_axis_valid.value):
            if int(dut.m_axis_ready.value):
                observed.append(int(dut.m_axis_data.value))
                saw_last = int(dut.m_axis_last.value) == 1
                if saw_last:
                    await RisingEdge(dut.clk)
                    return bytes(observed)
        await RisingEdge(dut.clk)

    raise AssertionError("palette CABAC stream did not finish")


@cocotb.test()
async def palette_cabac_streams_symbols_to_bytes(dut):
    await reset_dut(dut)
    observed = await drive_and_collect(dut, palette_symbols())
    assert observed
    assert int(dut.stream_last_byte_bits.value) in range(8)


@cocotb.test()
async def palette_cabac_holds_output_under_backpressure(dut):
    symbols = palette_symbols()

    await reset_dut(dut)
    unstalled = await drive_and_collect(dut, symbols, backpressure=False)

    await reset_dut(dut)
    stalled = await drive_and_collect(dut, symbols, backpressure=True)

    assert stalled == unstalled
