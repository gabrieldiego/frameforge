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


async def collect_stream(dut, backpressure=False, max_cycles=512):
    observed = []
    held = None
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    for cycle in range(max_cycles):
        dut.m_axis_ready.value = 0 if backpressure and (cycle % 4 == 2) else 1
        await ReadOnly()
        if int(dut.m_axis_valid.value) == 1:
            current = (int(dut.m_axis_data.value), int(dut.m_axis_last.value))
            if int(dut.m_axis_ready.value) == 0:
                if held is None:
                    held = current
                else:
                    assert current == held
            else:
                observed.append(current[0])
                held = None
                if current[1] == 1:
                    return bytes(observed)
        else:
            held = None
        await Timer(1, unit="ps")
        await RisingEdge(dut.clk)
    raise AssertionError("8x8 stream body did not finish")


@cocotb.test()
async def cabac_8x8_stream_body_emits_nonempty_stream(dut):
    await reset_dut(dut)
    observed = await collect_stream(dut)
    assert observed != b""


@cocotb.test()
async def cabac_8x8_stream_body_handles_backpressure(dut):
    await reset_dut(dut)
    stalled = await collect_stream(dut, backpressure=True)
    await Timer(1, unit="ps")
    await reset_dut(dut)
    unstalled = await collect_stream(dut)
    assert stalled == unstalled, (stalled.hex(), unstalled.hex())
