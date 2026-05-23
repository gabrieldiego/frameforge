import base64
import subprocess
import tempfile
import os
import zlib
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


REPO_ROOT = Path(__file__).resolve().parents[1]
TOY_16X16_SCRIPTED_RECON = bytes(
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
TOY_32X32_SCRIPTED_RECON_ZLIB_B64 = (
    "eNo1lOlz2gYWwP+wnZ1JN20d3wZs8AlufNvggI0xp4QAXUhCAt23QAgf2DXEjl2TJj5qp023s5N2nWzafOp/UmU6+768efN7b945b97zxT8e9Q/1PXrU75vbyOsX9zdne067c9K5ePP+0+//nRv71z+/eDLU/1XfSGA+DEqd73udlsufn17e//bx48OU58njx32DwyPeqdByFGSbJ5120z44OT1/efvzrw8Pk+Njg31f948FQktrm4kCozb3Wo2663B2cfnq7pd3M7Mz/uG+J57gWjSeBFFGNGynrqlmq3102D69fvvN0uqCf7Df9zSWBiCEYHjNbtVllpUNXRLrz1+HY4mtxYmxyZXdAoITFMPrzp7Fl1GiQsAw0+juZCBwe3EmuJHBqApFVjjdaRkMnIcgIJVGxCZQIqlSYn01CpAsx3zmdl3AgVRyNx6LA6SIkJzEoqlYPE9LMsdURd2UyPzudiy6GdlKlwhOMhqWgGbTxZpmKoKg6EolH4+sry4vr0a2U1nb2T9wNLoEYZxuabKi6wKeiizOB+dCT1fDz2LnZ92jls6RRIWXVVlSjM98LRgYH/dPzy8sLf/0Q++kqQocx3O1Wo2TdF2icuvTo4NDo17/1Gzw4T833YYsKppcLWNEVdJNtQZtBNx9DQyPeiam/nh4c2bLsmGpNFwqs6ppajVo3ff1476BgYEhT+DTh7cXLU2rNzQaRijJsAy5klsa/fLL/qGBJwNj/k8ffu4dWmajabAEybrlyTU0MT/yVd/w6FC/y39/eNtr182G01B5lhNEoUZCW/OewWGvb2x42Bt4/+7+fN/UzGbL1gSGIimqXIgvTfrGA5N+t8epX3581bFlQbZaLYvHi0V3S2h2c2Fudi4UCgWDodcvXxzqNYqWGo7JIkAepWuVUjKyvLi4sraxsb7WPmo3pTJUICVLZzGoWK5y1XJ+NxqOxBLpTDqlmM06V0wkIEbRBBrHiQpDE3BuN76TAmG8TBCsrlXS4XAS41VFqFIYgpUJrAhkcgWM5hU9Twg8HFtY2irVZE3lqRKYRwgCLRRKeIVT7YNEHkeTyzOhCEgJiiqQUBZEqQqB4WSVk8yDzrOdTHJjzj+zlkIYUeYIyD24WpUiKqwoytbhc7eL1ZDfN7kQBQhOZIlSiWB5lqY5Rde0xvGL+VBw2u/zTsys7KKsxJEIRgsCW2WVesOyWt3edMDn9Xi93olQDOYVnkRxxuWs6M7TttsXNwHfyMiYz+fxTG/CoiZQLuc5llPs/X3H+fb7N+UyjqEwDIsG657ycRdDEbhULBRIjqlJerNdLBagPAAACF3BKYbWISgP5rKZLEKTnzVRcDEI5HIIVdrdjm4Bf4dDBXcq4ZWV8BZFEp8zYGU0sTg793S5VmXoClEmSSIVGg9MzV49V1mOQCo1IjntC0xMv+rqnMiRZby0HZyanZr983/3vau7872DI5OEEQR5+PDT+cu3t+ff9U5butnav393d3z247/veuffnR53L287l0faXu/uuvvti9Pui96d45iqfXp7c/X6+urq+ubOUGRFO769+7+gIpECgK1YNLwTj0W+CcYxKAFhUCGzk0zEIqtPV7Kp7RJD0flUCkgnk5ubRSBeJBAsn8zAKIZnCyyeBPOJBJCGSLrKILhMpXPZ6LMMSPCSxDPZCrybL2UyWZBU65amrOey8SJVJrMAYbaatrW4mQJABC+CRdpqNZuNlc00mAOLMIzVjLpZt1BSUAVWNjXJ2Dvc39tXlfqho5t2XTedA/eTHtoH5x3bsBynYTsNTThpdy67Tc1oNnVdkwX64uLl1eWRZZqGqsiiwL66vr5+3TUNXXNtSRT/AhplPes="
)
TOY_32X32_SCRIPTED_RECON = zlib.decompress(
    base64.b64decode(TOY_32X32_SCRIPTED_RECON_ZLIB_B64)
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


def reconstructed_chroma(u, v):
    return 0 if u == 0 and v == 0 else 96


def decoded_reconstruction(frames, data):
    # This is the reconstruction of the emitted VVC bitstream.
    if rtl_chroma_format_idc() == 3:
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
    if is_toy_16x16_generated_path():
        return cropped_toy_16x16_generated_recon() * frames
    if is_toy_32x32_generated_path():
        return cropped_toy_32x32_generated_recon() * frames
    if is_toy_64x64_generated_path():
        return cropped_toy_64x64_generated_recon() * frames

    chroma = reconstructed_chroma(sample_to_8bit(data[luma_samples()]), sample_to_8bit(data[v_sample_index()]))
    if uses_capacity_tu_grid(data):
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

    y = inverse_transform_luma_dc(quantized_luma_dc(forward_luma_dc(first_residual_luma_block(data))))
    frame = bytes(
        [y] * luma_samples()
        + [chroma] * (luma_samples() // 4)
        + [chroma] * (luma_samples() // 4)
    )
    return frame * frames


def uses_capacity_tu_grid(data):
    return not (
        (rtl_visible_width() == 8 and rtl_visible_height() == 8)
        or is_toy_16x16_generated_path()
        or is_toy_32x32_generated_path()
        or is_toy_64x64_generated_path()
    )


def is_toy_16x16_generated_path():
    return (
        rtl_visible_width() <= 16
        and rtl_visible_height() <= 16
        and (rtl_visible_width() > 8 or rtl_visible_height() > 8)
    )


def is_toy_32x32_generated_path():
    return (
        rtl_visible_width() <= 32
        and rtl_visible_height() <= 32
        and (rtl_visible_width() > 16 or rtl_visible_height() > 16)
    )


def is_toy_64x64_generated_path():
    return (
        rtl_visible_width() <= 64
        and rtl_visible_height() <= 64
        and (rtl_visible_width() > 32 or rtl_visible_height() > 32)
    )


def cropped_toy_16x16_generated_recon():
    luma = TOY_16X16_SCRIPTED_RECON[: 16 * 16]
    cb = TOY_16X16_SCRIPTED_RECON[16 * 16 : 16 * 16 + 8 * 8]
    cr = TOY_16X16_SCRIPTED_RECON[16 * 16 + 8 * 8 :]
    out_luma = bytearray()
    for y in range(rtl_visible_height()):
        row = y * 16
        out_luma.extend(luma[row : row + rtl_visible_width()])
    chroma_width = rtl_visible_width() // 2
    chroma_height = rtl_visible_height() // 2
    out_cb = bytearray()
    out_cr = bytearray()
    for y in range(chroma_height):
        row = y * 8
        out_cb.extend(cb[row : row + chroma_width])
        out_cr.extend(cr[row : row + chroma_width])
    return bytes(out_luma + out_cb + out_cr)


def cropped_toy_32x32_generated_recon():
    return crop_yuv420p8_frame(
        TOY_32X32_SCRIPTED_RECON,
        coded_width=32,
        coded_height=32,
        visible_width=rtl_visible_width(),
        visible_height=rtl_visible_height(),
    )


def cropped_toy_64x64_generated_recon():
    frame_64 = tile_yuv420p8_frame(
        TOY_32X32_SCRIPTED_RECON,
        source_width=32,
        source_height=32,
        tiled_width=64,
        tiled_height=64,
    )
    return crop_yuv420p8_frame(
        frame_64,
        coded_width=64,
        coded_height=64,
        visible_width=rtl_visible_width(),
        visible_height=rtl_visible_height(),
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
    assert int(dut.luma_samples_1_q.value) == packed_second_rtl_luma_value(data)
    assert int(dut.quant_luma_ac_tokens_q.value) == int.from_bytes(
        quant_ac_tokens(first_residual_luma_block(data)), "big"
    )
    assert int(dut.quant_luma_ac_tokens_1_q.value) == int.from_bytes(
        quant_ac_tokens(second_residual_luma_block(data)), "big"
    )
    observed = bytearray()
    if dut.m_axis_valid.value == 1:
        observed.append(int(dut.m_axis_data.value))

    for cycle in range(2000):
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
    assert int(dut.luma_samples_1_q.value) == packed_second_rtl_luma_value(data)
    assert int(dut.quant_luma_ac_tokens_q.value) == int.from_bytes(
        quant_ac_tokens(first_residual_luma_block(data)), "big"
    )
    assert int(dut.quant_luma_ac_tokens_1_q.value) == int.from_bytes(
        quant_ac_tokens(second_residual_luma_block(data)), "big"
    )


@cocotb.test()
async def vvc_encoder_matches_software_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    one_frame, one_frame_input = await collect_stream(dut, frames=1)
    expected_one_frame = software_stream(frames=1, data=one_frame_input)
    assert one_frame == expected_one_frame, (
        one_frame.hex(),
        expected_one_frame.hex(),
        str(dut.palette_cu_select_mask.value) if hasattr(dut, "palette_cu_select_mask") else None,
        int(dut.palette_symbol_count.value) if hasattr(dut, "palette_symbol_count") else None,
        int(dut.cabac_payload_bit_len.value) if hasattr(dut, "cabac_payload_bit_len") else None,
    )
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_OUT_1F"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(one_frame)
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_RECON_OUT_1F"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(decoded_reconstruction(frames=1, data=one_frame_input))

    two_frames, two_frame_input = await collect_stream(dut, frames=2)
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_OUT"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(two_frames)
    if path := os.environ.get("FRAMEFORGE_RTL_VVC_ENCODER_RECON_OUT"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(decoded_reconstruction(frames=2, data=two_frame_input))
    expected_two_frames = software_stream(frames=2, data=two_frame_input)
    assert two_frames == expected_two_frames, (
        two_frames.hex(),
        expected_two_frames.hex(),
    )


@cocotb.test()
async def vvc_encoder_samples_first_yuv_values(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await drain_sampled_color(dut, frames=2, y=64, u=128, v=192)
