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


def rtl_input_samples(data):
    return list(data)


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
    return software_artifacts(frames=frames, data=source["data"])


async def feed_input(dut, data, frames):
    samples = rtl_input_samples(data)
    for index, sample in enumerate(samples):
        while dut.s_axis_ready.value != 1:
            await RisingEdge(dut.clk)
        frame_last = ((index + 1) % frame_samples()) == 0
        dut.s_axis_valid.value = 1
        dut.s_axis_data.value = sample
        dut.s_axis_last.value = frame_last
        await RisingEdge(dut.clk)
        if frame_last:
            dut._log.info("RTL input accepted frame %d/%d", (index + 1) // frame_samples(), frames)

    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0


async def feed_input_file(dut, path, frames):
    expected_samples = frame_samples() * frames
    bits = rtl_sample_bits()
    sample_bytes = 1 if bits <= 8 else 2
    with Path(path).open("rb") as handle:
        for index in range(expected_samples):
            raw = handle.read(sample_bytes)
            assert len(raw) == sample_bytes, f"input file ended before sample {index}"
            sample = raw[0] if bits <= 8 else int.from_bytes(raw, byteorder="little")
            while dut.s_axis_ready.value != 1:
                await RisingEdge(dut.clk)
            frame_last = ((index + 1) % frame_samples()) == 0
            dut.s_axis_valid.value = 1
            dut.s_axis_data.value = sample
            dut.s_axis_last.value = frame_last
            await RisingEdge(dut.clk)
            if frame_last:
                dut._log.info("RTL input accepted frame %d/%d", (index + 1) // frame_samples(), frames)

    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0


async def collect_stream(dut, frames, output_path=None):
    data_path = input_path(frames)
    data = None if data_path is not None else input_data(frames)
    source = {"path": data_path, "data": data}
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
    dut._log.info(
        "RTL encoder streaming %d frame(s), %dx%d %s",
        frames,
        rtl_visible_width(),
        rtl_visible_height(),
        software_format(),
    )
    max_cycles = 50000 + (frame_samples() * frames * 16) + (frames * 20000)
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
                if output_handle is None:
                    observed.append(byte)
                else:
                    output_handle.write(bytes([byte]))
                if value_is_one(dut.m_axis_last, "m_axis_last"):
                    output_frame_count += 1
                    dut._log.info(
                        "RTL output emitted frame %d/%d (%d byte(s) so far)",
                        output_frame_count,
                        frames,
                        output_byte_count,
                    )
                    if output_frame_count == frames:
                        break
    finally:
        if output_handle is not None:
            output_handle.close()

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
    }
    assert output_frame_count == frames, (
        f"RTL encoder emitted {output_frame_count} frame boundaries within {max_cycles} cycles, expected {frames}",
        debug_state,
    )
    await feed_task
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert dut.input_error.value == 0

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

    if output_path is not None:
        return Path(output_path).read_bytes(), source
    return bytes(observed), source


async def drain_sampled_color(dut, frames, y, u, v):
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

    data = bytearray(solid_yuv_planar8(y, u, v, frames, chroma_plane_samples()))
    data[3] = (y + 17) & 0xFF
    data[luma_samples() + 1] = (u + 29) & 0xFF
    data[v_sample_index() + 1] = (v + 43) & 0xFF
    data = bytes(data)
    await feed_input(dut, data, frames)
    await ReadOnly()
    assert dut.input_error.value == 0
    assert dut.sampled_color_valid.value == 1
    samples = rtl_input_samples(data)
    assert int(dut.sampled_y.value) == samples[0]
    assert int(dut.sampled_u.value) == samples[luma_samples()]
    assert int(dut.sampled_v.value) == samples[v_sample_index()]


@cocotb.test()
async def vvc_encoder_matches_software_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    requested_frames = int(os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_FRAMES", "2"))
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
    )
    reference, recon = software_artifacts_for_source(
        frames=requested_frames,
        source=source,
    )
    if path := recon_path:
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(recon)
    assert bitstream, "RTL encoder top emitted no bytes"
    assert bitstream == reference


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
    assert bitstream == reference


@cocotb.test()
async def vvc_encoder_samples_first_yuv_values(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await drain_sampled_color(dut, frames=2, y=64, u=128, v=192)
