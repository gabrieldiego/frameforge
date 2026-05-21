import subprocess
import tempfile
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


REPO_ROOT = Path(__file__).resolve().parents[1]


def solid_yuv420p8(y, u, v, frames):
    frame = bytes([y] * 16 + [u] * 4 + [v] * 4)
    return frame * frames


def solid_yuv_planar8(y, u, v, frames, chroma_samples):
    frame = bytes([y] * 16 + [u] * chroma_samples + [v] * chroma_samples)
    return frame * frames


def varied_yuv420p8(y, u, v, frames):
    frame = bytearray(solid_yuv420p8(y, u, v, 1))
    frame[3] = (y + 17) & 0xFF
    frame[17] = (u + 29) & 0xFF
    frame[21] = (v + 43) & 0xFF
    return bytes(frame) * frames


def input_data(frames):
    specific = os.environ.get(f"FRAMEFORGE_RTL_TOY4X4_INPUT_{frames}F")
    generic = os.environ.get("FRAMEFORGE_RTL_TOY4X4_INPUT")
    if path := specific or generic:
        data = Path(path).read_bytes()
        return data[: frame_samples() * frames]
    return solid_yuv_planar8(0, 0, 0, frames, chroma_plane_samples())


def rtl_sample_bits():
    return int(os.environ.get("RTL_SAMPLE_BITS", "8"))


def rtl_source_sample_bits():
    return int(os.environ.get("RTL_SOURCE_SAMPLE_BITS", str(rtl_sample_bits())))


def rtl_chroma_format_idc():
    return int(os.environ.get("RTL_CHROMA_FORMAT_IDC", "1"))


def chroma_plane_samples():
    return {1: 4, 2: 8, 3: 16}.get(rtl_chroma_format_idc(), 4)


def frame_samples():
    return 16 + (chroma_plane_samples() * 2)


def v_sample_index():
    return 16 + chroma_plane_samples()


def software_format():
    suffix = "8" if rtl_source_sample_bits() <= 8 else f"{rtl_source_sample_bits()}le"
    return {1: f"yuv420p{suffix}", 2: f"yuv422p{suffix}", 3: f"yuv444p{suffix}"}.get(
        rtl_chroma_format_idc(), f"yuv420p{suffix}"
    )


def software_input_bytes(data):
    bits = rtl_source_sample_bits()
    if bits <= 8:
        return data
    out = bytearray()
    for sample in data:
        out.extend((sample << (bits - 8)).to_bytes(2, byteorder="little"))
    return bytes(out)


def rtl_input_samples(data):
    bits = rtl_sample_bits()
    if bits <= 8:
        return list(data)
    return [sample << (bits - 8) for sample in data]


def packed_rtl_luma_value(data):
    bits = rtl_sample_bits()
    value = 0
    for sample in rtl_input_samples(data[:16]):
        value = (value << bits) | sample
    return value


def quantized_luma(sample):
    return min(
        (((16 - rem) * 114 + 8) // 16 for rem in range(17)),
        key=lambda value: abs(value - sample),
    )


def forward_luma_dc(samples):
    return ((sum(samples) + 8) >> 4) - 114


def quant_ac_token(sample, dc_sample):
    coeff = sample - dc_sample
    magnitude = min((abs(coeff) + 8) >> 4, 8)
    return 0x40 | ((1 if coeff < 0 else 0) << 5) | magnitude


def quant_ac_tokens(samples):
    dc_sample = (sum(samples) + 8) >> 4
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
    y = inverse_transform_luma_dc(quantized_luma_dc(forward_luma_dc(data[:16])))
    chroma = reconstructed_chroma(data[16], data[v_sample_index()])
    frame = bytes([y] * 16 + [chroma] * 4 + [chroma] * 4)
    return frame * frames


def software_stream(frames, data):
    with tempfile.TemporaryDirectory() as tmpdir:
        fmt = software_format()
        input_yuv = Path(tmpdir) / f"input_4x4_{frames}f_{fmt}.yuv"
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
    assert int(dut.sampled_u.value) == samples[16]
    assert int(dut.sampled_v.value) == samples[v_sample_index()]
    assert int(dut.luma_samples_q.value) == packed_rtl_luma_value(data)
    assert int(dut.quant_luma_ac_tokens_q.value) == int.from_bytes(
        quant_ac_tokens(data[:16]), "big"
    )

    observed = bytearray()
    if dut.m_axis_valid.value == 1:
        observed.append(int(dut.m_axis_data.value))

    for cycle in range(240):
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
    data[17] = (u + 29) & 0xFF
    data[v_sample_index() + 1] = (v + 43) & 0xFF
    data = bytes(data)
    await feed_input(dut, data)
    await ReadOnly()
    assert dut.input_error.value == 0
    assert dut.sampled_color_valid.value == 1
    samples = rtl_input_samples(data)
    assert int(dut.sampled_y.value) == samples[0]
    assert int(dut.sampled_u.value) == samples[16]
    assert int(dut.sampled_v.value) == samples[v_sample_index()]
    assert int(dut.luma_samples_q.value) == packed_rtl_luma_value(data)
    assert int(dut.quant_luma_ac_tokens_q.value) == int.from_bytes(
        quant_ac_tokens(data[:16]), "big"
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
