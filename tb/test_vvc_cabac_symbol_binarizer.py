import json
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


SYMBOL_BIN_EP = 0
SYMBOL_BIN_TRM = 1
SYMBOL_BIN_CTX = 2
SYMBOL_BIN_CTX_DIRECT = 3
SYMBOL_BINS_EP = 4

CABAC_BIN_EP = 0
CABAC_BIN_TRM = 1
CABAC_BIN_CTX = 2
CABAC_BINS_EP = 3


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_kind.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def expected_binarized_record(kind, data, last):
    mapped_kind = {
        SYMBOL_BIN_TRM: CABAC_BIN_TRM,
        SYMBOL_BIN_CTX: CABAC_BIN_CTX,
        SYMBOL_BIN_CTX_DIRECT: CABAC_BIN_CTX,
        SYMBOL_BINS_EP: CABAC_BINS_EP,
    }.get(kind, CABAC_BIN_EP)
    return {
        "kind": mapped_kind,
        "bin": data & 1,
        "bins_pattern": data >> 6 if kind == SYMBOL_BINS_EP else data & 1,
        "bins_count": data & 0x3F if kind == SYMBOL_BINS_EP else 1,
        "ctx_valid": int(kind == SYMBOL_BIN_CTX),
        "ctx_id": (data >> 8) & 0x1F,
        "lps": (data >> 16) & 0x1FF,
        "mps": (data >> 25) & 1,
        "last": int(last),
    }


@lru_cache(maxsize=None)
def load_rust_semantic_symbols(width, height, y):
    with tempfile.TemporaryDirectory(prefix="frameforge-binarizer-vector-") as tmpdir:
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
    record_bytes = vector["symbol_record_bytes"]
    symbols = []
    for offset in range(0, len(raw_symbols), record_bytes):
        kind = raw_symbols[offset]
        data = int.from_bytes(raw_symbols[offset + 1 : offset + 5], "big")
        symbols.append((kind, data))
    return symbols


async def drive_symbols_and_collect(dut, symbols, stall_every=None, max_cycles=512):
    observed = []
    index = 0
    dut.s_axis_valid.value = 0

    for cycle in range(max_cycles):
        dut.m_axis_ready.value = 0 if stall_every and cycle % stall_every == stall_every - 1 else 1

        if index < len(symbols) and int(dut.s_axis_ready.value) == 1:
            kind, data = symbols[index]
            dut.s_axis_valid.value = 1
            dut.s_axis_kind.value = kind
            dut.s_axis_data.value = data
            dut.s_axis_last.value = index == len(symbols) - 1
        else:
            dut.s_axis_valid.value = 0
            dut.s_axis_last.value = 0

        await ReadOnly()

        if int(dut.s_axis_valid.value) == 1 and int(dut.s_axis_ready.value) == 1:
            index += 1

        if int(dut.m_axis_valid.value) == 1 and int(dut.m_axis_ready.value) == 1:
            observed.append(
                {
                    "kind": int(dut.m_axis_kind.value),
                    "bin": int(dut.m_axis_bin.value),
                    "bins_pattern": int(dut.m_axis_bins_pattern.value),
                    "bins_count": int(dut.m_axis_bins_count.value),
                    "ctx_valid": int(dut.m_axis_ctx_valid.value),
                    "ctx_id": int(dut.m_axis_ctx_id.value),
                    "lps": int(dut.m_axis_lps.value),
                    "mps": int(dut.m_axis_mps.value),
                    "last": int(dut.m_axis_last.value),
                }
            )
            if int(dut.m_axis_last.value) == 1:
                return observed

        await Timer(1, unit="ps")
        await RisingEdge(dut.clk)

    raise AssertionError("CABAC symbol binarizer did not finish")


@cocotb.test()
async def symbol_binarizer_maps_context_symbol_to_bin(dut):
    await reset(dut)

    dut.s_axis_valid.value = 1
    dut.s_axis_kind.value = 2
    dut.s_axis_data.value = 1 | (7 << 8) | (33 << 16) | (1 << 25)
    dut.s_axis_last.value = 1
    await RisingEdge(dut.clk)
    dut.s_axis_valid.value = 0
    await Timer(1, unit="ns")

    assert int(dut.m_axis_valid.value) == 1
    assert int(dut.m_axis_kind.value) == 2
    assert int(dut.m_axis_bin.value) == 1
    assert int(dut.m_axis_ctx_valid.value) == 1
    assert int(dut.m_axis_ctx_id.value) == 7
    assert int(dut.m_axis_lps.value) == 33
    assert int(dut.m_axis_mps.value) == 1
    assert int(dut.m_axis_last.value) == 1


@cocotb.test()
async def symbol_binarizer_matches_rust_semantic_vectors(dut):
    cases = [
        (8, 8, 0),
        (8, 8, 64),
        (8, 8, 128),
        (16, 16, 0),
        (16, 16, 64),
        (24, 16, 64),
        (16, 24, 64),
        (32, 32, 0),
        (32, 32, 64),
    ]
    for width, height, y in cases:
        await reset(dut)
        symbols = load_rust_semantic_symbols(width, height, y)
        expected = [
            expected_binarized_record(kind, data, index == len(symbols) - 1)
            for index, (kind, data) in enumerate(symbols)
        ]
        observed = await drive_symbols_and_collect(dut, symbols, max_cycles=2048)
        assert observed == expected, (width, height, y, observed, expected)
        await Timer(1, unit="ps")


@cocotb.test()
async def symbol_binarizer_holds_output_under_backpressure(dut):
    await reset(dut)
    symbols = load_rust_semantic_symbols(16, 16, 64)
    expected = [
        expected_binarized_record(kind, data, index == len(symbols) - 1)
        for index, (kind, data) in enumerate(symbols)
    ]
    observed = await drive_symbols_and_collect(dut, symbols, stall_every=4, max_cycles=2048)
    assert observed == expected
