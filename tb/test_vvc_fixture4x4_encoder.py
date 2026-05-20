import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


@cocotb.test()
async def vvc_fixture4x4_encoder_emits_fixed_vtm_accepted_stream(dut):
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
        0x79,
        0x00,
        0x0B,
        0x02,
        0x00,
        0x80,
        0x00,
        0x42,
        0x44,
        0xEE,
        0xD5,
        0x01,
        0xF4,
        0x46,
        0xE8,
        0x84,
        0x68,
        0x84,
        0x24,
        0x61,
        0x36,
        0x28,
        0xC5,
        0x43,
        0x06,
        0x80,
        0xAB,
        0x8F,
        0xE0,
        0xAC,
        0x10,
        0x20,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x81,
        0x00,
        0x02,
        0x44,
        0x8A,
        0x42,
        0x00,
        0xC7,
        0xB2,
        0x14,
        0x59,
        0x45,
        0x94,
        0x58,
        0x80,
        0x00,
        0x00,
        0x01,
        0x00,
        0x41,
        0xC4,
        0x00,
        0x70,
        0x80,
        0x62,
        0xF5,
        0xB7,
        0xEB,
        0xCB,
        0x1F,
        0x80,
    ]
    observed = []
    if dut.m_axis_valid.value == 1:
        observed.append(int(dut.m_axis_data.value))

    for cycle in range(120):
        await RisingEdge(dut.clk)
        if cycle == 0:
            dut.start.value = 0
        await ReadOnly()
        if dut.m_axis_valid.value == 1:
            observed.append(int(dut.m_axis_data.value))
            if dut.m_axis_last.value == 1:
                break

    assert observed == expected
