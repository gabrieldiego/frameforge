import cocotb
from cocotb.clock import Clock
from cocotb.triggers import NextTimeStep, ReadOnly, RisingEdge


PKT_CU_START = 0x1
PKT_ENTRY_Y = 0x2
PKT_INDEX = 0x3
PKT_ENTRY_CB = 0x4
PKT_ENTRY_CR = 0x5


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.enable.value = 1
    dut.cu_selected.value = 1
    dut.s_axis_valid.value = 0
    dut.s_axis_y.value = 0
    dut.s_axis_cb.value = 0
    dut.s_axis_cr.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def send_sample(dut, y, cb, cr, last=False):
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.s_axis_ready.value) == 1:
            break
    await NextTimeStep()
    dut.s_axis_y.value = y
    dut.s_axis_cb.value = cb
    dut.s_axis_cr.value = cr
    dut.s_axis_last.value = int(last)
    dut.s_axis_valid.value = 1
    await RisingEdge(dut.clk)
    dut.s_axis_valid.value = 0
    dut.s_axis_last.value = 0


async def collect(dut, count):
    packets = []
    while len(packets) < count:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.m_axis_valid.value) == 1:
            packets.append(int(dut.m_axis_data.value))
    return packets


def kind(packet):
    return (packet >> 28) & 0xF


@cocotb.test()
async def palette_cu_symbolizer_streams_solid_cu(dut):
    await reset(dut)
    monitor = cocotb.start_soon(collect(dut, 4))
    for index in range(64):
        await send_sample(dut, 10, 20, 30, last=index == 63)
    packets = await monitor

    assert packets == [0x11010000, 0x2000000A, 0x40000014, 0x5000001E]


@cocotb.test()
async def palette_cu_symbolizer_streams_index_payload(dut):
    await reset(dut)
    monitor = cocotb.start_soon(collect(dut, 71))
    for index in range(64):
        if index % 2 == 0:
            await send_sample(dut, 10, 20, 30, last=index == 63)
        else:
            await send_sample(dut, 200, 210, 220, last=index == 63)
    packets = await monitor

    assert packets[:7] == [
        0x11020000,
        0x2000000A,
        0x200000C8,
        0x40000014,
        0x400000D2,
        0x5000001E,
        0x500000DC,
    ]
    assert [kind(packet) for packet in packets[7:]] == [PKT_INDEX] * 64


@cocotb.test()
async def palette_cu_symbolizer_marks_unselected_cu(dut):
    await reset(dut)
    dut.cu_selected.value = 0
    monitor = cocotb.start_soon(collect(dut, 1))
    for index in range(64):
        await send_sample(dut, 10, 20, 30, last=index == 63)
    packets = await monitor

    assert packets == [0x10000000]
