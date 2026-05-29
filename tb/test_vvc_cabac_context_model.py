import json
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.reset_contexts.value = 0
    dut.query_ctx_id.value = 0
    dut.query_range.value = 510
    dut.update_valid.value = 0
    dut.update_ctx_id.value = 0
    dut.update_bin.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@lru_cache(maxsize=None)
def load_rust_context_events(width, height, y):
    with tempfile.TemporaryDirectory(prefix="frameforge-context-vector-") as tmpdir:
        tmp = Path(tmpdir)
        luma_samples = width * height
        chroma_samples = luma_samples // 4
        input_yuv = tmp / "input.yuv"
        output_json = tmp / "cabac.json"
        input_yuv.write_bytes(bytes([y] * luma_samples + [128] * chroma_samples * 2))
        subprocess.run(
            [
                "cargo",
                "run",
                "--quiet",
                "--",
                "vvc-cabac-vector-dump",
                "--input",
                str(input_yuv),
                "--output",
                str(output_json),
                "--frames",
                "1",
                "--width",
                str(width),
                "--height",
                str(height),
                "--format",
                "yuv420p8",
            ],
            cwd=Path(__file__).resolve().parents[1],
            check=True,
        )
        vector = json.loads(output_json.read_text())

    raw_events = bytes.fromhex(vector["context_events_hex"])
    record_bytes = vector["context_event_record_bytes"]
    assert record_bytes == 7
    assert len(raw_events) % record_bytes == 0
    events = []
    for offset in range(0, len(raw_events), record_bytes):
        events.append(
            {
                "ctx_id": raw_events[offset],
                "bin": raw_events[offset + 1],
                "range": int.from_bytes(raw_events[offset + 2 : offset + 4], "big"),
                "lps": int.from_bytes(raw_events[offset + 4 : offset + 6], "big"),
                "mps": raw_events[offset + 6],
            }
        )
    assert events
    return events


async def apply_context_event(dut, event):
    dut.query_ctx_id.value = event["ctx_id"]
    dut.query_range.value = event["range"]
    await ReadOnly()
    assert int(dut.query_bank_id.value) == event["ctx_id"]
    assert int(dut.query_lps.value) == event["lps"], event
    assert int(dut.query_mps.value) == event["mps"], event

    await Timer(1, unit="ps")
    dut.update_valid.value = 1
    dut.update_ctx_id.value = event["ctx_id"]
    dut.update_bin.value = event["bin"]
    await RisingEdge(dut.clk)
    dut.update_valid.value = 0
    await Timer(1, unit="ps")


@cocotb.test()
async def context_model_replays_rust_context_events(dut):
    cases = [
        (8, 8, 0),
        (8, 8, 64),
        (8, 8, 128),
        (16, 16, 0),
        (16, 16, 64),
        (24, 16, 64),
        (16, 24, 64),
        (32, 32, 0),
        (32, 32, 64),
    ]
    for width, height, y in cases:
        await reset(dut)
        for event in load_rust_context_events(width, height, y):
            await apply_context_event(dut, event)


@cocotb.test()
async def context_model_reset_restores_initial_state(dut):
    await reset(dut)
    event = load_rust_context_events(16, 16, 64)[0]

    await apply_context_event(dut, event)
    dut.reset_contexts.value = 1
    await RisingEdge(dut.clk)
    dut.reset_contexts.value = 0
    await Timer(1, unit="ps")

    dut.query_ctx_id.value = event["ctx_id"]
    dut.query_range.value = event["range"]
    await ReadOnly()
    assert int(dut.query_lps.value) == event["lps"]
    assert int(dut.query_mps.value) == event["mps"]


@cocotb.test()
async def context_model_clamps_unknown_context_to_zero(dut):
    await reset(dut)
    dut.query_ctx_id.value = 31
    dut.query_range.value = 510
    await ReadOnly()
    assert int(dut.query_bank_id.value) == 0
