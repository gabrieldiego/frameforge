import json
import subprocess
import tempfile
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


SYMBOL_BIN_EP = 0
SYMBOL_BIN_TRM = 1
SYMBOL_BIN_CTX = 2


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.clear.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_kind.value = SYMBOL_BIN_EP
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_pipeline(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


def pack_ctx(bit, ctx_id=0, lps=4, mps=0):
    return (bit & 1) | ((ctx_id & 0x1F) << 8) | ((lps & 0x1FF) << 16) | ((mps & 1) << 25)


def load_rust_cabac_vector(width=8, height=8, y=64, u=128, v=128, semantic=True):
    with tempfile.TemporaryDirectory(prefix="frameforge-cabac-vector-") as tmpdir:
        tmp = Path(tmpdir)
        luma_samples = width * height
        chroma_samples = luma_samples // 4
        input_yuv = tmp / "input.yuv"
        output_json = tmp / "cabac.json"
        input_yuv.write_bytes(bytes([y] * luma_samples + [u] * chroma_samples + [v] * chroma_samples))
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

    symbol_key = "semantic_symbols_hex" if semantic else "symbols_hex"
    raw_symbols = bytes.fromhex(vector[symbol_key])
    record_bytes = vector["symbol_record_bytes"]
    assert record_bytes == 5
    assert len(raw_symbols) % record_bytes == 0
    symbols = []
    for offset in range(0, len(raw_symbols), record_bytes):
        kind = raw_symbols[offset]
        data = int.from_bytes(raw_symbols[offset + 1 : offset + 5], "big")
        symbols.append((kind, data))

    cabac_bytes = bytes.fromhex(vector["cabac_bytes_hex"])
    cabac_bit_len = int(vector["cabac_bit_len"])
    valid_last_bits = cabac_bit_len % 8
    return symbols, cabac_bytes, valid_last_bits


async def drive_symbols_and_collect(dut, symbols, max_cycles=512):
    observed = []
    index = 0
    dut.s_axis_valid.value = 0

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

    raise AssertionError("CABAC pipeline did not finish")


@cocotb.test()
async def cabac_pipeline_accepts_symbols_and_emits_bytes(dut):
    await reset_dut(dut)
    await start_pipeline(dut)
    symbols = [(SYMBOL_BIN_EP, i & 1) for i in range(40)]
    symbols.append((SYMBOL_BIN_TRM, 1))
    observed = await drive_symbols_and_collect(dut, symbols)
    assert observed != b""


@cocotb.test()
async def cabac_pipeline_accepts_context_symbols(dut):
    await reset_dut(dut)
    await start_pipeline(dut)
    symbols = [
        (SYMBOL_BIN_CTX, pack_ctx(0, ctx_id=0)),
        (SYMBOL_BIN_CTX, pack_ctx(1, ctx_id=1)),
        (SYMBOL_BIN_CTX, pack_ctx(0, ctx_id=8)),
    ]
    symbols.extend((SYMBOL_BIN_EP, i & 1) for i in range(32))
    symbols.append((SYMBOL_BIN_TRM, 1))
    observed = await drive_symbols_and_collect(dut, symbols)
    assert observed != b""


@cocotb.test()
async def cabac_pipeline_matches_rust_encoder_vector(dut):
    await reset_dut(dut)
    await start_pipeline(dut)
    symbols, expected_bytes, expected_last_bits = load_rust_cabac_vector()
    observed = await drive_symbols_and_collect(dut, symbols, max_cycles=2048)
    assert observed == expected_bytes, (observed.hex(), expected_bytes.hex())
    assert int(dut.stream_last_byte_bits.value) == expected_last_bits, (
        int(dut.stream_last_byte_bits.value),
        expected_last_bits,
    )


@cocotb.test()
async def cabac_pipeline_matches_multiple_rust_encoder_vectors(dut):
    cases = [
        (8, 8, 0, 128, 128),
        (16, 16, 0, 128, 128),
        (16, 16, 64, 128, 128),
        (24, 16, 64, 128, 128),
        (16, 24, 64, 128, 128),
        (32, 32, 0, 128, 128),
        (64, 64, 64, 128, 128),
    ]
    for width, height, y, u, v in cases:
        await reset_dut(dut)
        await start_pipeline(dut)
        symbols, expected_bytes, expected_last_bits = load_rust_cabac_vector(
            width=width, height=height, y=y, u=u, v=v
        )
        observed = await drive_symbols_and_collect(dut, symbols, max_cycles=8192)
        assert observed == expected_bytes, (
            width,
            height,
            y,
            observed.hex(),
            expected_bytes.hex(),
        )
        assert int(dut.stream_last_byte_bits.value) == expected_last_bits, (
            width,
            height,
            y,
            int(dut.stream_last_byte_bits.value),
            expected_last_bits,
        )
        await Timer(1, unit="ps")
