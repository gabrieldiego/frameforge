import json
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path

import cocotb
from cocotb.triggers import Timer


async def settle():
    await Timer(1, unit="ns")


def drive_event(dut, event):
    dut.bin_kind.value = event["kind"]
    dut.bin_value.value = event["bin"]
    dut.ctx_lps.value = event["lps"]
    dut.ctx_mps.value = event["mps"]
    dut.low_in.value = event["low_in"]
    dut.range_in.value = event["range_in"]
    dut.bits_left_in.value = event["bits_left_in"]


@lru_cache(maxsize=None)
def load_rust_bin_engine_events(width, height, y):
    with tempfile.TemporaryDirectory(prefix="frameforge-bin-engine-vector-") as tmpdir:
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

    raw_events = bytes.fromhex(vector["bin_engine_events_hex"])
    record_bytes = vector["bin_engine_event_record_bytes"]
    assert record_bytes == 20
    assert len(raw_events) % record_bytes == 0
    events = []
    for offset in range(0, len(raw_events), record_bytes):
        events.append(
            {
                "kind": raw_events[offset],
                "bin": raw_events[offset + 1],
                "lps": int.from_bytes(raw_events[offset + 2 : offset + 4], "big"),
                "mps": raw_events[offset + 4],
                "low_in": int.from_bytes(raw_events[offset + 5 : offset + 9], "big"),
                "range_in": int.from_bytes(raw_events[offset + 9 : offset + 11], "big"),
                "bits_left_in": raw_events[offset + 11],
                "low_out": int.from_bytes(raw_events[offset + 12 : offset + 16], "big"),
                "range_out": int.from_bytes(raw_events[offset + 16 : offset + 18], "big"),
                "bits_left_out": raw_events[offset + 18],
                "write_out": raw_events[offset + 19],
            }
        )
    assert events
    return events


@cocotb.test()
async def bin_engine_matches_rust_arithmetic_events(dut):
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
        for event in load_rust_bin_engine_events(width, height, y):
            drive_event(dut, event)
            await settle()
            observed = {
                "low_out": int(dut.low_out.value),
                "range_out": int(dut.range_out.value),
                "bits_left_out": int(dut.bits_left_out.value),
                "write_out": int(dut.write_out.value),
            }
            expected = {
                "low_out": event["low_out"],
                "range_out": event["range_out"],
                "bits_left_out": event["bits_left_out"],
                "write_out": event["write_out"],
            }
            assert observed == expected, (width, height, y, event, observed, expected)


@cocotb.test()
async def bin_engine_vectors_cover_all_current_bin_kinds(dut):
    events = []
    for case in [(8, 8, 0), (8, 8, 64), (8, 8, 128), (32, 32, 64)]:
        events.extend(load_rust_bin_engine_events(*case))
    assert {event["kind"] for event in events} == {0, 1, 2}
    assert any(event["write_out"] for event in events)
