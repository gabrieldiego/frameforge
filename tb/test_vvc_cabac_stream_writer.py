import json
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


CABAC_BIN_EP = 0
CABAC_BIN_TRM = 1
CABAC_BIN_CTX = 2
CABAC_BINS_EP = 3

SYMBOL_BIN_EP = 0
SYMBOL_BIN_TRM = 1
SYMBOL_BIN_CTX = 2
SYMBOL_BINS_EP = 4


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.clear.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_kind.value = CABAC_BIN_EP
    dut.s_axis_bin.value = 0
    dut.s_axis_bins_pattern.value = 0
    dut.s_axis_bins_count.value = 1
    dut.s_axis_ctx_valid.value = 0
    dut.s_axis_ctx_id.value = 0
    dut.s_axis_lps.value = 4
    dut.s_axis_mps.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_writer(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


@lru_cache(maxsize=None)
def load_rust_stream_vector(width, height, y):
    with tempfile.TemporaryDirectory(prefix="frameforge-stream-writer-vector-") as tmpdir:
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

    raw_symbols = bytes.fromhex(vector["semantic_symbols_hex"])
    record_bytes = vector["symbol_record_bytes"]
    bins = []
    for offset in range(0, len(raw_symbols), record_bytes):
        kind = raw_symbols[offset]
        data = int.from_bytes(raw_symbols[offset + 1 : offset + 5], "big")
        if kind == SYMBOL_BIN_TRM:
            bins.append({"kind": CABAC_BIN_TRM, "bin": data & 1})
        elif kind == SYMBOL_BIN_CTX:
            bins.append(
                {
                    "kind": CABAC_BIN_CTX,
                    "bin": data & 1,
                    "ctx_valid": 1,
                    "ctx_id": (data >> 8) & 0x3FF,
                }
            )
        elif kind == SYMBOL_BINS_EP:
            bins.append(
                {
                    "kind": CABAC_BINS_EP,
                    "bins_pattern": data >> 6,
                    "bins_count": data & 0x3F,
                }
            )
        else:
            assert kind == SYMBOL_BIN_EP
            bins.append({"kind": CABAC_BIN_EP, "bin": data & 1})
    return {
        "bins": bins,
        "bytes": bytes.fromhex(vector["cabac_bytes_hex"]),
        "last_bits": int(vector["cabac_bit_len"]) % 8,
    }


async def drive_bins_and_collect(dut, bins, backpressure=False, max_cycles=4096):
    observed = []
    held = None
    index = 0
    dut.s_axis_valid.value = 0

    for cycle in range(max_cycles):
        dut.m_axis_ready.value = 0 if backpressure and (cycle % 4 == 2) else 1
        if index < len(bins) and int(dut.s_axis_ready.value) == 1:
            if isinstance(bins[index], dict):
                item = bins[index]
                kind = item["kind"]
                bit = item.get("bin", 0)
                bins_pattern = item.get("bins_pattern", bit)
                bins_count = item.get("bins_count", 1)
                ctx_valid = item.get("ctx_valid", 0)
                ctx_id = item.get("ctx_id", 0)
                lps = item.get("lps", 4)
                mps = item.get("mps", 0)
            elif len(bins[index]) == 2:
                kind, bit = bins[index]
                bins_pattern = bit
                bins_count = 1
                ctx_valid = 0
                ctx_id = 0
                lps = 4
                mps = 0
            else:
                kind, bit, lps, mps = bins[index]
                bins_pattern = bit
                bins_count = 1
                ctx_valid = 0
                ctx_id = 0
            dut.s_axis_valid.value = 1
            dut.s_axis_kind.value = kind
            dut.s_axis_bin.value = bit
            dut.s_axis_bins_pattern.value = bins_pattern
            dut.s_axis_bins_count.value = bins_count
            dut.s_axis_ctx_valid.value = ctx_valid
            dut.s_axis_ctx_id.value = ctx_id
            dut.s_axis_lps.value = lps
            dut.s_axis_mps.value = mps
            dut.s_axis_last.value = index == len(bins) - 1
        else:
            dut.s_axis_valid.value = 0
            dut.s_axis_last.value = 0

        await ReadOnly()

        if int(dut.s_axis_valid.value) == 1 and int(dut.s_axis_ready.value) == 1:
            index += 1

        if int(dut.m_axis_valid.value) == 1:
            current = (int(dut.m_axis_data.value), int(dut.m_axis_last.value))
            if int(dut.m_axis_ready.value) == 0:
                if held is None:
                    held = current
                else:
                    assert current == held
            else:
                observed.append(current[0])
                held = None
                if current[1] == 1:
                    return bytes(observed)
        await Timer(1, unit="ps")
        await RisingEdge(dut.clk)

    raise AssertionError("stream writer did not finish")


@cocotb.test()
async def cabac_stream_writer_emits_bytes_without_backpressure(dut):
    await reset_dut(dut)
    await start_writer(dut)
    bins = [(CABAC_BIN_EP, i & 1) for i in range(40)] + [(CABAC_BIN_TRM, 1)]
    observed = await drive_bins_and_collect(dut, bins)
    assert observed != b""
    assert int(dut.done.value) in (0, 1)


@cocotb.test()
async def cabac_stream_writer_holds_byte_until_ready(dut):
    bins = [(CABAC_BIN_EP, (i >> 1) & 1) for i in range(48)] + [(CABAC_BIN_TRM, 1)]

    await reset_dut(dut)
    await start_writer(dut)
    stalled = await drive_bins_and_collect(dut, bins, backpressure=True)

    await Timer(1, unit="ps")
    await reset_dut(dut)
    await start_writer(dut)
    unstalled = await drive_bins_and_collect(dut, bins, backpressure=False)

    assert stalled == unstalled


@cocotb.test()
async def cabac_stream_writer_accepts_context_bins(dut):
    await reset_dut(dut)
    await start_writer(dut)
    bins = [
        (CABAC_BIN_CTX, 0, 4, 0),
        (CABAC_BIN_CTX, 1, 17, 0),
        (CABAC_BIN_CTX, 0, 8, 1),
        (CABAC_BIN_CTX, 1, 33, 1),
    ]
    bins.extend((CABAC_BIN_EP, i & 1) for i in range(32))
    bins.append((CABAC_BIN_TRM, 1))
    observed = await drive_bins_and_collect(dut, bins, backpressure=True)
    assert observed != b""


@cocotb.test()
async def cabac_stream_writer_matches_rust_vectors(dut):
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
        (64, 64, 64),
    ]
    for width, height, y in cases:
        vector = load_rust_stream_vector(width, height, y)
        await reset_dut(dut)
        await start_writer(dut)
        observed = await drive_bins_and_collect(dut, vector["bins"], max_cycles=8192)
        assert observed == vector["bytes"], (
            width,
            height,
            y,
            observed.hex(),
            vector["bytes"].hex(),
        )
        assert int(dut.stream_last_byte_bits.value) == vector["last_bits"], (
            width,
            height,
            y,
            int(dut.stream_last_byte_bits.value),
            vector["last_bits"],
        )
        await Timer(1, unit="ps")


@cocotb.test()
async def cabac_stream_writer_matches_rust_vector_under_backpressure(dut):
    vector = load_rust_stream_vector(16, 16, 64)
    await reset_dut(dut)
    await start_writer(dut)
    observed = await drive_bins_and_collect(
        dut, vector["bins"], backpressure=True, max_cycles=8192
    )
    assert observed == vector["bytes"]
