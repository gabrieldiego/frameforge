import subprocess
import tempfile
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


REPO_ROOT = Path(__file__).resolve().parents[1]


def fail_fast(message):
    manager = getattr(cocotb, "_regression_manager", None)
    if manager is not None:
        test_queue = getattr(manager, "_test_queue", None)
        included = getattr(manager, "_included", None)
        if test_queue is not None:
            test_queue.clear()
        if included is not None:
            included.clear()
    raise AssertionError(message)


def assert_fail_fast(condition, message):
    if not condition:
        fail_fast(message)


def solid_yuv420p8(y, u, v, frames):
    frame = bytes([y] * luma_samples() + [u] * chroma_plane_samples() + [v] * chroma_plane_samples())
    return frame * frames


def solid_yuv_planar8(y, u, v, frames, chroma_samples):
    frame = bytes([y] * luma_samples() + [u] * chroma_samples + [v] * chroma_samples)
    return frame * frames


def varied_yuv420p8(y, u, v, frames):
    frame = bytearray(solid_yuv420p8(y, u, v, 1))
    frame[3] = (y + 17) & 0xFF
    frame[luma_samples() + 1] = (u + 29) & 0xFF
    frame[v_sample_index() + 1] = (v + 43) & 0xFF
    return bytes(frame) * frames


def input_data(frames):
    return list(solid_yuv_planar8(0, 0, 0, frames, chroma_plane_samples()))


def input_path(frames):
    specific = os.environ.get(f"FRAMEFORGE_RTL_VVC_ENCODER_INPUT_{frames}F")
    generic = os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_INPUT")
    if path := specific or generic:
        return Path(path)
    return None


def input_samples_from_bytes(data, frames):
    sample_count = frame_samples() * frames
    bits = rtl_sample_bits()
    if bits <= 8:
        return list(data[:sample_count])
    samples = []
    for offset in range(0, sample_count * 2, 2):
        samples.append(int.from_bytes(data[offset : offset + 2], byteorder="little"))
    return samples


def rtl_sample_bits():
    return int(os.environ.get("RTL_SAMPLE_BITS", "8"))


def rtl_source_sample_bits():
    return int(os.environ.get("RTL_SOURCE_SAMPLE_BITS", str(rtl_sample_bits())))


def rtl_chroma_format_idc():
    return int(os.environ.get("RTL_CHROMA_FORMAT_IDC", "1"))


def rtl_visible_width():
    return int(os.environ.get("RTL_VISIBLE_WIDTH", "4"))


def rtl_visible_height():
    return int(os.environ.get("RTL_VISIBLE_HEIGHT", "4"))


def luma_samples():
    return rtl_visible_width() * rtl_visible_height()


