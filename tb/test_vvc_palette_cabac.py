import json
import subprocess
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


REPO_ROOT = Path(__file__).resolve().parents[1]
VECTOR = REPO_ROOT / "verification/test_vectors/palette_tiles_64x64_1f_yuv444p8.yuv"
DUMP = REPO_ROOT / "verification/generated/checksums/palette_tiles_64x64_1f_yuv444p8_palette_cabac.json"


def pack_plane(data, width=64, height=64, max_width=64, max_height=64):
    value = 0
    max_samples = max_width * max_height
    plane_samples = width * height
    for index in range(max_samples):
        sample = data[index] if index < plane_samples else 0
        value = (value << 8) | sample
    return value


def pack_palette_symbols(y, cb, cr, width=64, height=64, max_symbols=64):
    symbols = []
    tiles_x = (width + 7) // 8
    tiles_y = (height + 7) // 8
    count = tiles_x * tiles_y
    for index in range(max_symbols):
        if index < count:
            tile_x = index % tiles_x
            tile_y = index // tiles_x
            sample_x = min(tile_x * 8, width - 1)
            sample_y = min(tile_y * 8, height - 1)
            sample_index = sample_y * width + sample_x
            symbol = (y[sample_index] << 16) | (cb[sample_index] << 8) | cr[sample_index]
        else:
            symbol = 0
        symbols.append(symbol)
    return count, symbols


def cabac_bytes(dut):
    bit_len = int(dut.payload_bit_len.value)
    if hasattr(dut, "compat_payload_bits"):
        value = int(dut.compat_payload_bits.value)
    else:
        value = int(dut.payload_bits.value)
    if bit_len == 0:
        return b""
    pad = ((bit_len + 7) // 8 * 8) - bit_len
    return (value << pad).to_bytes((bit_len + 7) // 8, byteorder="big")


async def stream_bytes(dut):
    if not hasattr(dut, "m_axis_data") or not hasattr(dut, "clk"):
        return None
    byte_count = int(dut.stream_byte_count.value)
    observed = bytearray()
    dut.m_axis_ready.value = 1
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    for index in range(byte_count + 4):
        await ReadOnly()
        assert int(dut.m_axis_valid.value) == 1
        observed.append(int(dut.m_axis_data.value))
        if int(dut.m_axis_last.value) == 1:
            assert len(observed) == byte_count
            await RisingEdge(dut.clk)
            break
        await RisingEdge(dut.clk)
    assert len(observed) == byte_count
    return bytes(observed)


async def feed_palette_symbols(dut, symbols, count):
    if not hasattr(dut, "s_axis_valid"):
        return
    for index in range(count):
        while int(dut.s_axis_ready.value) != 1:
            await RisingEdge(dut.clk)
        dut.s_axis_valid.value = 1
        if hasattr(dut, "s_axis_kind"):
            dut.s_axis_kind.value = 1
        dut.s_axis_data.value = symbols[index]
        dut.s_axis_last.value = index == count - 1
        await RisingEdge(dut.clk)
    dut.s_axis_valid.value = 0
    dut.s_axis_last.value = 0
    await RisingEdge(dut.clk)


def ensure_reference_dump():
    if not VECTOR.exists():
        subprocess.run(
            ["python3", "scripts/generate_palette_tile_vector.py"],
            cwd=REPO_ROOT,
            check=True,
        )
    DUMP.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "cargo",
            "run",
            "--quiet",
            "--",
            "vvc-palette-cabac-dump",
            "--input",
            str(VECTOR),
            "--output",
            str(DUMP),
            "--width",
            "64",
            "--height",
            "64",
            "--format",
            "yuv444p8",
        ],
        cwd=REPO_ROOT,
        check=True,
    )
    return json.loads(DUMP.read_text())


@cocotb.test()
async def palette_cabac_matches_software_boundary_dump(dut):
    if hasattr(dut, "clk"):
        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
        dut.rst_n.value = 0
        dut.enable.value = 1
        if hasattr(dut, "start"):
            dut.start.value = 0
        if hasattr(dut, "mode_palette_444"):
            dut.mode_palette_444.value = 1
            dut.body_kind.value = 0
            dut.luma_rem.value = 0
            dut.chroma_rem.value = 0
        dut.s_axis_valid.value = 0
        if hasattr(dut, "s_axis_kind"):
            dut.s_axis_kind.value = 0
        dut.s_axis_data.value = 0
        dut.s_axis_last.value = 0
        if hasattr(dut, "m_axis_ready"):
            dut.m_axis_ready.value = 1
        for _ in range(2):
            await RisingEdge(dut.clk)
        dut.rst_n.value = 1
        await RisingEdge(dut.clk)

    reference = ensure_reference_dump()
    data = VECTOR.read_bytes()
    luma_len = 64 * 64
    y = data[:luma_len]
    cb = data[luma_len : luma_len * 2]
    cr = data[luma_len * 2 : luma_len * 3]
    symbol_count, symbols = pack_palette_symbols(y, cb, cr)

    dut.enable.value = 1
    if hasattr(dut, "mode_palette_444"):
        dut.mode_palette_444.value = 1
        dut.body_kind.value = 0
        dut.luma_rem.value = 0
        dut.chroma_rem.value = 0
        dut.m_axis_ready.value = 1
    dut.coded_width.value = reference["width"]
    dut.coded_height.value = reference["height"]
    dut.symbol_count.value = symbol_count
    await feed_palette_symbols(dut, symbols, symbol_count)
    await Timer(1, unit="ns")

    assert int(dut.payload_bit_len.value) == reference["cabac_bit_len"]
    observed_hex = cabac_bytes(dut).hex()
    assert observed_hex == reference["cabac_hex"], (observed_hex, reference["cabac_hex"])
    observed_stream = await stream_bytes(dut)
    if observed_stream is not None:
        assert observed_stream.hex() == reference["cabac_hex"]
