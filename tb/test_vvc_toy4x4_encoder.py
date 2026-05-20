import subprocess
import tempfile
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


REPO_ROOT = Path(__file__).resolve().parents[1]


def software_stream(frames):
    with tempfile.TemporaryDirectory() as tmpdir:
        input_yuv = Path(tmpdir) / f"black_4x4_{frames}f_yuv420p8.yuv"
        output = Path(tmpdir) / "toy.vvc"
        input_yuv.write_bytes(internal_reconstruction(frames))
        subprocess.run(
            [
                "cargo",
                "run",
                "--quiet",
                "--",
                "vvc-toy-4x4-black-video",
                "--input",
                str(input_yuv),
                "--frames",
                str(frames),
                "--output",
                str(output),
            ],
            cwd=REPO_ROOT,
            check=True,
        )
        return output.read_bytes()


def internal_reconstruction(frames):
    return bytes(4 * 4 * 3 // 2 * frames)


async def feed_black_input(dut, frames):
    frame_bytes = len(internal_reconstruction(1))
    input_len = frame_bytes * frames

    for index in range(input_len):
        while dut.s_axis_ready.value != 1:
            await RisingEdge(dut.clk)
        dut.s_axis_valid.value = 1
        dut.s_axis_data.value = 0
        dut.s_axis_last.value = index == input_len - 1
        await RisingEdge(dut.clk)

    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0


async def collect_stream(dut, frames):
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

    await feed_black_input(dut, frames)
    await ReadOnly()
    assert dut.input_error.value == 0

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

    return bytes(observed)


@cocotb.test()
async def vvc_toy4x4_encoder_matches_software_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    one_frame = await collect_stream(dut, frames=1)
    assert one_frame == software_stream(frames=1)
    if path := os.environ.get("FRAMEFORGE_RTL_TOY4X4_OUT_1F"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(one_frame)
    if path := os.environ.get("FRAMEFORGE_RTL_TOY4X4_RECON_OUT_1F"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(internal_reconstruction(frames=1))

    two_frames = await collect_stream(dut, frames=2)
    assert two_frames == software_stream(frames=2)
    if path := os.environ.get("FRAMEFORGE_RTL_TOY4X4_OUT"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(two_frames)
    if path := os.environ.get("FRAMEFORGE_RTL_TOY4X4_RECON_OUT"):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(internal_reconstruction(frames=2))
