import json
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


SYMBOL_BIN_EP = 0
SYMBOL_BIN_CTX = 2
CTX_QT_CBF_Y_0 = 5


def ctx_id(data):
    return (data >> 8) & 0x1F


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.raw_symbol_valid.value = 0
    dut.raw_symbol_kind.value = 0
    dut.raw_symbol_data.value = 0
    dut.raw_symbol_last.value = 0
    dut.ctu_valid.value = 0
    dut.ctu_x.value = 0
    dut.ctu_y.value = 0
    dut.ctu_visible_width.value = 16
    dut.ctu_visible_height.value = 16
    dut.ctu_luma_dc_abs_level.value = 0
    dut.ctu_luma_dc_negative.value = 0
    dut.ctu_luma_only.value = 1
    dut.ctu_last.value = 1
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@lru_cache(maxsize=None)
def load_rust_semantic_prefix(width, height, y):
    with tempfile.TemporaryDirectory(prefix="frameforge-syntax-prefix-") as tmpdir:
        tmp = Path(tmpdir)
        luma_samples = width * height
        chroma_samples = luma_samples // 4
        input_yuv = tmp / "input.yuv"
        output_json = tmp / "cabac.json"
        input_yuv.write_bytes(bytes([y] * luma_samples + [128] * chroma_samples * 2))
        subprocess.run(
            [
                "cargo",
                "run",
                "--quiet",
                "--",
                "vvc-cabac-vector-dump",
                "--input",
                str(input_yuv),
                "--output",
                str(output_json),
                "--frames",
                "1",
                "--width",
                str(width),
                "--height",
                str(height),
                "--format",
                "yuv420p8",
            ],
            cwd=Path(__file__).resolve().parents[1],
            check=True,
        )
        vector = json.loads(output_json.read_text())

    raw_symbols = bytes.fromhex(vector["semantic_symbols_hex"])
    symbols = []
    for offset in range(0, len(raw_symbols), vector["symbol_record_bytes"]):
        kind = raw_symbols[offset]
        data = int.from_bytes(raw_symbols[offset + 1 : offset + 5], "big")
        symbols.append((kind, data))
        if kind == SYMBOL_BIN_CTX and ctx_id(data) == CTX_QT_CBF_Y_0 and (data & 1) == 0:
            break
        if kind == SYMBOL_BIN_EP:
            break
    return {
        "symbols": symbols,
        "luma_dc_abs_level": int(vector["luma_dc_abs_level"]),
        "luma_dc_negative": bool(vector["luma_dc_negative"]),
    }


async def collect_luma_prefix(dut, width, height, abs_level, negative):
    dut.ctu_visible_width.value = width
    dut.ctu_visible_height.value = height
    dut.ctu_luma_dc_abs_level.value = abs_level
    dut.ctu_luma_dc_negative.value = int(negative)
    dut.ctu_luma_only.value = 1
    dut.ctu_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ctu_valid.value = 0

    observed = []
    for _ in range(64):
        await ReadOnly()
        if int(dut.m_axis_valid.value) == 1:
            observed.append((int(dut.m_axis_kind.value), int(dut.m_axis_data.value)))
            if int(dut.m_axis_last.value) == 1:
                return observed
        await Timer(1, unit="ps")
        await RisingEdge(dut.clk)
    raise AssertionError("syntax frontend did not finish luma prefix")


@cocotb.test()
async def syntax_frontend_forwards_raw_symbols(dut):
    await reset(dut)

    dut.raw_symbol_valid.value = 1
    dut.raw_symbol_kind.value = 2
    dut.raw_symbol_data.value = 0x1234
    dut.raw_symbol_last.value = 1
    await Timer(1, unit="ns")

    assert int(dut.raw_symbol_ready.value) == 1
    assert int(dut.ctu_ready.value) == 0
    assert int(dut.m_axis_valid.value) == 1
    assert int(dut.m_axis_kind.value) == 2
    assert int(dut.m_axis_data.value) == 0x1234
    assert int(dut.m_axis_last.value) == 1


@cocotb.test()
async def syntax_frontend_generates_luma_prefix_from_ctu_parameters(dut):
    cases = [
        (8, 8, 0),
        (8, 8, 96),
        (8, 8, 128),
        (8, 16, 64),
        (16, 8, 64),
        (16, 16, 0),
        (16, 16, 32),
        (16, 16, 64),
        (16, 16, 96),
        (16, 16, 128),
        (24, 16, 64),
        (16, 24, 64),
        (24, 24, 64),
        (24, 16, 0),
        (24, 8, 64),
        (16, 24, 0),
        (8, 24, 64),
        (24, 24, 0),
        (24, 24, 128),
        (64, 64, 64),
    ]
    for width, height, y in cases:
        await reset(dut)
        vector = load_rust_semantic_prefix(width, height, y)
        observed = await collect_luma_prefix(
            dut,
            width,
            height,
            vector["luma_dc_abs_level"],
            vector["luma_dc_negative"],
        )
        expected = vector["symbols"]
        assert observed == expected, (width, height, y, observed, expected)
        await Timer(1, unit="ps")
