import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


VISIBLE_SAMPLES = 64
PKT_CU_START = 0x1
PKT_ENTRY = 0x2
PKT_INDEX = 0x3


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.enable.value = 1
    dut.ctu_coded_width.value = 8
    dut.ctu_coded_height.value = 8
    dut.cu_select_mask.value = 1 << 63
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


async def send_plane(dut, plane, value, last=False, samples=None):
    if samples is None:
        samples = VISIBLE_SAMPLES
    for index in range(samples):
        while int(dut.s_axis_ready.value) != 1:
            await RisingEdge(dut.clk)
        dut.s_axis_valid.value = 1
        dut.s_axis_plane.value = plane
        dut.s_axis_sample.value = value
        dut.s_axis_last.value = last and index == samples - 1
        await RisingEdge(dut.clk)
    dut.s_axis_valid.value = 0
    dut.s_axis_last.value = 0


async def monitor_symbols(dut, symbols, count):
    while len(symbols) < count:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.m_axis_valid.value) == 1:
            symbols.append(int(dut.m_axis_data.value))


def packet_kind(symbol):
    return (symbol >> 28) & 0xF


def packet_selected(symbol):
    return (symbol >> 24) & 0x1


def packet_entry_count(symbol):
    return (symbol >> 16) & 0xFF


@cocotb.test()
async def palette_symbolizer_streams_anchor_symbol(dut):
    await reset(dut)

    symbols = []
    monitor = cocotb.start_soon(monitor_symbols(dut, symbols, 2))
    await send_plane(dut, 0, 10)
    await send_plane(dut, 1, 20)
    await send_plane(dut, 2, 30, last=True)
    for _ in range(8):
        if len(symbols) >= 2:
            break
        await RisingEdge(dut.clk)
    monitor.cancel()

    assert int(dut.symbol_count.value) == 1
    assert symbols == [0x11010000, 0x200A141E], [hex(symbol) for symbol in symbols]
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")


@cocotb.test()
async def palette_symbolizer_marks_unselected_cu(dut):
    await reset(dut)
    dut.cu_select_mask.value = 0

    symbols = []
    monitor = cocotb.start_soon(monitor_symbols(dut, symbols, 1))
    await send_plane(dut, 0, 10)
    await send_plane(dut, 1, 20)
    await send_plane(dut, 2, 30, last=True)
    for _ in range(4):
        if len(symbols) >= 1:
            break
        await RisingEdge(dut.clk)
    monitor.cancel()

    assert symbols == [0x10000000]


@cocotb.test()
async def palette_symbolizer_marks_off_view_right_column_unselected(dut):
    await reset(dut)
    dut.ctu_coded_width.value = 16
    dut.ctu_coded_height.value = 16
    # Coding order for a 16x16 CTU is TL, TR, BL, BR. The right column is
    # fully off-picture for an 8x16 visible rectangle.
    dut.cu_select_mask.value = (1 << 63) | (1 << 61)

    symbols = []
    monitor = cocotb.start_soon(monitor_symbols(dut, symbols, 6))
    await send_plane(dut, 0, 10, samples=8 * 16)
    await send_plane(dut, 1, 20, samples=8 * 16)
    await send_plane(dut, 2, 30, last=True, samples=8 * 16)
    for _ in range(8):
        if len(symbols) >= 6:
            break
        await RisingEdge(dut.clk)
    monitor.cancel()

    assert int(dut.symbol_count.value) == 4
    selected = [packet_selected(symbol) for symbol in symbols if packet_kind(symbol) == PKT_CU_START]
    assert selected == [1, 0, 1, 0], selected


@cocotb.test()
async def palette_symbolizer_marks_off_view_bottom_row_unselected(dut):
    await reset(dut)
    dut.ctu_coded_width.value = 16
    dut.ctu_coded_height.value = 16
    # Coding order for a 16x16 CTU is TL, TR, BL, BR. The bottom row is
    # fully off-picture for a 16x8 visible rectangle.
    dut.cu_select_mask.value = (1 << 63) | (1 << 62)

    symbols = []
    monitor = cocotb.start_soon(monitor_symbols(dut, symbols, 6))
    await send_plane(dut, 0, 10, samples=16 * 8)
    await send_plane(dut, 1, 20, samples=16 * 8)
    await send_plane(dut, 2, 30, last=True, samples=16 * 8)
    for _ in range(8):
        if len(symbols) >= 6:
            break
        await RisingEdge(dut.clk)
    monitor.cancel()

    assert int(dut.symbol_count.value) == 4
    selected = [packet_selected(symbol) for symbol in symbols if packet_kind(symbol) == PKT_CU_START]
    assert selected == [1, 1, 0, 0], selected


@cocotb.test()
async def palette_symbolizer_streams_lossless_indices_for_multicolor_cu(dut):
    await reset(dut)

    y_samples = [10 if index % 2 == 0 else 200 for index in range(64)]
    cb_samples = [20 if index % 2 == 0 else 210 for index in range(64)]
    cr_samples = [30 if index % 2 == 0 else 220 for index in range(64)]
    symbols = []
    monitor = cocotb.start_soon(monitor_symbols(dut, symbols, 67))
    for sample in y_samples:
        await send_plane(dut, 0, sample, samples=1)
    for sample in cb_samples:
        await send_plane(dut, 1, sample, samples=1)
    for index, sample in enumerate(cr_samples):
        await send_plane(dut, 2, sample, last=index == len(cr_samples) - 1, samples=1)
    for _ in range(80):
        if len(symbols) >= 67:
            break
        await RisingEdge(dut.clk)
    monitor.cancel()

    assert packet_kind(symbols[0]) == PKT_CU_START
    assert packet_selected(symbols[0]) == 1
    assert packet_entry_count(symbols[0]) == 2, [hex(symbol) for symbol in symbols[:6]]
    assert symbols[1:3] == [0x200A141E, 0x20C8D2DC]
    assert [packet_kind(symbol) for symbol in symbols[3:]] == [PKT_INDEX] * 64
    expected_indices = []
    for y in range(8):
        if y % 2 == 0:
            x_iter = range(8)
        else:
            x_iter = range(7, -1, -1)
        for x in x_iter:
            expected_indices.append((y * 8 + x) % 2)
    assert [(symbol & 0xFF) for symbol in symbols[3:]] == expected_indices
