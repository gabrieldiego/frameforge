import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
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


async def collect_until_done(dut, max_cycles=128):
    observed = []
    for _ in range(max_cycles):
        await ReadOnly()
        if int(dut.m_axis_valid.value):
            observed.append((int(dut.m_axis_data.value), int(dut.m_axis_last.value)))
        if int(dut.done.value):
            return observed
        await RisingEdge(dut.clk)
    raise AssertionError("timed out waiting for emulation prevention output")


async def send_sequence_and_collect(dut, values, max_cycles=128):
    observed = []
    sender_done = False

    async def sender():
        nonlocal sender_done
        for index, value in enumerate(values):
            await send_byte(dut, value, last=(index == len(values) - 1))
        sender_done = True

    cocotb.start_soon(sender())
    for _ in range(max_cycles):
        await ReadOnly()
        if int(dut.m_axis_valid.value):
            observed.append((int(dut.m_axis_data.value), int(dut.m_axis_last.value)))
        if sender_done and int(dut.done.value):
            return observed
        await RisingEdge(dut.clk)
    raise AssertionError("timed out collecting emulation prevention sequence")


@cocotb.test()
async def emulation_prevention_inserts_after_two_zeroes(dut):
    await reset_dut(dut)
    observed = await send_sequence_and_collect(dut, [0x00, 0x00, 0x01, 0x11])
    assert observed == [(0x00, 0), (0x00, 0), (0x03, 0), (0x01, 0), (0x11, 1)]


@cocotb.test()
async def emulation_prevention_does_not_insert_before_large_byte(dut):
    await reset_dut(dut)
    observed = await send_sequence_and_collect(dut, [0x00, 0x00, 0x04, 0x00])
    assert observed == [(0x00, 0), (0x00, 0), (0x04, 0), (0x00, 1)]
