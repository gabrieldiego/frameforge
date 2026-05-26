import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.clear.value = 0
    dut.luma_rem.value = 16
    dut.cb_rem.value = 16
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def collect_symbols(dut, backpressure=False, max_cycles=256):
    symbols = []
    held = None
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    for cycle in range(max_cycles):
        dut.m_axis_ready.value = 0 if backpressure and (cycle % 5 == 3) else 1
        await ReadOnly()
        if int(dut.m_axis_valid.value) == 1:
            current = (
                int(dut.m_axis_kind.value),
                int(dut.m_axis_bin.value),
                int(dut.m_axis_lps.value),
                int(dut.m_axis_mps.value),
                int(dut.m_axis_last.value),
            )
            if int(dut.m_axis_ready.value) == 0:
                if held is None:
                    held = current
                else:
                    assert current == held
            else:
                symbols.append(current)
                held = None
                if current[-1] == 1:
                    return symbols
        else:
            held = None
        await Timer(1, unit="ps")
        await RisingEdge(dut.clk)

    raise AssertionError("symbolizer did not finish")


@cocotb.test()
async def cabac_8x8_symbolizer_streams_symbols(dut):
    await reset_dut(dut)
    symbols = await collect_symbols(dut)
    assert len(symbols) > 10
    assert symbols[-1][-1] == 1


@cocotb.test()
async def cabac_8x8_symbolizer_holds_symbols_under_backpressure(dut):
    await reset_dut(dut)
    stalled = await collect_symbols(dut, backpressure=True)

    await Timer(1, unit="ps")
    await reset_dut(dut)
    unstalled = await collect_symbols(dut, backpressure=False)

    assert stalled == unstalled
