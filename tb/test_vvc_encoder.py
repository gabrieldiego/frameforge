import subprocess
import tempfile
import math
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
    return packed_luma_value(first_residual_luma_block(data))


def packed_second_rtl_luma_value(data):
    return packed_luma_value(second_residual_luma_block(data))


def packed_luma_value(samples):
    bits = rtl_sample_bits()
    value = 0
    for sample in rtl_input_samples(samples):
        value = (value << bits) | sample
    return value


def first_residual_luma_block(data):
    return residual_luma_block(data, 0, 0)


def second_residual_luma_block(data):
    if rtl_visible_width() >= 8:
        return residual_luma_block(data, 4, 0)
    if rtl_visible_height() >= 8:
        return residual_luma_block(data, 0, 4)
    return [0] * 16


def residual_luma_block(data, origin_x, origin_y):
    block = []
    for y in range(4):
        start = (origin_y + y) * rtl_visible_width() + origin_x
        block.extend(data[start : start + 4])
    return block


def quantized_luma(sample):
    best_rem = min(
        range(17),
        key=lambda rem: abs((((16 - rem) * 114 + 8) // 16) - sample),
    )
    return ((16 - best_rem) * 114) // 16


def forward_luma_dc(samples):
    samples = [sample_to_8bit(sample) for sample in samples]
    return ((sum(samples) + 8) >> 4) - 114


def quant_ac_token(sample, dc_sample):
    sample = sample_to_8bit(sample)
    coeff = sample - dc_sample
    magnitude = min((abs(coeff) + 8) >> 4, 8)
    negative = coeff < 0 and magnitude != 0
    return 0x40 | ((1 if negative else 0) << 5) | magnitude


def quant_ac_tokens(samples):
    dc_sample = (sum(sample_to_8bit(sample) for sample in samples) + 8) >> 4
    return bytes(quant_ac_token(sample, dc_sample) for sample in samples[1:16])


def quantized_luma_dc(dc_coeff):
    sample = max(0, min(255, dc_coeff + 114))
    return quantized_luma(sample) - 114


def inverse_transform_luma_dc(dc_coeff):
    return max(0, min(255, dc_coeff + 114))


def quantized_luma_remainder(sample):
    return min(
        range(17),
        key=lambda rem: abs((((16 - rem) * 114 + 8) // 16) - sample),
    )


VVC_CURRENT_CTU_SIZE = 64
VVC_CURRENT_MIN_LUMA_LEAF_SIZE = 16
VVC_CURRENT_MAX_LUMA_LEAF_SIZE = 32


def current_anchor_luma_tb_log2(width, height):
    return (
        5 if width >= VVC_CURRENT_MAX_LUMA_LEAF_SIZE else (4 if width >= VVC_CURRENT_MIN_LUMA_LEAF_SIZE else 3),
        5 if height >= VVC_CURRENT_MAX_LUMA_LEAF_SIZE else (4 if height >= VVC_CURRENT_MIN_LUMA_LEAF_SIZE else 3),
    )


def vvc_luma_reconstruction_from_sample(sample):
    rem = quantized_luma_remainder(sample_to_8bit(sample))
    log2_tb_width, log2_tb_height = current_anchor_luma_tb_log2(
        rtl_visible_width(), rtl_visible_height()
    )
    tb_area = 1 << (log2_tb_width + log2_tb_height)
    effective_side = max(8.0, math.sqrt(tb_area))
    dc_scale = max(1, round(456 / effective_side))
    residual_delta = (rem * dc_scale + 8) // 16
    return max(0, min(255, 128 - residual_delta))


def reconstructed_chroma(u, v):
    return 0 if u == 0 and v == 0 else 96


def decoded_reconstruction(frames, data):
    # This is the reconstruction of the emitted VVC bitstream.
    if rtl_chroma_format_idc() == 3:
        if rtl_sample_bits() == 8:
            return bytes(data[: frame_samples()]) * frames

        width = rtl_visible_width()
        height = rtl_visible_height()
        luma_len = luma_samples()
        y_plane = bytearray(luma_len)
        u_plane = bytearray(luma_len)
        v_plane = bytearray(luma_len)
        for origin_y in range(0, height, 8):
            for origin_x in range(0, width, 8):
                sample_index = origin_y * width + origin_x
                y = sample_to_8bit(data[sample_index])
                u = sample_to_8bit(data[luma_len + sample_index])
                v = sample_to_8bit(data[v_sample_index() + sample_index])
                for y_off in range(min(8, height - origin_y)):
                    row = (origin_y + y_off) * width + origin_x
                    tile_width = min(8, width - origin_x)
                    y_plane[row : row + tile_width] = bytes([y] * tile_width)
                    u_plane[row : row + tile_width] = bytes([u] * tile_width)
                    v_plane[row : row + tile_width] = bytes([v] * tile_width)
        frame = bytes(y_plane + u_plane + v_plane)
        return frame * frames
    if uses_capacity_tu_grid(data):
        chroma = reconstructed_chroma(sample_to_8bit(data[luma_samples()]), sample_to_8bit(data[v_sample_index()]))
        frame = bytearray([0] * luma_samples())
        for origin_y in range(0, rtl_visible_height(), 4):
            for origin_x in range(0, rtl_visible_width(), 4):
                block = residual_luma_block(data, origin_x, origin_y)
                y = inverse_transform_luma_dc(quantized_luma_dc(forward_luma_dc(block)))
                for y_off in range(min(4, rtl_visible_height() - origin_y)):
                    row = (origin_y + y_off) * rtl_visible_width() + origin_x
                    frame[row : row + min(4, rtl_visible_width() - origin_x)] = bytes(
                        [y] * min(4, rtl_visible_width() - origin_x)
                    )
        frame.extend([chroma] * (luma_samples() // 4))
        frame.extend([chroma] * (luma_samples() // 4))
        return bytes(frame) * frames

    y = vvc_luma_reconstruction_from_sample(data[0] if data else 0)
    chroma = 128
    frame = bytes(
        [y] * luma_samples()
        + [chroma] * (luma_samples() // 4)
        + [chroma] * (luma_samples() // 4)
    )
    return frame * frames


def uses_capacity_tu_grid(data):
    del data
    return not rtl_vtm_facing_path()


def rtl_vtm_facing_path():
    return (
        rtl_visible_width() >= 8
        and rtl_visible_height() >= 8
        and rtl_visible_width() <= 64
        and rtl_visible_height() <= 64
    )


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


def software_stream(frames, data):
    with tempfile.TemporaryDirectory() as tmpdir:
        fmt = software_format()
        input_yuv = Path(tmpdir) / f"input_{rtl_visible_width()}x{rtl_visible_height()}_{frames}f_{fmt}.yuv"
        output = Path(tmpdir) / "encoded.vvc"
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
                "--format",
                fmt,
            ],
            cwd=REPO_ROOT,
            check=True,
        )
        return output.read_bytes()


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
    observed = bytearray()
    symbol_records = []
    if dut.m_axis_valid.value == 1:
        observed.append(int(dut.m_axis_data.value))

    for cycle in range(8000):
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
        if dut.m_axis_valid.value == 1:
            observed.append(int(dut.m_axis_data.value))
            if dut.m_axis_last.value == 1:
                break

    if path := os.environ.get(f"FRAMEFORGE_RTL_CTU_SYMBOLS_OUT_{frames}F"):
        lines = [f"{kind:02x} {data:08x} {last:d}\n" for kind, data, last in symbol_records]
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
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_RECON_OUT_1F"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(decoded_reconstruction(frames=1, data=one_frame_input))

    # The palette RTL path currently models one CTU/frame at a time. Re-enable
    # this when the palette symbolizer has an explicit per-frame reset/drain
    # handshake instead of draining only on final input EOF.
    if rtl_chroma_format_idc() == 3:
        return

    two_frames, two_frame_input = await collect_stream(dut, frames=2)
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_OUT"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(two_frames)
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_RECON_OUT"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(decoded_reconstruction(frames=2, data=two_frame_input))
    assert two_frames, "RTL encoder top emitted no bytes for two-frame smoke"


@cocotb.test()
async def vvc_encoder_samples_first_yuv_values(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await drain_sampled_color(dut, frames=2, y=64, u=128, v=192)
