import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


TEMP_BLACK_444_WIDTH = 64
TEMP_BLACK_444_HEIGHT = 64
TEMP_BLACK_444_BYTES = TEMP_BLACK_444_WIDTH * TEMP_BLACK_444_HEIGHT * 3


def temporary_black_444_payload():
    return bytes(TEMP_BLACK_444_BYTES)


def output_path():
    return os.environ.get("FRAMEFORGE_RTL_AV2_ENCODER_OUT_1F") or os.environ.get(
        "FRAMEFORGE_RTL_AV2_ENCODER_OUT"
    )


def recon_path():
    return os.environ.get("FRAMEFORGE_RTL_AV2_ENCODER_RECON_OUT_1F") or os.environ.get(
        "FRAMEFORGE_RTL_AV2_ENCODER_RECON_OUT"
    )


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.visible_width.value = TEMP_BLACK_444_WIDTH
    dut.visible_height.value = TEMP_BLACK_444_HEIGHT
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


async def collect_until_last(dut, max_cycles=TEMP_BLACK_444_BYTES + 128):
    observed = bytearray()
    for _ in range(max_cycles):
        await ReadOnly()
        if int(dut.m_axis_valid.value):
            observed.append(int(dut.m_axis_data.value))
            last = int(dut.m_axis_last.value)
            await RisingEdge(dut.clk)
            if last:
                await ReadOnly()
                assert int(dut.busy.value) == 0
                return bytes(observed)
        else:
            await RisingEdge(dut.clk)
    raise AssertionError("timed out waiting for AV2 temporary black-frame payload")


def write_optional_artifacts(payload):
    for path in (output_path(), recon_path()):
        if not path:
            continue
        out = Path(path)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(payload)


@cocotb.test()
async def av2_encoder_emits_temporary_black_64x64_444_payload(dut):
    await reset_dut(dut)
    await start_encoder(dut)

    payload = await collect_until_last(dut)
    expected = temporary_black_444_payload()
    assert len(payload) == len(expected), f"payload length {len(payload)} != {len(expected)}"
    first_nonzero = next((idx for idx, value in enumerate(payload) if value != 0), None)
    assert first_nonzero is None, f"payload byte {first_nonzero} is {payload[first_nonzero]:02x}"
    assert int(dut.s_axis_ready.value) == 0
    assert int(dut.input_error.value) == 0
    write_optional_artifacts(payload)


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
    assert int(dut.busy.value) == 1
    assert int(dut.m_axis_valid.value) == 1
    assert int(dut.input_error.value) == 0


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
