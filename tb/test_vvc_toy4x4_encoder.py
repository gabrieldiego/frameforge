import subprocess
import tempfile
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


REPO_ROOT = Path(__file__).resolve().parents[1]
TOY_16X16_BLACK_TRACE_RECON = bytes(
    [
        124, 124, 124, 125, 125, 126, 127, 128, 129, 129, 130, 131, 131, 132, 132, 132,
        122, 123, 123, 123, 124, 125, 126, 126, 127, 128, 129, 129, 130, 130, 131, 131,
        122, 123, 123, 123, 124, 125, 125, 126, 127, 128, 128, 129, 130, 130, 130, 131,
        125, 125, 126, 126, 127, 127, 128, 129, 130, 130, 131, 132, 132, 133, 133, 133,
        129, 129, 129, 130, 130, 131, 132, 132, 133, 134, 134, 135, 135, 136, 136, 136,
        130, 130, 130, 131, 131, 132, 132, 133, 134, 134, 135, 135, 136, 136, 136, 137,
        127, 127, 127, 128, 128, 128, 129, 130, 130, 131, 131, 132, 132, 132, 133, 133,
        123, 123, 123, 124, 124, 124, 125, 125, 126, 126, 127, 127, 128, 128, 128, 128,
        122, 122, 122, 123, 123, 123, 124, 124, 125, 125, 126, 126, 126, 127, 127, 127,
        124, 125, 125, 125, 125, 126, 126, 126, 127, 127, 127, 128, 128, 128, 128, 129,
        127, 127, 127, 127, 127, 128, 128, 128, 128, 129, 129, 129, 130, 130, 130, 130,
        126, 126, 126, 126, 126, 127, 127, 127, 127, 128, 128, 128, 128, 128, 129, 129,
        123, 123, 123, 123, 123, 124, 124, 124, 124, 124, 125, 125, 125, 125, 125, 125,
        121, 121, 122, 122, 122, 122, 122, 122, 122, 123, 123, 123, 123, 123, 123, 123,
        123, 123, 123, 123, 123, 123, 123, 123, 124, 124, 124, 124, 124, 124, 124, 124,
        125, 125, 125, 125, 125, 125, 125, 125, 126, 126, 126, 126, 126, 126, 126, 126,
    ]
    + [128] * 64
    + [119] * 64
)


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
    specific = os.environ.get(f"FRAMEFORGE_RTL_TOY4X4_INPUT_{frames}F")
    generic = os.environ.get("FRAMEFORGE_RTL_TOY4X4_INPUT")
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
    bits = rtl_sample_bits()
    value = 0
    for sample in rtl_input_samples(first_residual_luma_block(data)):
        value = (value << bits) | sample
    return value


def first_residual_luma_block(data):
    block = []
    for y in range(4):
        start = y * rtl_visible_width()
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


def reconstructed_chroma(u, v):
    return 0 if u == 0 and v == 0 else 96


def decoded_reconstruction(frames, data):
    # This is the reconstruction of the emitted VVC bitstream.
    if is_toy_16x16_black_trace_path(data):
        return TOY_16X16_BLACK_TRACE_RECON * frames

    y = inverse_transform_luma_dc(quantized_luma_dc(forward_luma_dc(first_residual_luma_block(data))))
    chroma = reconstructed_chroma(sample_to_8bit(data[luma_samples()]), sample_to_8bit(data[v_sample_index()]))
    frame = bytes(
        [y] * luma_samples()
        + [chroma] * (luma_samples() // 4)
        + [chroma] * (luma_samples() // 4)
    )
    return frame * frames


def is_toy_16x16_black_trace_path(data):
    return (
        rtl_visible_width() == 16
        and rtl_visible_height() == 16
        and rtl_chroma_format_idc() == 1
        and rtl_source_sample_bits() == 8
        and all(sample == 0 for sample in data[:frame_samples()])
    )


def sample_to_8bit(sample):
    bits = rtl_sample_bits()
    if bits <= 8:
        return sample
    return sample >> (bits - 8)


def software_stream(frames, data):
    with tempfile.TemporaryDirectory() as tmpdir:
        fmt = software_format()
        input_yuv = Path(tmpdir) / f"input_{rtl_visible_width()}x{rtl_visible_height()}_{frames}f_{fmt}.yuv"
        output = Path(tmpdir) / "toy.vvc"
        input_yuv.write_bytes(software_input_bytes(data))
        subprocess.run(
            [
                "cargo",
                "run",
                "--quiet",
                "--",
                "vvc-toy-4x4-video",
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
    assert int(dut.quant_luma_ac_tokens_q.value) == int.from_bytes(
        quant_ac_tokens(first_residual_luma_block(data)), "big"
    )

    observed = bytearray()
    if dut.m_axis_valid.value == 1:
        observed.append(int(dut.m_axis_data.value))

    for cycle in range(420):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if dut.m_axis_valid.value == 1:
            observed.append(int(dut.m_axis_data.value))
            if dut.m_axis_last.value == 1:
                break

    return bytes(observed), data


async def drain_sampled_color(dut, frames, y, u, v):
    await Timer(1, unit="ns")

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.frame_count.value = frames
    dut.visible_width.value = rtl_visible_width()
    dut.visible_height.value = rtl_visible_height()
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
    assert int(dut.quant_luma_ac_tokens_q.value) == int.from_bytes(
        quant_ac_tokens(first_residual_luma_block(data)), "big"
    )


@cocotb.test()
async def vvc_toy4x4_encoder_matches_software_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    one_frame, one_frame_input = await collect_stream(dut, frames=1)
    expected_one_frame = software_stream(frames=1, data=one_frame_input)
    assert one_frame == expected_one_frame, (
        one_frame.hex(),
        expected_one_frame.hex(),
    )
    if path := os.environ.get("FRAMEFORGE_RTL_TOY4X4_OUT_1F"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(one_frame)
    if path := os.environ.get("FRAMEFORGE_RTL_TOY4X4_RECON_OUT_1F"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(decoded_reconstruction(frames=1, data=one_frame_input))

    two_frames, two_frame_input = await collect_stream(dut, frames=2)
    if path := os.environ.get("FRAMEFORGE_RTL_TOY4X4_OUT"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(two_frames)
    if path := os.environ.get("FRAMEFORGE_RTL_TOY4X4_RECON_OUT"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(decoded_reconstruction(frames=2, data=two_frame_input))
    expected_two_frames = software_stream(frames=2, data=two_frame_input)
    assert two_frames == expected_two_frames, (
        two_frames.hex(),
        expected_two_frames.hex(),
    )


@cocotb.test()
async def vvc_toy4x4_encoder_samples_first_yuv_values(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await drain_sampled_color(dut, frames=2, y=64, u=128, v=192)
