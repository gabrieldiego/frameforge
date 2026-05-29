import json
import subprocess
import tempfile
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge

SYMBOL_BIN_CTX = 2
CTX_QT_CBF_Y_0 = 5
CTX_CCLM_MODE_FLAG = 13


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.start.value = 0
    dut.abs_level.value = 0
    dut.negative.value = 0
    dut.log2_tb_size.value = 3
    dut.m_axis_ready.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def collect_symbols(dut, abs_level, negative, log2_tb_size=3):
    dut.abs_level.value = abs_level
    dut.negative.value = int(negative)
    dut.log2_tb_size.value = log2_tb_size
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


def _ctx_id(data):
    return (data >> 8) & 0x1F


def _load_rust_semantic_symbols(width, height, y):
    with tempfile.TemporaryDirectory(prefix="frameforge-residual-vector-") as tmpdir:
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
    return vector, symbols


def rust_luma_residual_symbols(width, height, y):
    vector, symbols = _load_rust_semantic_symbols(width, height, y)
    start = None
    for index, (kind, data) in enumerate(symbols):
        if kind == SYMBOL_BIN_CTX and _ctx_id(data) == CTX_QT_CBF_Y_0 and (data & 1):
            start = index + 1
            break
    assert start is not None, "reference vector does not contain nonzero luma residual syntax"

    end = len(symbols)
    for index in range(start, len(symbols)):
        kind, data = symbols[index]
        if kind == 0:
            end = index + 1
            break
        if kind == SYMBOL_BIN_CTX and _ctx_id(data) == CTX_CCLM_MODE_FLAG:
            end = index
            break
    residual_symbols = symbols[start:end]
    residual = [
        (kind, data, int(index == len(residual_symbols) - 1))
        for index, (kind, data) in enumerate(residual_symbols)
    ]
    return vector, residual


@cocotb.test()
async def residual_dc_symbolizer_emits_zero_dc_subset(dut):
    await reset(dut)
    symbols = await collect_symbols(dut, 0, False)
    assert symbols[-1][2] == 1


@cocotb.test()
async def residual_dc_symbolizer_emits_remainder_subset(dut):
    await reset(dut)
    vector, expected = rust_luma_residual_symbols(8, 8, 64)
    observed = await collect_symbols(
        dut,
        int(vector["luma_dc_abs_level"]),
        bool(vector["luma_dc_negative"]),
    )
    assert observed == expected, (observed, expected)


@cocotb.test()
async def residual_dc_symbolizer_selects_16x16_last_sig_contexts(dut):
    await reset(dut)
    vector, expected = rust_luma_residual_symbols(16, 16, 64)
    symbols = await collect_symbols(
        dut,
        int(vector["luma_dc_abs_level"]),
        bool(vector["luma_dc_negative"]),
        log2_tb_size=4,
    )
    assert symbols == expected, (symbols, expected)
