from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import cocotb


BODY_GENERATED = 0


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def stream_cabac_bytes(dut, max_cycles=128):
    observed = []
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    for _ in range(max_cycles):
        if int(dut.m_axis_valid.value) == 1:
            observed.append(int(dut.m_axis_data.value))
            if int(dut.m_axis_last.value) == 1:
                await RisingEdge(dut.clk)
                return bytes(observed)
        await RisingEdge(dut.clk)

    raise AssertionError("CABAC body stream did not finish")


@cocotb.test()
async def cabac_body_generates_8x8_black_payload(dut):
    await reset_dut(dut)
    dut.body_kind.value = BODY_GENERATED
    dut.coded_width.value = 8
    dut.coded_height.value = 8
    dut.luma_rem.value = 16
    dut.cb_rem.value = 16
    dut.cr_rem.value = 16
    await Timer(1, unit="ns")

    observed = await stream_cabac_bytes(dut)
    assert int(dut.stream_bit_count.value) > 0
    assert int(dut.stream_byte_count.value) == len(observed)
    assert observed != b""


@cocotb.test()
async def ctu_geometries_generate_nonempty_cabac_streams(dut):
    for width, height in [(16, 16), (16, 32), (32, 16), (32, 32), (16, 64), (64, 16)]:
        await reset_dut(dut)
        dut.body_kind.value = BODY_GENERATED
        dut.coded_width.value = width
        dut.coded_height.value = height
        dut.luma_rem.value = 16
        dut.cb_rem.value = 16
        dut.cr_rem.value = 16
        await Timer(1, unit="ns")

        assert int(dut.stream_bit_count.value) > 0
        assert int(dut.stream_byte_count.value) > 0


@cocotb.test()
async def cabac_body_generates_64x64_partition_payload(dut):
    await reset_dut(dut)
    dut.body_kind.value = BODY_GENERATED
    dut.coded_width.value = 64
    dut.coded_height.value = 64
    dut.luma_rem.value = 16
    dut.cb_rem.value = 16
    dut.cr_rem.value = 16
    await Timer(1, unit="ns")

    assert int(dut.stream_bit_count.value) > 0
    assert int(dut.stream_byte_count.value) > 0
    assert await stream_cabac_bytes(dut) != b""


@cocotb.test()
async def cabac_body_generates_rectangular_64_sample_partition_payloads(dut):
    for width, height in [(64, 32), (32, 64)]:
        await reset_dut(dut)
        dut.body_kind.value = BODY_GENERATED
        dut.coded_width.value = width
        dut.coded_height.value = height
        dut.luma_rem.value = 16
        dut.cb_rem.value = 16
        dut.cr_rem.value = 16
        await Timer(1, unit="ns")

        assert int(dut.stream_bit_count.value) > 0
        assert int(dut.stream_byte_count.value) > 0
        assert await stream_cabac_bytes(dut) != b""
