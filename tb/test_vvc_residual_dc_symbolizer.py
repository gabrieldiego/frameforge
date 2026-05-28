import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.start.value = 0
    dut.abs_level.value = 0
    dut.negative.value = 0
    dut.m_axis_ready.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def collect_symbols(dut, abs_level, negative):
    dut.abs_level.value = abs_level
    dut.negative.value = int(negative)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    symbols = []
    for _ in range(32):
        await ReadOnly()
        if int(dut.m_axis_valid.value) == 1:
            symbols.append(
                (
                    int(dut.m_axis_kind.value),
                    int(dut.m_axis_data.value),
                    int(dut.m_axis_last.value),
                )
            )
            if int(dut.m_axis_last.value) == 1:
                return symbols
        await RisingEdge(dut.clk)
    raise AssertionError("residual symbolizer did not finish")


@cocotb.test()
async def residual_dc_symbolizer_emits_zero_dc_subset(dut):
    await reset(dut)
    assert await collect_symbols(dut, 0, False) == [
        (2, 0x000, 0),
        (2, 0x100, 1),
    ]


@cocotb.test()
async def residual_dc_symbolizer_emits_remainder_subset(dut):
    await reset(dut)
    assert await collect_symbols(dut, 7, True) == [
        (2, 0x000, 0),
        (2, 0x100, 0),
        (2, 0x201, 0),
        (2, 0x301, 0),
        (2, 0x401, 0),
        (4, 0x082, 0),
        (0, 0x001, 1),
    ]
