import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_value.value = 0
    dut.s_axis_bit_count.value = 0
    dut.s_axis_flush_zero.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def send_bits(dut, value, bit_count, flush=False, last=False):
    dut.s_axis_value.value = value
    dut.s_axis_bit_count.value = bit_count
    dut.s_axis_flush_zero.value = int(flush)
    dut.s_axis_last.value = int(last)
    dut.s_axis_valid.value = 1
    while True:
        await ReadOnly()
        ready = int(dut.s_axis_ready.value)
        await RisingEdge(dut.clk)
        if ready:
            break
    dut.s_axis_valid.value = 0
    dut.s_axis_flush_zero.value = 0
    dut.s_axis_last.value = 0


async def collect_bytes(dut, expected_count, max_cycles=128):
    observed = []
    for _ in range(max_cycles):
        await ReadOnly()
        if int(dut.m_axis_valid.value):
            observed.append(int(dut.m_axis_data.value))
        await RisingEdge(dut.clk)
        if len(observed) == expected_count:
            return bytes(observed)
    raise AssertionError("timed out collecting bytes")


@cocotb.test()
async def cabac_bit_writer_packs_msb_first_bytes(dut):
    await reset_dut(dut)
    await send_bits(dut, 0b1010_1100, 8)
    observed = await collect_bytes(dut, 1)
    assert observed == bytes([0b1010_1100])
    assert int(dut.total_bit_count.value) == 8
    assert int(dut.partial_bit_count.value) == 0


@cocotb.test()
async def cabac_bit_writer_carries_partial_bits_between_commands(dut):
    await reset_dut(dut)
    await send_bits(dut, 0b101, 3)
    await send_bits(dut, 0b00110, 5)
    observed = await collect_bytes(dut, 1)
    assert observed == bytes([0b1010_0110])
    assert int(dut.total_bit_count.value) == 8


@cocotb.test()
async def cabac_bit_writer_flush_zero_pads_partial_byte(dut):
    await reset_dut(dut)
    await send_bits(dut, 0b101, 3)
    await send_bits(dut, 0, 0, flush=True)
    observed = await collect_bytes(dut, 1)
    assert observed == bytes([0b1010_0000])
    assert int(dut.partial_bit_count.value) == 0


@cocotb.test()
async def cabac_bit_writer_holds_output_under_backpressure(dut):
    await reset_dut(dut)
    dut.m_axis_ready.value = 0
    await send_bits(dut, 0x5A, 8)
    for _ in range(12):
        await ReadOnly()
        if int(dut.m_axis_valid.value):
            assert int(dut.m_axis_data.value) == 0x5A
        await RisingEdge(dut.clk)
    dut.m_axis_ready.value = 1
    observed = await collect_bytes(dut, 1)
    assert observed == bytes([0x5A])


@cocotb.test()
async def cabac_bit_writer_marks_last_flushed_byte_and_done(dut):
    await reset_dut(dut)
    await send_bits(dut, 0b101, 3)
    await send_bits(dut, 0, 0, flush=True, last=True)

    for _ in range(32):
        await ReadOnly()
        if int(dut.m_axis_valid.value):
            assert int(dut.m_axis_data.value) == 0b1010_0000
            assert int(dut.m_axis_last.value) == 1
        if int(dut.done.value):
            return
        await RisingEdge(dut.clk)
    raise AssertionError("bit writer did not assert done")
