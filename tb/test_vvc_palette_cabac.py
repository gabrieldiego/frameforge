import json
import subprocess
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


REPO_ROOT = Path(__file__).resolve().parents[1]
VECTOR = REPO_ROOT / "verification/test_vectors/palette_tiles_64x64_1f_yuv444p8.yuv"
DUMP = REPO_ROOT / "verification/generated/checksums/palette_tiles_64x64_1f_yuv444p8_palette_cabac.json"
MULTICOLOR_VECTOR = REPO_ROOT / "verification/generated/checksums/palette_multicolor_8x8_1f_yuv444p8.yuv"
MULTICOLOR_DUMP = REPO_ROOT / "verification/generated/checksums/palette_multicolor_8x8_1f_yuv444p8_palette_cabac.json"
CTU_SIZE = 64
PALETTE_CU_SIZE = 8
CTU_PALETTE_CU_COUNT = (CTU_SIZE // PALETTE_CU_SIZE) * (CTU_SIZE // PALETTE_CU_SIZE)


def pack_plane(data, width=64, height=64, max_width=64, max_height=64):
    value = 0
    max_samples = max_width * max_height
    plane_samples = width * height
    for index in range(max_samples):
        sample = data[index] if index < plane_samples else 0
        value = (value << 8) | sample
    return value


def palette_entries_and_indices(y, cb, cr, width, height, origin_x=0, origin_y=0):
    entries = []
    indices = []
    for y_off in range(min(8, height - origin_y)):
        for x_off in range(min(8, width - origin_x)):
            sample_index = (origin_y + y_off) * width + origin_x + x_off
            color = (y[sample_index], cb[sample_index], cr[sample_index])
            if color not in entries:
                entries.append(color)
            indices.append(entries.index(color))
    return entries, indices


def pack_palette_lossless_frame_symbols(y, cb, cr, width=64, height=64):
    symbols = []
    count = CTU_PALETTE_CU_COUNT
    for index in range(count):
        origin_x, origin_y = coding_order_position(index)
        selected = origin_x < width and origin_y < height
        if not selected:
            symbols.append(0x1 << 28)
            continue
        entries, indices = palette_entries_and_indices(y, cb, cr, width, height, origin_x, origin_y)
        symbols.append((0x1 << 28) | (1 << 24) | (len(entries) << 16))
        for entry_y, _, _ in entries:
            symbols.append((0x2 << 28) | entry_y)
        for _, entry_cb, _ in entries:
            symbols.append((0x4 << 28) | entry_cb)
        for _, _, entry_cr in entries:
            symbols.append((0x5 << 28) | entry_cr)
        if len(entries) > 1:
            for x, y_pos in palette_horizontal_scan_positions(
                min(8, width - origin_x),
                min(8, height - origin_y),
            ):
                index = indices[y_pos * min(8, width - origin_x) + x]
                symbols.append((0x3 << 28) | index)
    return len(symbols), symbols


def pack_palette_lossless_symbols(y, cb, cr, width=8, height=8):
    return pack_palette_lossless_frame_symbols(y, cb, cr, width, height)

def palette_horizontal_scan_positions(width, height):
    for y_pos in range(height):
        if y_pos % 2 == 0:
            x_iter = range(width)
        else:
            x_iter = range(width - 1, -1, -1)
        for x in x_iter:
            yield x, y_pos


def coding_order_position(index):
    origin_x = 0
    origin_y = 0
    origin_x += 32 if index & 0x10 else 0
    origin_y += 32 if index & 0x20 else 0
    index_in_32 = index & 0x0F
    origin_x += 16 if index_in_32 & 0x04 else 0
    origin_y += 16 if index_in_32 & 0x08 else 0
    index_in_16 = index_in_32 & 0x03
    origin_x += 8 if index_in_16 & 0x01 else 0
    origin_y += 8 if index_in_16 & 0x02 else 0
    return origin_x, origin_y


async def feed_palette_symbols(dut, symbols, count):
    if not hasattr(dut, "s_axis_valid"):
        return None
    observed = bytearray()
    index = 0
    saw_last = False
    if hasattr(dut, "m_axis_ready"):
        dut.m_axis_ready.value = 1
    dut.s_axis_valid.value = 1 if count else 0
    if hasattr(dut, "s_axis_kind"):
        dut.s_axis_kind.value = 1
    if count:
        dut.s_axis_data.value = symbols[0]
        dut.s_axis_last.value = count == 1
    while index < count or not saw_last:
        await RisingEdge(dut.clk)
        if hasattr(dut, "m_axis_valid") and int(dut.m_axis_valid.value) == 1:
            observed.append(int(dut.m_axis_data.value))
            saw_last = int(dut.m_axis_last.value) == 1
        if index < count and int(dut.s_axis_valid.value) == 1 and int(dut.s_axis_ready.value) == 1:
            index += 1
        if index < count:
            dut.s_axis_valid.value = 1
            dut.s_axis_data.value = symbols[index]
            dut.s_axis_last.value = index == count - 1
        else:
            dut.s_axis_valid.value = 0
            dut.s_axis_last.value = 0
        assert index < count or saw_last or len(observed) <= int(dut.stream_byte_count.value) + 8
    dut.s_axis_valid.value = 0
    dut.s_axis_last.value = 0
    await RisingEdge(dut.clk)
    return bytes(observed)


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


def ensure_multicolor_reference_dump():
    MULTICOLOR_VECTOR.parent.mkdir(parents=True, exist_ok=True)
    y = bytearray()
    cb = bytearray()
    cr = bytearray()
    for index in range(64):
        even = index % 2 == 0
        y.append(10 if even else 200)
        cb.append(20 if even else 210)
        cr.append(30 if even else 220)
    MULTICOLOR_VECTOR.write_bytes(bytes(y + cb + cr))
    subprocess.run(
        [
            "cargo",
            "run",
            "--quiet",
            "--",
            "vvc-palette-cabac-dump",
            "--input",
            str(MULTICOLOR_VECTOR),
            "--output",
            str(MULTICOLOR_DUMP),
            "--width",
            "8",
            "--height",
            "8",
            "--format",
            "yuv444p8",
        ],
        cwd=REPO_ROOT,
        check=True,
    )
    return json.loads(MULTICOLOR_DUMP.read_text())


@cocotb.test()
async def palette_cabac_matches_software_boundary_dump(dut):
    if hasattr(dut, "clk"):
        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
        dut.rst_n.value = 1
        await Timer(1, unit="ns")
        dut.rst_n.value = 0
        dut.enable.value = 1
        if hasattr(dut, "start"):
            dut.start.value = 0
        if hasattr(dut, "mode_palette_444"):
            dut.mode_palette_444.value = 1
            dut.body_kind.value = 0
            dut.luma_rem.value = 0
            dut.cb_rem.value = 0
            dut.cr_rem.value = 0
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
    symbol_count, symbols = pack_palette_lossless_frame_symbols(y, cb, cr)

    dut.enable.value = 1
    if hasattr(dut, "mode_palette_444"):
        dut.mode_palette_444.value = 1
        dut.body_kind.value = 0
        dut.luma_rem.value = 0
        dut.cb_rem.value = 0
        dut.cr_rem.value = 0
        dut.m_axis_ready.value = 1
    dut.coded_width.value = reference["width"]
    dut.coded_height.value = reference["height"]
    dut.symbol_count.value = CTU_PALETTE_CU_COUNT
    await Timer(1, unit="ns")
    observed_stream = await feed_palette_symbols(dut, symbols, symbol_count)
    await Timer(1, unit="ns")

    observed_len = int(dut.stream_bit_count.value)
    assert observed_len == reference["cabac_bit_len"], (
        observed_len,
        reference["cabac_bit_len"],
        observed_stream.hex() if observed_stream is not None else None,
        reference["cabac_hex"],
    )
    assert observed_stream.hex() == reference["cabac_hex"]


@cocotb.test()
async def palette_cabac_matches_multicolor_lossless_symbols(dut):
    if hasattr(dut, "clk"):
        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
        dut.rst_n.value = 1
        await Timer(1, unit="ns")
        dut.rst_n.value = 0
        dut.enable.value = 1
        if hasattr(dut, "start"):
            dut.start.value = 0
        if hasattr(dut, "mode_palette_444"):
            dut.mode_palette_444.value = 1
            dut.body_kind.value = 0
            dut.luma_rem.value = 0
            dut.cb_rem.value = 0
            dut.cr_rem.value = 0
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

    reference = ensure_multicolor_reference_dump()
    data = MULTICOLOR_VECTOR.read_bytes()
    y = data[:64]
    cb = data[64:128]
    cr = data[128:192]
    symbol_count, symbols = pack_palette_lossless_symbols(y, cb, cr)

    dut.enable.value = 1
    if hasattr(dut, "mode_palette_444"):
        dut.mode_palette_444.value = 1
        dut.body_kind.value = 0
        dut.luma_rem.value = 0
        dut.cb_rem.value = 0
        dut.cr_rem.value = 0
        dut.m_axis_ready.value = 1
    dut.coded_width.value = reference["width"]
    dut.coded_height.value = reference["height"]
    dut.symbol_count.value = CTU_PALETTE_CU_COUNT
    await Timer(1, unit="ns")
    observed_stream = await feed_palette_symbols(dut, symbols, symbol_count)
    await Timer(1, unit="ns")

    observed_len = int(dut.stream_bit_count.value)
    assert observed_len == reference["cabac_bit_len"], (
        observed_len,
        reference["cabac_bit_len"],
        observed_stream.hex() if observed_stream is not None else None,
        reference["cabac_hex"],
    )
    assert observed_stream.hex() == reference["cabac_hex"]
