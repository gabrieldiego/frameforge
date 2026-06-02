import subprocess
import tempfile
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


REPO_ROOT = Path(__file__).resolve().parents[1]


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
    specific = os.environ.get(f"FRAMEFORGE_RTL_VVC_ENCODER_INPUT_{frames}F")
    generic = os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_INPUT")
    if path := specific or generic:
        return input_samples_from_bytes(Path(path).read_bytes(), frames)
    return list(solid_yuv_planar8(0, 0, 0, frames, chroma_plane_samples()))


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


def source_sample(sample):
    source_bits = rtl_source_sample_bits()
    sample_bits = rtl_sample_bits()
    if source_bits > sample_bits:
        return sample << (source_bits - sample_bits)
    if source_bits < sample_bits:
        return sample >> (sample_bits - source_bits)
    return sample


def rtl_input_samples(data):
    return list(data)


def packed_rtl_luma_value(data):
    return packed_luma_value(residual_luma_block(data, 0, 0))


def packed_luma_value(samples):
    bits = rtl_sample_bits()
    value = 0
    for sample in rtl_input_samples(samples):
        value = (value << bits) | sample
    return value


def residual_luma_block(data, origin_x, origin_y):
    return residual_luma_block_sized(
        data, origin_x, origin_y, VVC_LUMA_TU_SIZE, VVC_LUMA_TU_SIZE
    )


def residual_luma_block_sized(data, origin_x, origin_y, width, height):
    block = []
    for y in range(min(height, rtl_visible_height() - origin_y)):
        start = (origin_y + y) * rtl_visible_width() + origin_x
        block.extend(data[start : start + min(width, rtl_visible_width() - origin_x)])
    block.extend([0] * ((width * height) - len(block)))
    return block


VVC_LUMA_TU_SIZE = 8


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


def software_artifacts(frames, data):
    with tempfile.TemporaryDirectory() as tmpdir:
        fmt = software_format()
        input_yuv = Path(tmpdir) / f"input_{rtl_visible_width()}x{rtl_visible_height()}_{frames}f_{fmt}.yuv"
        output = Path(tmpdir) / "encoded.vvc"
        recon = Path(tmpdir) / "recon.yuv"
        input_yuv.write_bytes(software_input_bytes(data))
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


async def feed_input(dut, data):
    samples = rtl_input_samples(data)
    for index, sample in enumerate(samples):
        while dut.s_axis_ready.value != 1:
            await RisingEdge(dut.clk)
        dut.s_axis_valid.value = 1
        dut.s_axis_data.value = sample
        dut.s_axis_last.value = index == len(samples) - 1
        await RisingEdge(dut.clk)

    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0


