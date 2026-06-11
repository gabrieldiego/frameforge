import json
import subprocess
import tempfile
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


SYMBOL_BIN_EP = 0
SYMBOL_BIN_TRM = 1
PALETTE_PKT_CU_START = 0x81
PALETTE_PKT_ENTRY_Y = 0x82
PALETTE_PKT_INDEX = 0x83
PALETTE_PKT_ENTRY_CB = 0x84
PALETTE_PKT_ENTRY_CR = 0x85


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.enable.value = 1
    dut.lossless_slice_qp.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_kind.value = SYMBOL_BIN_EP
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_cabac(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


def load_rust_symbols(width=8, height=8, y=64):
    with tempfile.TemporaryDirectory(prefix="frameforge-cabac-top-vector-") as tmpdir:
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
    return symbols, bytes.fromhex(vector["cabac_bytes_hex"]), int(vector["cabac_bit_len"]) % 8


async def drive_symbols_and_collect(dut, symbols, max_cycles=4096):
    observed = []
    index = 0
    for _ in range(max_cycles):
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
            observed.append(int(dut.m_axis_data.value))
            if int(dut.m_axis_last.value) == 1:
                return bytes(observed)
        await Timer(1, unit="ps")
        await RisingEdge(dut.clk)
    raise AssertionError("CABAC top did not finish")


@cocotb.test()
async def cabac_top_matches_rust_residual_vector(dut):
    await reset_dut(dut)
    await start_cabac(dut)
    symbols, expected, last_bits = load_rust_symbols(width=16, height=16, y=64)
    observed = await drive_symbols_and_collect(dut, symbols, max_cycles=8192)
    assert observed == expected, (observed.hex(), expected.hex())
    assert int(dut.stream_last_byte_bits.value) == last_bits


@cocotb.test()
async def cabac_top_routes_palette_packets_through_common_pipeline(dut):
    await reset_dut(dut)
    await start_cabac(dut)
    symbols = [
        (PALETTE_PKT_CU_START, (1 << 24) | (1 << 16)),
        (PALETTE_PKT_ENTRY_Y, 65),
        (PALETTE_PKT_ENTRY_CB, 128),
        (PALETTE_PKT_ENTRY_CR, 192),
        (PALETTE_PKT_INDEX, 0),
    ]
    observed = await drive_symbols_and_collect(dut, symbols, max_cycles=1024)
    assert observed