def chroma_plane_samples():
    return {
        1: luma_samples() // 4,
        2: luma_samples() // 2,
        3: luma_samples(),
    }.get(rtl_chroma_format_idc(), luma_samples() // 4)


def frame_samples():
    return luma_samples() + (chroma_plane_samples() * 2)


def active_luma_tu_cols_for(width):
    return max((min(width, rtl_ctu_size()) + 7) // 8, 1)


def active_luma_tu_rows_for(height):
    return max((min(height, rtl_ctu_size()) + 7) // 8, 1)


def active_luma_tu_cols():
    return active_luma_tu_cols_for(ctu_visible_width_for(0))


def active_luma_tu_rows():
    return active_luma_tu_rows_for(ctu_visible_height_for(0))


def active_luma_tu_count():
    return active_luma_tu_cols() * active_luma_tu_rows()


def rtl_stream_luma_samples():
    if rtl_chroma_format_idc() in (1, 3):
        return sum(ctu_active_luma_tu_count(index) * 64 for index in range(ctu_count()))
    return luma_samples()


def rtl_stream_chroma_plane_samples():
    if rtl_chroma_format_idc() == 1:
        return sum(ctu_active_luma_tu_count(index) * 16 for index in range(ctu_count()))
    if rtl_chroma_format_idc() == 3:
        return sum(ctu_active_luma_tu_count(index) * 64 for index in range(ctu_count()))
    return chroma_plane_samples()


def rtl_stream_chroma_block_samples():
    if rtl_chroma_format_idc() == 3:
        return 64
    return 16


def rtl_stream_frame_samples():
    return rtl_stream_luma_samples() + (rtl_stream_chroma_plane_samples() * 2)


def rtl_ctu_size():
    return int(os.environ.get("RTL_CTU_SIZE", "64"))


def ctu_cols():
    return (rtl_visible_width() + rtl_ctu_size() - 1) // rtl_ctu_size()


def ctu_rows():
    return (rtl_visible_height() + rtl_ctu_size() - 1) // rtl_ctu_size()


def ctu_count():
    return ctu_cols() * ctu_rows()


def ctu_visible_width_for(ctu_x):
    origin_x = ctu_x * rtl_ctu_size()
    remaining = rtl_visible_width() - origin_x
    return min(rtl_ctu_size(), remaining if remaining > 0 else 1)


def ctu_visible_height_for(ctu_y):
    origin_y = ctu_y * rtl_ctu_size()
    remaining = rtl_visible_height() - origin_y
    return min(rtl_ctu_size(), remaining if remaining > 0 else 1)


def ctu_geometry(ctu_index):
    cols = max(ctu_cols(), 1)
    ctu_x = ctu_index % cols
    ctu_y = ctu_index // cols
    return ctu_x, ctu_y, ctu_visible_width_for(ctu_x), ctu_visible_height_for(ctu_y)


def ctu_active_luma_tu_count(ctu_index):
    _, _, width, height = ctu_geometry(ctu_index)
    return active_luma_tu_cols_for(width) * active_luma_tu_rows_for(height)


def v_sample_index():
    return luma_samples() + chroma_plane_samples()


def software_format():
    suffix = "8" if rtl_source_sample_bits() <= 8 else f"{rtl_source_sample_bits()}le"
    return {1: f"yuv420p{suffix}", 2: f"yuv422p{suffix}", 3: f"yuv444p{suffix}"}.get(
        rtl_chroma_format_idc(), f"yuv420p{suffix}"
    )


def software_input_bytes(data):
    bits = rtl_source_sample_bits()
    if bits <= 8:
        return bytes(source_sample(sample) for sample in data)
    out = bytearray()
    for sample in data:
        out.extend(source_sample(sample).to_bytes(2, byteorder="little"))
    return bytes(out)


def software_input_byte_count(frames):
    sample_bytes = 1 if rtl_source_sample_bits() <= 8 else 2
    return frame_samples() * frames * sample_bytes


def signed_value(value, bits):
    sign = 1 << (bits - 1)
    return (value ^ sign) - sign


def unpack_luma_ac_levels(packed, bits=8):
    return [
        signed_value((packed >> ((14 - idx) * bits)) & ((1 << bits) - 1), bits)
        for idx in range(15)
    ]


def unpack_chroma_ac_levels(packed, bits=8):
    return [
        signed_value((packed >> (idx * bits)) & ((1 << bits) - 1), bits)
        for idx in range(3)
    ]


def unpack_signed_slots(packed, bits, count):
    return [signed_value((packed >> (idx * bits)) & ((1 << bits) - 1), bits) for idx in range(count)]


def unpack_luma_tu_ac_slots(packed, tu_count, bits=8):
    return [
        unpack_luma_ac_levels(
            (packed >> (idx * bits * 15)) & ((1 << (bits * 15)) - 1),
            bits,
        )
        for idx in range(tu_count)
    ]


def unpack_chroma_tu_ac_slots(packed, tu_count, bits=8):
    return [
        unpack_chroma_ac_levels(
            (packed >> (idx * bits * 3)) & ((1 << (bits * 3)) - 1),
            bits,
        )
        for idx in range(tu_count)
    ]


def copy_input_prefix(input_file, output_file, frames):
    remaining = software_input_byte_count(frames)
    with Path(input_file).open("rb") as src, Path(output_file).open("wb") as dst:
        while remaining:
            chunk = src.read(min(remaining, 65536))
            assert chunk, f"input file ended before {frames} frame(s)"
            dst.write(chunk)
            remaining -= len(chunk)


def source_sample(sample):
    source_bits = rtl_source_sample_bits()
    sample_bits = rtl_sample_bits()
    if source_bits > sample_bits:
        return sample << (source_bits - sample_bits)
    if source_bits < sample_bits:
        return sample >> (sample_bits - source_bits)
    return sample


def ctu_tu_positions_8x8(width=None, height=None):
    visible_cols = active_luma_tu_cols() if width is None else active_luma_tu_cols_for(width)
    visible_rows = active_luma_tu_rows() if height is None else active_luma_tu_rows_for(height)
    positions = []
    for scan in range(64):
        col = ((scan >> 4) & 1) << 2
        col |= ((scan >> 2) & 1) << 1
        col |= scan & 1
        row = ((scan >> 5) & 1) << 2
        row |= ((scan >> 3) & 1) << 1
        row |= (scan >> 1) & 1
        if col < visible_cols and row < visible_rows:
            positions.append((col, row))
    return positions


# The RTL top consumes planar source frames through a CTU-local leaf stream, not
# in planar frame order. For each active 8x8 coding-tree leaf, the driver sends
# Y first, then the colocated Cb block, then the colocated Cr block. Chroma is
# 4x4 for the current 4:2:0 residual path and 8x8 for the 4:4:4 palette path.
# This mirrors the deliberately small RTL input buffer contract: one active
# leaf/TU is live at a time instead of a full 64x64 CTU fetch buffer.
def rtl_yuv420_ctu_ordered_samples(frame, ctu_index):
    width = rtl_visible_width()
    height = rtl_visible_height()
    chroma_width = width // 2
    chroma_height = height // 2
    luma_len = luma_samples()
    chroma_len = chroma_plane_samples()
    luma = frame[:luma_len]
    cb = frame[luma_len : luma_len + chroma_len]
    cr = frame[luma_len + chroma_len : luma_len + (chroma_len * 2)]
    out = []
    ctu_x, ctu_y, ctu_width, ctu_height = ctu_geometry(ctu_index)
    ctu_origin_x = ctu_x * rtl_ctu_size()
    ctu_origin_y = ctu_y * rtl_ctu_size()

    for col, row in ctu_tu_positions_8x8(ctu_width, ctu_height):
        origin_x = ctu_origin_x + (col * 8)
        origin_y = ctu_origin_y + (row * 8)
        for y in range(8):
            for x in range(8):
                sample_x = origin_x + x
                sample_y = origin_y + y
                if sample_x < width and sample_y < height:
                    out.append(luma[(sample_y * width) + sample_x])
                else:
                    out.append(0)

        for plane in (cb, cr):
            chroma_origin_x = (ctu_origin_x // 2) + (col * 4)
            chroma_origin_y = (ctu_origin_y // 2) + (row * 4)
            for y in range(4):
                for x in range(4):
                    sample_x = chroma_origin_x + x
                    sample_y = chroma_origin_y + y
                    if sample_x < chroma_width and sample_y < chroma_height:
                        out.append(plane[(sample_y * chroma_width) + sample_x])
                    else:
                        out.append(128)
    return out


def rtl_yuv420_tu_ordered_frame(frame):
    out = []
    for ctu_index in range(ctu_count()):
        out.extend(rtl_yuv420_ctu_ordered_samples(frame, ctu_index))
    return out


def append_block_samples(out, plane, width, height, origin_x, origin_y, block_size, pad_value):
    for y in range(block_size):
        for x in range(block_size):
            sample_x = origin_x + x
            sample_y = origin_y + y
            if sample_x < width and sample_y < height:
                out.append(plane[(sample_y * width) + sample_x])
            else:
                out.append(pad_value)


def rtl_yuv444_ctu_ordered_samples(frame, ctu_index):
    width = rtl_visible_width()
    height = rtl_visible_height()
    plane_len = luma_samples()
    luma = frame[:plane_len]
    cb = frame[plane_len : plane_len * 2]
    cr = frame[plane_len * 2 : plane_len * 3]
    out = []
    ctu_x, ctu_y, ctu_width, ctu_height = ctu_geometry(ctu_index)
    ctu_origin_x = ctu_x * rtl_ctu_size()
    ctu_origin_y = ctu_y * rtl_ctu_size()

    for col, row in ctu_tu_positions_8x8(ctu_width, ctu_height):
        origin_x = ctu_origin_x + (col * 8)
        origin_y = ctu_origin_y + (row * 8)
        append_block_samples(out, luma, width, height, origin_x, origin_y, 8, 0)
        append_block_samples(out, cb, width, height, origin_x, origin_y, 8, 128)
        append_block_samples(out, cr, width, height, origin_x, origin_y, 8, 128)
    return out


def rtl_yuv444_block_ordered_frame(frame):
    out = []
    for ctu_index in range(ctu_count()):
        out.extend(rtl_yuv444_ctu_ordered_samples(frame, ctu_index))
    return out


def rtl_input_bursts_for_frame(frame):
    if rtl_chroma_format_idc() == 1:
        return [rtl_yuv420_ctu_ordered_samples(frame, index) for index in range(ctu_count())]
    if rtl_chroma_format_idc() == 3:
        return [rtl_yuv444_ctu_ordered_samples(frame, index) for index in range(ctu_count())]
    return [list(frame)]


def tile_yuv420p8_frame(frame, source_width, source_height, tiled_width, tiled_height):
    source_luma = source_width * source_height
    source_chroma_width = source_width // 2
    source_chroma_height = source_height // 2
    source_chroma = source_chroma_width * source_chroma_height
    luma = frame[:source_luma]
    cb = frame[source_luma : source_luma + source_chroma]
    cr = frame[source_luma + source_chroma :]

    out_luma = bytearray()
    for y in range(tiled_height):
        source_row = (y % source_height) * source_width
        row = bytes(luma[source_row : source_row + source_width])
        repeats = (tiled_width + source_width - 1) // source_width
        out_luma.extend((row * repeats)[:tiled_width])

    tiled_chroma_width = tiled_width // 2
    tiled_chroma_height = tiled_height // 2
    out_cb = bytearray()
    out_cr = bytearray()
    for y in range(tiled_chroma_height):
        source_row = (y % source_chroma_height) * source_chroma_width
        cb_row = bytes(cb[source_row : source_row + source_chroma_width])
        cr_row = bytes(cr[source_row : source_row + source_chroma_width])
        repeats = (tiled_chroma_width + source_chroma_width - 1) // source_chroma_width
        out_cb.extend((cb_row * repeats)[:tiled_chroma_width])
        out_cr.extend((cr_row * repeats)[:tiled_chroma_width])

    return bytes(out_luma + out_cb + out_cr)


def crop_yuv420p8_frame(frame, coded_width, coded_height, visible_width, visible_height):
    coded_luma = coded_width * coded_height
    coded_chroma_width = coded_width // 2
    coded_chroma = coded_chroma_width * (coded_height // 2)
    luma = frame[:coded_luma]
    cb = frame[coded_luma : coded_luma + coded_chroma]
    cr = frame[coded_luma + coded_chroma :]

    out_luma = bytearray()
    for y in range(visible_height):
        row = y * coded_width
        out_luma.extend(luma[row : row + visible_width])

    chroma_width = visible_width // 2
    chroma_height = visible_height // 2
    out_cb = bytearray()
    out_cr = bytearray()
    for y in range(chroma_height):
        row = y * coded_chroma_width
        out_cb.extend(cb[row : row + chroma_width])
        out_cr.extend(cr[row : row + chroma_width])

    return bytes(out_luma + out_cb + out_cr)


def sample_to_8bit(sample):
    bits = rtl_sample_bits()
    if bits <= 8:
        return sample
    return sample >> (bits - 8)


def software_artifacts(frames, data=None, input_file=None):
    with tempfile.TemporaryDirectory() as tmpdir:
        fmt = software_format()
        input_yuv = Path(tmpdir) / f"input_{rtl_visible_width()}x{rtl_visible_height()}_{frames}f_{fmt}.yuv"
        output = Path(tmpdir) / "encoded.vvc"
        recon = Path(tmpdir) / "recon.yuv"
        if input_file is None:
            input_yuv.write_bytes(software_input_bytes(data))
        else:
            copy_input_prefix(input_file, input_yuv, frames)
        subprocess.run(
            [
                "cargo",
                "run",
                "--quiet",
                "--",
                "vvc-encode",
                "--input",
                str(input_yuv),
                "--frames",
                str(frames),
                "--width",
                str(rtl_visible_width()),
                "--height",
                str(rtl_visible_height()),
                "--output",
                str(output),
                "--recon",
                str(recon),
                "--format",
                fmt,
            ],
            cwd=REPO_ROOT,
            check=True,
        )
        return output.read_bytes(), recon.read_bytes()


def software_stream(frames, data):
    return software_artifacts(frames, data)[0]


def software_artifacts_for_source(frames, source):
    if source["path"] is not None:
        return software_artifacts(frames=frames, input_file=source["path"])
    sample_count = frame_samples() * frames
    data = source["data"]
    assert len(data) >= sample_count, f"source has {len(data)} sample(s), need {sample_count}"
    return software_artifacts(frames=frames, data=data[:sample_count])


def stream_source(frames):
    data_path = input_path(frames)
    data = None if data_path is not None else input_data(frames)
    return {"path": data_path, "data": data}


def annexb_nal_ranges(stream):
    starts = []
    i = 0
    while i + 3 <= len(stream):
        if i + 4 <= len(stream) and stream[i : i + 4] == b"\x00\x00\x00\x01":
            starts.append((i, 4))
            i += 4
        elif stream[i : i + 3] == b"\x00\x00\x01":
            starts.append((i, 3))
            i += 3
        else:
            i += 1

    ranges = []
    for index, (prefix_pos, prefix_len) in enumerate(starts):
        payload_start = prefix_pos + prefix_len
        payload_end = starts[index + 1][0] if index + 1 < len(starts) else len(stream)
        ranges.append((prefix_pos, payload_start, payload_end))
    return ranges


def software_vcl_slice_prefixes(reference):
    prefixes = []
    for _, payload_start, payload_end in annexb_nal_ranges(reference):
        assert payload_end - payload_start >= 2, f"NAL at byte {payload_start} has no VVC header"
        nal_unit_type = reference[payload_start + 1] >> 3
        if nal_unit_type <= 11:
            prefixes.append(reference[:payload_end])
    return prefixes


def first_mismatch_offset(actual, expected):
    limit = min(len(actual), len(expected))
    for offset in range(limit):
        if actual[offset] != expected[offset]:
            return offset
    if len(actual) != len(expected):
        return limit
    return None


def assert_stream_prefix_match(actual, expected, label):
    actual = bytes(actual)
    if actual == expected:
        return
    offset = first_mismatch_offset(actual, expected)
    actual_at = actual[offset : offset + 8].hex() if offset < len(actual) else "<eof>"
    expected_at = expected[offset : offset + 8].hex() if offset < len(expected) else "<eof>"
    fail_fast(
        f"RTL bitstream mismatch at {label}: "
        f"observed {len(actual)} byte(s), expected {len(expected)} byte(s), "
        f"first mismatch byte {offset}: rtl={actual_at} software={expected_at}"
    )


def software_frame_prefixes(frames, source, full_reference):
    prefixes = []
    for frame_count in range(1, frames + 1):
        if frame_count == frames:
            prefix = full_reference
        else:
            prefix, _ = software_artifacts_for_source(frames=frame_count, source=source)
        if not full_reference.startswith(prefix):
            offset = first_mismatch_offset(full_reference[: len(prefix)], prefix)
            fail_fast(
                f"software {frame_count}-frame stream is not a prefix of the "
                f"{frames}-frame reference; first mismatch byte {offset}"
            )
        prefixes.append(prefix)
    return prefixes


async def feed_input(dut, data, frames):
    # This is the cocotb top-driver boundary for ff_vvc_encoder.sv. The
    # elaborated DUT sees a leaf-ordered stream on s_axis_*:
    #   8x8 Y, colocated Cb, colocated Cr, then the next 8x8 leaf.
    # Source files remain planar YUV; rtl_input_bursts_for_frame() converts
    # each frame into CTU-local bursts. s_axis_last marks the end of a CTU
    # burst, not the end of the whole picture.
    samples = list(data)
    source_frame_samples = frame_samples()
    for frame_index in range(frames):
        frame = samples[
            frame_index * source_frame_samples : (frame_index + 1) * source_frame_samples
        ]
        for ctu_index, burst in enumerate(rtl_input_bursts_for_frame(frame)):
            for sample_index, sample in enumerate(burst):
                while dut.s_axis_ready.value != 1:
                    await RisingEdge(dut.clk)
                dut.s_axis_valid.value = 1
                dut.s_axis_data.value = sample
                dut.s_axis_last.value = sample_index == (len(burst) - 1)
                await RisingEdge(dut.clk)
            dut._log.info(
                "RTL input accepted CTU %d/%d (frame %d/%d)",
                ctu_index + 1,
                ctu_count(),
                frame_index + 1,
                frames,
            )

    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0


async def feed_input_file(dut, path, frames):
    bits = rtl_sample_bits()
    sample_bytes = 1 if bits <= 8 else 2
    source_frame_samples = frame_samples()
    with Path(path).open("rb") as handle:
        for frame_index in range(frames):
            frame = []
            for sample_index in range(source_frame_samples):
                raw = handle.read(sample_bytes)
                assert len(raw) == sample_bytes, f"input file ended before sample {sample_index}"
                frame.append(raw[0] if bits <= 8 else int.from_bytes(raw, byteorder="little"))
            # The RTL top is intentionally driven in leaf order rather than
            # file-planar order so the input side does not need a CTU buffer.
            for ctu_index, burst in enumerate(rtl_input_bursts_for_frame(frame)):
                for sample_index, sample in enumerate(burst):
                    while dut.s_axis_ready.value != 1:
                        await RisingEdge(dut.clk)
                    dut.s_axis_valid.value = 1
                    dut.s_axis_data.value = sample
                    dut.s_axis_last.value = sample_index == (len(burst) - 1)
                    await RisingEdge(dut.clk)
                dut._log.info(
                    "RTL input accepted CTU %d/%d (frame %d/%d)",
                    ctu_index + 1,
                    ctu_count(),
                    frame_index + 1,
                    frames,
                )

    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0


async def collect_stream(
    dut,
    frames,
    output_path=None,
    source=None,
    expected_frame_prefixes=None,
    expected_slice_prefixes=None,
    expected_reference_len=None,
):
    source = source if source is not None else stream_source(frames)
    data_path = source["path"]
    data = source["data"]
    await Timer(1, unit="ns")

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.visible_width.value = rtl_visible_width()
    dut.visible_height.value = rtl_visible_height()
    dut.chroma_format_idc.value = rtl_chroma_format_idc()
    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1

    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    def signal_int(path):
        node = dut
        for part in path.split("."):
            if not hasattr(node, part):
                return None
            node = getattr(node, part)
        return known_int(node, path)

    def signal_debug_value(path):
        node = dut
        for part in path.split("."):
            if not hasattr(node, part):
                return None
            node = getattr(node, part)
        return debug_value(node)

    def known_int(node, name):
        try:
            return int(node.value)
        except ValueError:
            raise AssertionError(f"sampled {name} while it contains unknown bits: {node.value}") from None

    def debug_value(node):
        try:
            return int(node.value)
        except ValueError:
            return str(node.value)

    def value_is_one(node, name):
        return known_int(node, name) == 1

    observed = bytearray()
    output_handle = None
    if output_path is not None:
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_handle = output_path.open("wb")
    symbol_records = []
    frontend_raw_records = []
    syntax_records = []

    def write_trace_records():
        if path := os.environ.get(f"FRAMEFORGE_RTL_CTU_SYMBOLS_OUT_{frames}F"):
            lines = [f"{kind:02x} {data:08x} {last:d}\n" for kind, data, last in symbol_records]
            Path(path).write_text("".join(lines))
        if path := os.environ.get(f"FRAMEFORGE_RTL_FRONTEND_RAW_OUT_{frames}F"):
            lines = [
                f"{kind:02x} {data:08x} {last:d}\n"
                for kind, data, last in frontend_raw_records
            ]
            Path(path).write_text("".join(lines))
        if path := os.environ.get(f"FRAMEFORGE_RTL_SYNTAX_OUT_{frames}F"):
            lines = [
                f"{kind:02x} {data:08x} {last:d}\n"
                for kind, data, last in syntax_records
            ]
            Path(path).write_text("".join(lines))

    handshake_counts = {
        "palette": 0,
        "palette_last": 0,
        "syntax": 0,
        "syntax_last": 0,
        "bin": 0,
        "bin_last": 0,
        "cabac_byte": 0,
        "cabac_byte_last": 0,
        "frontend_raw": 0,
        "frontend_raw_last": 0,
        "frontend_terminate_state": 0,
    }
    handshake_tail = []

    if data_path is None:
        feed_task = cocotb.start_soon(feed_input(dut, data, frames))
    else:
        feed_task = cocotb.start_soon(feed_input_file(dut, data_path, frames))

    output_frame_count = 0
    output_byte_count = 0
    ctu_symbol_count = 0
    ctu_slice_count = 0
    ctus_per_frame = max(ctu_count(), 1)
    expected_ctus = ctus_per_frame * frames
    last_current_slice = signal_int("current_slice_q")

    def log_ctu_progress(label, count):
        frame_index = ((count - 1) // ctus_per_frame) + 1
        ctu_index = ((count - 1) % ctus_per_frame) + 1
        dut._log.info(
            "RTL %s CTU %d/%d (frame %d/%d, CTU %d/%d)",
            label,
            count,
            expected_ctus,
            frame_index,
            frames,
            ctu_index,
            ctus_per_frame,
        )

    dut._log.info(
        "RTL encoder streaming %d frame(s), %dx%d %s",
        frames,
        rtl_visible_width(),
        rtl_visible_height(),
        software_format(),
    )
    reference_cycle_budget = 0 if expected_reference_len is None else expected_reference_len * 64
    max_cycles = (
        50000
        + (rtl_stream_frame_samples() * frames * 16)
        + (frames * 20000)
        + reference_cycle_budget
    )
    try:
        for cycle in range(max_cycles):
            await RisingEdge(dut.clk)
            await ReadOnly()
            if (
                hasattr(dut, "ctu_symbol_valid")
                and value_is_one(dut.ctu_symbol_valid, "ctu_symbol_valid")
                and value_is_one(dut.ctu_symbol_ready, "ctu_symbol_ready")
            ):
                symbol_records.append(
                    (
                        known_int(dut.ctu_symbol_kind, "ctu_symbol_kind"),
                        known_int(dut.ctu_symbol_data, "ctu_symbol_data"),
                        known_int(dut.ctu_symbol_last, "ctu_symbol_last"),
                    )
                )
                if value_is_one(dut.ctu_symbol_last, "ctu_symbol_last"):
                    ctu_symbol_count += 1
                    log_ctu_progress("symbolized", ctu_symbol_count)
            if (
                hasattr(dut, "palette_stream_valid")
                and value_is_one(dut.palette_stream_valid, "palette_stream_valid")
                and value_is_one(dut.palette_stream_ready, "palette_stream_ready")
            ):
                handshake_counts["palette"] += 1
                handshake_counts["palette_last"] += known_int(dut.palette_stream_last, "palette_stream_last")
                handshake_tail.append(
                    (
                        "pal",
                        known_int(dut.palette_stream_data, "palette_stream_data"),
                        known_int(dut.palette_stream_last, "palette_stream_last"),
                    )
                )
            if signal_int("cabac_writer.streamed_cabac.syntax_frontend.raw_symbol_valid") == 1 and signal_int(
                "cabac_writer.streamed_cabac.syntax_frontend.raw_symbol_ready"
            ) == 1:
                handshake_counts["frontend_raw"] += 1
                handshake_counts["frontend_raw_last"] += signal_int(
                    "cabac_writer.streamed_cabac.syntax_frontend.raw_symbol_last"
                )
                handshake_tail.append(
                    (
                        "raw",
                        signal_int("cabac_writer.streamed_cabac.syntax_frontend.raw_symbol_kind"),
                        signal_int("cabac_writer.streamed_cabac.syntax_frontend.raw_symbol_data"),
                        signal_int("cabac_writer.streamed_cabac.syntax_frontend.raw_symbol_last"),
                    )
                )
                frontend_raw_records.append(
                    (
                        signal_int("cabac_writer.streamed_cabac.syntax_frontend.raw_symbol_kind"),
                        signal_int("cabac_writer.streamed_cabac.syntax_frontend.raw_symbol_data"),
                        signal_int("cabac_writer.streamed_cabac.syntax_frontend.raw_symbol_last"),
                    )
                )
            if signal_int("cabac_writer.streamed_cabac.syntax_frontend.state_q") == 4:
                handshake_counts["frontend_terminate_state"] += 1
            if signal_int("cabac_writer.streamed_cabac.syntax_valid") == 1 and signal_int(
                "cabac_writer.streamed_cabac.syntax_ready"
            ) == 1:
                handshake_counts["syntax"] += 1
                handshake_counts["syntax_last"] += signal_int("cabac_writer.streamed_cabac.syntax_last")
                handshake_tail.append(
                    (
                        "syn",
                        signal_int("cabac_writer.streamed_cabac.syntax_kind"),
                        signal_int("cabac_writer.streamed_cabac.syntax_data"),
                        signal_int("cabac_writer.streamed_cabac.syntax_last"),
                    )
                )
                syntax_records.append(
                    (
                        signal_int("cabac_writer.streamed_cabac.syntax_kind"),
                        signal_int("cabac_writer.streamed_cabac.syntax_data"),
                        signal_int("cabac_writer.streamed_cabac.syntax_last"),
                    )
                )
            if signal_int("cabac_writer.streamed_cabac.bin_valid") == 1 and signal_int(
                "cabac_writer.streamed_cabac.bin_ready"
            ) == 1:
                handshake_counts["bin"] += 1
                handshake_counts["bin_last"] += signal_int("cabac_writer.streamed_cabac.bin_last")
                handshake_tail.append(
                    (
                        "bin",
                        signal_int("cabac_writer.streamed_cabac.bin_kind"),
                        signal_int("cabac_writer.streamed_cabac.bin_last"),
                    )
                )
            if (
                hasattr(dut, "cabac_stream_valid")
                and value_is_one(dut.cabac_stream_valid, "cabac_stream_valid")
                and value_is_one(dut.cabac_stream_ready, "cabac_stream_ready")
            ):
                handshake_counts["cabac_byte"] += 1
                handshake_counts["cabac_byte_last"] += known_int(dut.cabac_stream_last, "cabac_stream_last")
                handshake_tail.append(
                    (
                        "byte",
                        known_int(dut.cabac_stream_data, "cabac_stream_data"),
                        known_int(dut.cabac_stream_last, "cabac_stream_last"),
                    )
                )
            handshake_tail = handshake_tail[-24:]
            if value_is_one(dut.m_axis_valid, "m_axis_valid") and value_is_one(
                dut.m_axis_ready, "m_axis_ready"
            ):
                byte = known_int(dut.m_axis_data, "m_axis_data")
                output_byte_count += 1
                observed.append(byte)
                if output_handle is None:
                    pass
                else:
                    output_handle.write(bytes([byte]))
                current_slice = signal_int("current_slice_q")
                slice_completed = value_is_one(dut.m_axis_last, "m_axis_last")
                if (
                    not slice_completed
                    and current_slice is not None
                    and last_current_slice is not None
                    and current_slice == last_current_slice + 1
                ):
                    slice_completed = True
                if slice_completed:
                    ctu_slice_count += 1
                    log_ctu_progress("emitted", ctu_slice_count)
                    if expected_slice_prefixes is not None:
                        assert ctu_slice_count <= len(expected_slice_prefixes), (
                            f"RTL emitted CTU slice {ctu_slice_count}, but software only has "
                            f"{len(expected_slice_prefixes)} VCL slice prefix(es)"
                        )
                        write_trace_records()
                        assert_stream_prefix_match(
                            observed,
                            expected_slice_prefixes[ctu_slice_count - 1],
                            f"end of CTU slice {ctu_slice_count}/{expected_ctus}",
                        )
                if value_is_one(dut.m_axis_last, "m_axis_last"):
                    output_frame_count += 1
                    dut._log.info(
                        "RTL output emitted frame %d/%d (%d byte(s) so far)",
                        output_frame_count,
                        frames,
                        output_byte_count,
                    )
                    if expected_frame_prefixes is not None:
                        assert_stream_prefix_match(
                            observed,
                            expected_frame_prefixes[output_frame_count - 1],
                            f"end of frame {output_frame_count}/{frames}",
                        )
                    if output_frame_count == frames:
                        break
                last_current_slice = current_slice
    finally:
        if output_handle is not None:
            output_handle.close()
        write_trace_records()

    debug_state = {
        "generated_out_state": debug_value(dut.generated_out_state_q)
        if hasattr(dut, "generated_out_state_q")
        else None,
        "cabac_start": debug_value(dut.cabac_start_q) if hasattr(dut, "cabac_start_q") else None,
        "palette_stream_valid": debug_value(dut.palette_stream_valid)
        if hasattr(dut, "palette_stream_valid")
        else None,
        "palette_stream_ready": debug_value(dut.palette_stream_ready)
        if hasattr(dut, "palette_stream_ready")
        else None,
        "cabac_input_valid": debug_value(dut.cabac_input_valid_q)
        if hasattr(dut, "cabac_input_valid_q")
        else None,
        "cabac_input_kind": debug_value(dut.cabac_input_kind_q)
        if hasattr(dut, "cabac_input_kind_q")
        else None,
        "cabac_input_last": debug_value(dut.cabac_input_last_q)
        if hasattr(dut, "cabac_input_last_q")
        else None,
        "cabac_symbol_ready": debug_value(dut.cabac_symbol_ready)
        if hasattr(dut, "cabac_symbol_ready")
        else None,
        "ctu_symbol_valid": debug_value(dut.ctu_symbol_valid)
        if hasattr(dut, "ctu_symbol_valid")
        else None,
        "ctu_symbol_ready": debug_value(dut.ctu_symbol_ready)
        if hasattr(dut, "ctu_symbol_ready")
        else None,
        "ctu_symbol_kind": debug_value(dut.ctu_symbol_kind)
        if hasattr(dut, "ctu_symbol_kind")
        else None,
        "ctu_symbol_last": debug_value(dut.ctu_symbol_last)
        if hasattr(dut, "ctu_symbol_last")
        else None,
        "ctu_symbols_state": signal_debug_value("ctu_symbols.state_q"),
        "ctu_symbols_residual_start": signal_debug_value("ctu_symbols.residual_emitter_start_q"),
        "ctu_symbols_residual_valid": signal_debug_value("ctu_symbols.residual_axis_valid"),
        "ctu_symbols_residual_ready": signal_debug_value("ctu_symbols.residual_axis_ready"),
        "ctu_symbols_residual_done": signal_debug_value("ctu_symbols.residual_emitter_done"),
        "residual_emitter_state": signal_debug_value("ctu_symbols.residual_symbol_emitter_i.state_q"),
        "residual_emitter_subphase": signal_debug_value("ctu_symbols.residual_symbol_emitter_i.subphase_q"),
        "residual_emitter_scan_pos": signal_debug_value("ctu_symbols.residual_symbol_emitter_i.scan_pos_q"),
        "residual_emitter_regular_bins_left": signal_debug_value(
            "ctu_symbols.residual_symbol_emitter_i.regular_bins_left_q"
        ),
        "residual_emitter_sign_count": signal_debug_value(
            "ctu_symbols.residual_symbol_emitter_i.sign_count_q"
        ),
        "residual_emitter_min_pos_2nd_pass": signal_debug_value(
            "ctu_symbols.residual_symbol_emitter_i.min_pos_2nd_pass_q"
        ),
        "residual_emitter_busy": signal_debug_value("ctu_symbols.residual_symbol_emitter_i.busy"),
        "cabac_stream_valid": debug_value(dut.cabac_stream_valid)
        if hasattr(dut, "cabac_stream_valid")
        else None,
        "cabac_stream_ready": debug_value(dut.cabac_stream_ready)
        if hasattr(dut, "cabac_stream_ready")
        else None,
        "rbsp_payload_valid": debug_value(dut.rbsp_payload_valid)
        if hasattr(dut, "rbsp_payload_valid")
        else None,
        "rbsp_payload_ready": debug_value(dut.rbsp_payload_ready)
        if hasattr(dut, "rbsp_payload_ready")
        else None,
        "slice_stream_valid": debug_value(dut.slice_stream_valid)
        if hasattr(dut, "slice_stream_valid")
        else None,
        "slice_stream_ready": debug_value(dut.slice_stream_ready)
        if hasattr(dut, "slice_stream_ready")
        else None,
        "palette_state": signal_debug_value("palette_symbolizer.state_q"),
        "syntax_state": signal_debug_value("cabac_writer.streamed_cabac.syntax_frontend.state_q"),
        "syntax_valid": signal_debug_value("cabac_writer.streamed_cabac.syntax_valid"),
        "syntax_ready": signal_debug_value("cabac_writer.streamed_cabac.syntax_ready"),
        "binarizer_valid": signal_debug_value("cabac_writer.streamed_cabac.symbol_binarizer.valid_q"),
        "binarizer_kind": signal_debug_value("cabac_writer.streamed_cabac.symbol_binarizer.kind_q"),
        "binarizer_last": signal_debug_value("cabac_writer.streamed_cabac.symbol_binarizer.last_q"),
        "bin_valid": signal_debug_value("cabac_writer.streamed_cabac.bin_valid"),
        "bin_ready": signal_debug_value("cabac_writer.streamed_cabac.bin_ready"),
        "stream_writer_state": signal_debug_value("cabac_writer.streamed_cabac.stream_writer.state_q"),
        "stream_writer_return_state": signal_debug_value(
            "cabac_writer.streamed_cabac.stream_writer.return_state_q"
        ),
        "stream_writer_emit_valid": signal_debug_value(
            "cabac_writer.streamed_cabac.stream_writer.emit_valid_q"
        ),
        "bit_writer_state": signal_debug_value("cabac_writer.streamed_cabac.stream_writer.bit_writer.state_q"),
        "bit_writer_bits_left": signal_debug_value(
            "cabac_writer.streamed_cabac.stream_writer.bit_writer.bits_left_q"
        ),
        "bit_writer_partial_count": signal_debug_value(
            "cabac_writer.streamed_cabac.stream_writer.bit_writer.partial_count_q"
        ),
        "bit_writer_out_last": signal_debug_value(
            "cabac_writer.streamed_cabac.stream_writer.bit_writer.out_last_q"
        ),
        "bit_writer_idle": signal_debug_value("cabac_writer.streamed_cabac.stream_writer.bit_writer_idle"),
        "handshake_counts": handshake_counts,
        "handshake_tail": handshake_tail,
        "output_frame_count": output_frame_count,
        "output_byte_count": output_byte_count,
        "ctu_symbol_count": ctu_symbol_count,
        "ctu_slice_count": ctu_slice_count,
    }
    assert_fail_fast(
        output_frame_count == frames,
        (
            f"RTL encoder emitted {output_frame_count} frame boundaries within {max_cycles} cycles, "
            f"expected {frames}: {debug_state}"
        ),
    )
    await feed_task
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert_fail_fast(dut.input_error.value == 0, "RTL encoder reported input_error")

    if output_path is not None:
        return bytes(observed), source
    return bytes(observed), source


@cocotb.test()
async def vvc_encoder_matches_software_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    requested_frames = int(os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_FRAMES", "2"))
    source = stream_source(requested_frames)
    reference, recon = software_artifacts_for_source(
        frames=requested_frames,
        source=source,
    )
    expected_frame_prefixes = software_frame_prefixes(
        requested_frames,
        source,
        reference,
    )
    expected_slice_prefixes = software_vcl_slice_prefixes(reference)
    expected_ctus = ctu_count() * requested_frames
    assert_fail_fast(
        len(expected_slice_prefixes) == expected_ctus,
        (
            f"software reference exposes {len(expected_slice_prefixes)} VCL slice prefix(es), "
            f"expected {expected_ctus} CTU slice(s)"
        ),
    )

    async def dump_quantized_chroma_once():
        if os.environ.get("FRAMEFORGE_RTL_DUMP_QUANT") != "1":
            return
        if not hasattr(dut, "frame_quant_pending_q") and not hasattr(dut, "pending_output_q"):
            return
        for _ in range(5000):
            await RisingEdge(dut.clk)
            try:
                pending = int(dut.frame_quant_pending_q.value)
            except ValueError:
                pending = 0
            try:
                output_pending = int(dut.pending_output_q.value)
            except (AttributeError, ValueError):
                output_pending = 0
            if pending or output_pending:
                await RisingEdge(dut.clk)
                await ReadOnly()
                cb_direct = unpack_chroma_ac_levels(int(dut.quant_cb_ac_levels_q.value), bits=4)
                cr_direct = unpack_chroma_ac_levels(int(dut.quant_cr_ac_levels_q.value), bits=4)
                dut._log.info(
                    "RTL chroma quant direct cb_dc=%d cb_ac=%s cr_dc=%d cr_ac=%s",
                    signed_value(int(dut.quant_cb_dc_level_q.value), 9),
                    cb_direct,
                    signed_value(int(dut.quant_cr_dc_level_q.value), 9),
                    cr_direct,
                )
                try:
                    cb_ctu = unpack_chroma_ac_levels(int(dut.quant_cb_ac_levels_ctu_q[0].value), bits=4)
                    cr_ctu = unpack_chroma_ac_levels(int(dut.quant_cr_ac_levels_ctu_q[0].value), bits=4)
                    dut._log.info(
                        "RTL chroma quant CTU0/TU0 cb_dc=%d cb_ac=%s cr_dc=%d cr_ac=%s",
                        signed_value(int(dut.quant_cb_dc_level_ctu_q[0].value), 9),
                        cb_ctu,
                        signed_value(int(dut.quant_cr_dc_level_ctu_q[0].value), 9),
                        cr_ctu,
                    )
                except (AttributeError, TypeError, ValueError):
                    dut._log.info("RTL chroma quant CTU0/TU0 direct array probe unavailable")
                try:
                    luma_cols = (rtl_visible_width() + 7) // 8
                    luma_rows = (rtl_visible_height() + 7) // 8
                    luma_tu_count = min(luma_cols * luma_rows, 64)
                    luma_dc_packed = int(dut.selected_quant_luma_rem_w.value)
                    luma_dc = [
                        (luma_dc_packed >> (tu_idx * 8)) & 0xFF
                        for tu_idx in range(luma_tu_count)
                    ]
                    luma_ac = unpack_luma_tu_ac_slots(
                        int(dut.selected_quant_luma_ac_levels_w.value), luma_tu_count, bits=4
                    )
                    for tu_idx in range(luma_tu_count):
                        dut._log.info(
                            "RTL luma quant selected TU%d dc_abs=%d ac=%s",
                            tu_idx,
                            luma_dc[tu_idx],
                            luma_ac[tu_idx],
                        )
                except (AttributeError, TypeError, ValueError):
                    dut._log.info("RTL luma quant selected packed probe unavailable")
                try:
                    chroma_cols = ((rtl_visible_width() // 2) + 3) // 4
                    chroma_rows = ((rtl_visible_height() // 2) + 3) // 4
                    tu_count = min(chroma_cols * chroma_rows, 64)
                    cb_dc = unpack_signed_slots(int(dut.selected_quant_cb_dc_levels_w.value), 9, tu_count)
                    cr_dc = unpack_signed_slots(int(dut.selected_quant_cr_dc_levels_w.value), 9, tu_count)
                    cb_ac = unpack_chroma_tu_ac_slots(
                        int(dut.selected_quant_cb_ac_levels_w.value), tu_count, bits=4
                    )
                    cr_ac = unpack_chroma_tu_ac_slots(
                        int(dut.selected_quant_cr_ac_levels_w.value), tu_count, bits=4
                    )
                    for tu_idx in range(tu_count):
                        dut._log.info(
                            "RTL chroma quant selected TU%d cb_dc=%d cb_ac=%s cr_dc=%d cr_ac=%s",
                            tu_idx,
                            cb_dc[tu_idx],
                            cb_ac[tu_idx],
                            cr_dc[tu_idx],
                            cr_ac[tu_idx],
                        )
                except (AttributeError, TypeError, ValueError):
                    dut._log.info("RTL chroma quant selected packed probe unavailable")
                return

    quant_dump_task = cocotb.start_soon(dump_quantized_chroma_once())
    output_path = (
        os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_OUT_1F")
        if requested_frames == 1
        else os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_OUT")
    )
    recon_path = (
        os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_RECON_OUT_1F")
        if requested_frames == 1
        else os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_RECON_OUT")
    )
    bitstream, source = await collect_stream(
        dut,
        frames=requested_frames,
        output_path=output_path,
        source=source,
        expected_frame_prefixes=expected_frame_prefixes,
        expected_slice_prefixes=expected_slice_prefixes,
        expected_reference_len=len(reference),
    )
    await quant_dump_task
    if path := recon_path:
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(recon)
    assert_fail_fast(bitstream, "RTL encoder top emitted no bytes")
    assert_stream_prefix_match(bitstream, reference, "end of stream")


@cocotb.test()
async def vvc_encoder_matches_software_stream_with_ac_pattern(dut):
    if (
        rtl_visible_width() != 8
        or rtl_visible_height() != 8
        or rtl_chroma_format_idc() != 1
        or rtl_sample_bits() != 8
        or rtl_source_sample_bits() != 8
    ):
        return

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    with tempfile.TemporaryDirectory(prefix="frameforge-rtl-ac-pattern-") as tmpdir:
        path = Path(tmpdir) / "pattern_8x8_1f_yuv420p8.yuv"
        y = bytearray()
        for row in range(8):
            for col in range(8):
                y.append(32 if (row + col) % 2 == 0 else 224)
        path.write_bytes(bytes(y) + bytes([128] * 32))
        previous = os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_INPUT_1F")
        os.environ["FRAMEFORGE_RTL_VVC_ENCODER_INPUT_1F"] = str(path)
        try:
            bitstream, source = await collect_stream(dut, frames=1)
            reference, _ = software_artifacts_for_source(frames=1, source=source)
        finally:
            if previous is None:
                os.environ.pop("FRAMEFORGE_RTL_VVC_ENCODER_INPUT_1F", None)
            else:
                os.environ["FRAMEFORGE_RTL_VVC_ENCODER_INPUT_1F"] = previous
    assert_stream_prefix_match(bitstream, reference, "AC pattern end of stream")


@cocotb.test()
async def vvc_encoder_matches_software_stream_with_chroma_ac_pattern(dut):
    if (
        rtl_visible_width() != 8
        or rtl_visible_height() != 8
        or rtl_chroma_format_idc() != 1
        or rtl_sample_bits() != 8
        or rtl_source_sample_bits() != 8
    ):
        return

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    with tempfile.TemporaryDirectory(prefix="frameforge-rtl-chroma-ac-pattern-") as tmpdir:
        path = Path(tmpdir) / "chroma_pattern_8x8_1f_yuv420p8.yuv"
        y = bytes([128] * 64)
        cb = bytearray()
        cr = bytearray()
        for row in range(4):
            for col in range(4):
                cb.append(40 if (row + col) % 2 == 0 else 216)
                cr.append(216 if row < 2 else 40)
        path.write_bytes(y + bytes(cb) + bytes(cr))
        previous = os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_INPUT_1F")
        os.environ["FRAMEFORGE_RTL_VVC_ENCODER_INPUT_1F"] = str(path)
        captured_coeffs = []

        async def capture_quantized_chroma():
            if not hasattr(dut, "frame_quant_pending_q"):
                return
            for _ in range(2000):
                await RisingEdge(dut.clk)
                try:
                    pending = int(dut.frame_quant_pending_q.value)
                except ValueError:
                    pending = 0
                if pending:
                    await RisingEdge(dut.clk)
                    await ReadOnly()
                    cb_packed = int(dut.quant_cb_ac_levels_q.value)
                    cr_packed = int(dut.quant_cr_ac_levels_q.value)
                    captured_coeffs.append(
                        (
                            signed_value(int(dut.quant_cb_dc_level_q.value), 9),
                            unpack_chroma_ac_levels(cb_packed, bits=4),
                            signed_value(int(dut.quant_cr_dc_level_q.value), 9),
                            unpack_chroma_ac_levels(cr_packed, bits=4),
                        )
                    )
                    return

        quant_monitor = cocotb.start_soon(capture_quantized_chroma())
        try:
            bitstream, source = await collect_stream(dut, frames=1)
            reference, _ = software_artifacts_for_source(frames=1, source=source)
            await quant_monitor
        finally:
            if previous is None:
                os.environ.pop("FRAMEFORGE_RTL_VVC_ENCODER_INPUT_1F", None)
            else:
                os.environ["FRAMEFORGE_RTL_VVC_ENCODER_INPUT_1F"] = previous
    if captured_coeffs:
        cb_dc, cb_levels, cr_dc, cr_levels = captured_coeffs[0]
        dut._log.info(
            "RTL chroma coeffs cb_dc=%d cb_ac=%s cr_dc=%d cr_ac=%s",
            cb_dc,
            cb_levels,
            cr_dc,
            cr_levels,
        )
    assert_stream_prefix_match(bitstream, reference, "chroma AC pattern end of stream")