async def collect_stream(dut, frames):
    data = input_data(frames)
    await Timer(1, unit="ns")

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.frame_count.value = frames
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

    await feed_input(dut, data)
    await ReadOnly()
    assert dut.input_error.value == 0
    assert dut.sampled_color_valid.value == 1
    samples = rtl_input_samples(data)
    assert int(dut.sampled_y.value) == samples[0]
    assert int(dut.sampled_u.value) == samples[luma_samples()]
    assert int(dut.sampled_v.value) == samples[v_sample_index()]
    assert int(dut.luma_samples_q.value) == packed_rtl_luma_value(data)

    def signal_int(path):
        node = dut
        for part in path.split("."):
            if not hasattr(node, part):
                return None
            node = getattr(node, part)
        try:
            return int(node.value)
        except ValueError:
            return None

    observed = bytearray()
    symbol_records = []
    frontend_raw_records = []
    syntax_records = []
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
    if dut.m_axis_valid.value == 1:
        observed.append(int(dut.m_axis_data.value))

    saw_last = False
    max_cycles = 20000 + frame_samples() * 16
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if (
            hasattr(dut, "ctu_symbol_valid")
            and int(dut.ctu_symbol_valid.value) == 1
            and int(dut.ctu_symbol_ready.value) == 1
        ):
            symbol_records.append(
                (
                    int(dut.ctu_symbol_kind.value),
                    int(dut.ctu_symbol_data.value),
                    int(dut.ctu_symbol_last.value),
                )
            )
        if (
            hasattr(dut, "palette_stream_valid")
            and int(dut.palette_stream_valid.value) == 1
            and int(dut.palette_stream_ready.value) == 1
        ):
            handshake_counts["palette"] += 1
            handshake_counts["palette_last"] += int(dut.palette_stream_last.value)
            handshake_tail.append(
                (
                    "pal",
                    int(dut.palette_stream_data.value),
                    int(dut.palette_stream_last.value),
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
            and int(dut.cabac_stream_valid.value) == 1
            and int(dut.cabac_stream_ready.value) == 1
        ):
            handshake_counts["cabac_byte"] += 1
            handshake_counts["cabac_byte_last"] += int(dut.cabac_stream_last.value)
            handshake_tail.append(
                (
                    "byte",
                    int(dut.cabac_stream_data.value),
                    int(dut.cabac_stream_last.value),
                )
            )
        handshake_tail = handshake_tail[-24:]
        if dut.m_axis_valid.value == 1:
            observed.append(int(dut.m_axis_data.value))
            if dut.m_axis_last.value == 1:
                saw_last = True
                break

    debug_state = {
        "generated_out_state": int(dut.generated_out_state_q.value)
        if hasattr(dut, "generated_out_state_q")
        else None,
        "cabac_start": int(dut.cabac_start_q.value) if hasattr(dut, "cabac_start_q") else None,
        "palette_stream_valid": int(dut.palette_stream_valid.value)
        if hasattr(dut, "palette_stream_valid")
        else None,
        "palette_stream_ready": int(dut.palette_stream_ready.value)
        if hasattr(dut, "palette_stream_ready")
        else None,
        "cabac_input_valid": int(dut.cabac_input_valid_q.value)
        if hasattr(dut, "cabac_input_valid_q")
        else None,
        "cabac_input_kind": int(dut.cabac_input_kind_q.value)
        if hasattr(dut, "cabac_input_kind_q")
        else None,
        "cabac_input_last": int(dut.cabac_input_last_q.value)
        if hasattr(dut, "cabac_input_last_q")
        else None,
        "cabac_symbol_ready": int(dut.cabac_symbol_ready.value)
        if hasattr(dut, "cabac_symbol_ready")
        else None,
        "cabac_stream_valid": int(dut.cabac_stream_valid.value)
        if hasattr(dut, "cabac_stream_valid")
        else None,
        "cabac_stream_ready": int(dut.cabac_stream_ready.value)
        if hasattr(dut, "cabac_stream_ready")
        else None,
        "rbsp_payload_valid": int(dut.rbsp_payload_valid.value)
        if hasattr(dut, "rbsp_payload_valid")
        else None,
        "rbsp_payload_ready": int(dut.rbsp_payload_ready.value)
        if hasattr(dut, "rbsp_payload_ready")
        else None,
        "slice_stream_valid": int(dut.slice_stream_valid.value)
        if hasattr(dut, "slice_stream_valid")
        else None,
        "slice_stream_ready": int(dut.slice_stream_ready.value)
        if hasattr(dut, "slice_stream_ready")
        else None,
        "palette_state": signal_int("palette_symbolizer.state_q"),
        "syntax_state": signal_int("cabac_writer.streamed_cabac.syntax_frontend.state_q"),
        "syntax_valid": signal_int("cabac_writer.streamed_cabac.syntax_valid"),
        "syntax_ready": signal_int("cabac_writer.streamed_cabac.syntax_ready"),
        "binarizer_valid": signal_int("cabac_writer.streamed_cabac.symbol_binarizer.valid_q"),
        "binarizer_kind": signal_int("cabac_writer.streamed_cabac.symbol_binarizer.kind_q"),
        "binarizer_last": signal_int("cabac_writer.streamed_cabac.symbol_binarizer.last_q"),
        "bin_valid": signal_int("cabac_writer.streamed_cabac.bin_valid"),
        "bin_ready": signal_int("cabac_writer.streamed_cabac.bin_ready"),
        "stream_writer_state": signal_int("cabac_writer.streamed_cabac.stream_writer.state_q"),
        "stream_writer_return_state": signal_int(
            "cabac_writer.streamed_cabac.stream_writer.return_state_q"
        ),
        "stream_writer_emit_valid": signal_int(
            "cabac_writer.streamed_cabac.stream_writer.emit_valid_q"
        ),
        "bit_writer_state": signal_int("cabac_writer.streamed_cabac.stream_writer.bit_writer.state_q"),
        "bit_writer_bits_left": signal_int(
            "cabac_writer.streamed_cabac.stream_writer.bit_writer.bits_left_q"
        ),
        "bit_writer_partial_count": signal_int(
            "cabac_writer.streamed_cabac.stream_writer.bit_writer.partial_count_q"
        ),
        "bit_writer_out_last": signal_int(
            "cabac_writer.streamed_cabac.stream_writer.bit_writer.out_last_q"
        ),
        "bit_writer_idle": signal_int("cabac_writer.streamed_cabac.stream_writer.bit_writer_idle"),
        "handshake_counts": handshake_counts,
        "handshake_tail": handshake_tail,
    }
    assert saw_last, (
        f"RTL encoder did not terminate byte stream within {max_cycles} cycles",
        debug_state,
    )

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

    return bytes(observed), data


async def drain_sampled_color(dut, frames, y, u, v):
    await Timer(1, unit="ns")

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.frame_count.value = frames
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

    data = bytearray(solid_yuv_planar8(y, u, v, frames, chroma_plane_samples()))
    data[3] = (y + 17) & 0xFF
    data[luma_samples() + 1] = (u + 29) & 0xFF
    data[v_sample_index() + 1] = (v + 43) & 0xFF
    data = bytes(data)
    await feed_input(dut, data)
    await ReadOnly()
    assert dut.input_error.value == 0
    assert dut.sampled_color_valid.value == 1
    samples = rtl_input_samples(data)
    assert int(dut.sampled_y.value) == samples[0]
    assert int(dut.sampled_u.value) == samples[luma_samples()]
    assert int(dut.sampled_v.value) == samples[v_sample_index()]
    assert int(dut.luma_samples_q.value) == packed_rtl_luma_value(data)


@cocotb.test()
async def vvc_encoder_matches_software_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    one_frame, one_frame_input = await collect_stream(dut, frames=1)
    assert one_frame, (
        "RTL encoder top emitted no bytes",
        str(dut.ctu_cu_active_mask.value) if hasattr(dut, "ctu_cu_active_mask") else None,
        int(dut.palette_symbol_count.value) if hasattr(dut, "palette_symbol_count") else None,
        int(dut.cabac_stream_last_byte_bits.value) if hasattr(dut, "cabac_stream_last_byte_bits") else None,
    )
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_OUT_1F"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(one_frame)
    one_frame_reference, one_frame_recon = software_artifacts(frames=1, data=one_frame_input)
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_RECON_OUT_1F"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(one_frame_recon)

    assert one_frame == one_frame_reference

    # The palette RTL path currently models one CTU/frame at a time. Keep the
    # multi-frame smoke on the residual path until the palette symbolizer has a
    # per-frame reset/drain handshake, but always require the one-frame RTL
    # bitstream to match the Rust reference.
    if rtl_chroma_format_idc() == 3:
        return

    two_frames, two_frame_input = await collect_stream(dut, frames=2)
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_OUT"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(two_frames)
    two_frame_reference, two_frame_recon = software_artifacts(frames=2, data=two_frame_input)
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_RECON_OUT"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(two_frame_recon)
    assert two_frames, "RTL encoder top emitted no bytes for two-frame smoke"
    assert two_frames == two_frame_reference


@cocotb.test()
async def vvc_encoder_samples_first_yuv_values(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await drain_sampled_color(dut, frames=2, y=64, u=128, v=192)
