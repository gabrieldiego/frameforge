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
    dut.enable.value = 1
    dut.cu_active_mask.value = (1 << 64) - 1
    dut.cu_index.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_sample.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    dut.luma_samples.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def _ctx_id(data):
    return (data >> 8) & 0x1F


def rust_luma_residual_symbols(width, height, y):
    with tempfile.TemporaryDirectory(prefix="frameforge-residual-transform-vector-") as tmpdir:
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
    return [
        (kind, data, int(index == len(residual_symbols) - 1))
        for index, (kind, data) in enumerate(residual_symbols)
    ]


@cocotb.test()
async def residual_stream_emits_quantized_packets(dut):
    await reset(dut)
    assert int(dut.cu_active.value) == 1

    for index in range(64):
        while int(dut.s_axis_ready.value) != 1:
            await RisingEdge(dut.clk)
        dut.s_axis_valid.value = 1
        dut.s_axis_sample.value = 64
        dut.s_axis_last.value = index == 63
        await RisingEdge(dut.clk)
    dut.s_axis_valid.value = 0
    dut.s_axis_last.value = 0

    observed = []
    for _ in range(16):
        await ReadOnly()
        if int(dut.m_axis_valid.value) == 1:
            observed.append(
                (
                    int(dut.m_axis_kind.value),
                    int(dut.m_axis_data.value),
                    int(dut.m_axis_last.value),
                )
            )
            if int(dut.m_axis_last.value) == 1:
                break
        await RisingEdge(dut.clk)

    expected = rust_luma_residual_symbols(8, 8, 64)
    assert observed == expected, (observed, expected)
