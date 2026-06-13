import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


def rtl_geometry():
    return (
        int(os.environ.get("RTL_VISIBLE_WIDTH", "64")),
        int(os.environ.get("RTL_VISIBLE_HEIGHT", "64")),
    )


async def reset_dut(dut):
    width, height = rtl_geometry()
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.visible_width.value = width
    dut.visible_height.value = height
    dut.chroma_format_idc.value = 3
    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_encoder(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


@cocotb.test()
async def av2_encoder_reports_unimplemented_tile_entropy(dut):
    await reset_dut(dut)
    await start_encoder(dut)
    await ReadOnly()

    assert int(dut.busy.value) == 0
    assert int(dut.s_axis_ready.value) == 0
    assert int(dut.m_axis_valid.value) == 0
    assert int(dut.m_axis_last.value) == 0
    assert int(dut.input_error.value) == 1


@cocotb.test()
async def av2_encoder_waits_for_start(dut):
    await reset_dut(dut)
    await ReadOnly()
    assert int(dut.s_axis_ready.value) == 0
    assert int(dut.m_axis_valid.value) == 0
    assert int(dut.busy.value) == 0

    await RisingEdge(dut.clk)
    await start_encoder(dut)
    await ReadOnly()
    assert int(dut.busy.value) == 0
    assert int(dut.m_axis_valid.value) == 0
    assert int(dut.input_error.value) == 1


@cocotb.test()
async def av2_encoder_reports_invalid_geometry(dut):
    await reset_dut(dut)
    dut.visible_width.value = 0
    await start_encoder(dut)
    await ReadOnly()
    assert int(dut.busy.value) == 0
    assert int(dut.input_error.value) == 1
    assert int(dut.m_axis_valid.value) == 0


@cocotb.test()
async def av2_encoder_reports_non_444_input_format(dut):
    await reset_dut(dut)
    dut.chroma_format_idc.value = 1
    await start_encoder(dut)
    await ReadOnly()
    assert int(dut.busy.value) == 0
    assert int(dut.input_error.value) == 1
    assert int(dut.m_axis_valid.value) == 0
