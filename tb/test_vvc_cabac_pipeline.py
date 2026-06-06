import json
import os
import subprocess
import tempfile
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


SYMBOL_BIN_EP = 0
SYMBOL_BIN_TRM = 1
SYMBOL_BIN_CTX = 2


def known_int(node, name):
    value = node.value
    if not value.is_resolvable:
        raise AssertionError(f"sampled {name} while it contains unknown bits: {value}")
    return int(value)


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.clear.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_kind.value = SYMBOL_BIN_EP
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_pipeline(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


def pack_ctx(bit, ctx_id=0, lps=4, mps=0):
    return (bit & 1) | ((ctx_id & 0x3FF) << 8) | ((lps & 0x1FF) << 16) | ((mps & 1) << 25)


def load_rust_cabac_vector_from_bytes(width, height, input_bytes, semantic=True):
    with tempfile.TemporaryDirectory(prefix="frameforge-cabac-vector-") as tmpdir:
        tmp = Path(tmpdir)
        input_yuv = tmp / "input.yuv"
        output_json = tmp / "cabac.json"
        input_yuv.write_bytes(input_bytes)
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

    symbol_key = "semantic_symbols_hex" if semantic else "symbols_hex"
    raw_symbols = bytes.fromhex(vector[symbol_key])
    record_bytes = vector["symbol_record_bytes"]
    assert record_bytes == 5
    assert len(raw_symbols) % record_bytes == 0
    symbols = []
    for offset in range(0, len(raw_symbols), record_bytes):
        kind = raw_symbols[offset]
        data = int.from_bytes(raw_symbols[offset + 1 : offset + 5], "big")
        symbols.append((kind, data))

    cabac_bytes = bytes.fromhex(vector["cabac_bytes_hex"])
    cabac_bit_len = int(vector["cabac_bit_len"])
    valid_last_bits = cabac_bit_len % 8
    return symbols, cabac_bytes, valid_last_bits


def load_rust_cabac_vector(width=8, height=8, y=64, u=128, v=128, semantic=True):
    luma_samples = width * height
    chroma_samples = luma_samples // 4
    input_bytes = bytes([y] * luma_samples + [u] * chroma_samples + [v] * chroma_samples)
    return load_rust_cabac_vector_from_bytes(width, height, input_bytes, semantic=semantic)


def load_symbol_trace(path):
    symbols = []
    for line_no, line in enumerate(Path(path).read_text().splitlines(), 1):
        if not line.strip():
            continue
        fields = line.split()
        if len(fields) not in (2, 3):
            raise AssertionError(f"{path}:{line_no}: expected kind data [last]")
        kind = int(fields[0], 16)
        data = int(fields[1], 16)
        last = int(fields[2]) if len(fields) == 3 else 0
        symbols.append((kind, data, last))
    assert symbols, f"{path}: empty CABAC symbol trace"
    if not symbols[-1][2]:
        kind, data, _last = symbols[-1]
        symbols[-1] = (kind, data, 1)
    return symbols


async def drive_symbols_and_collect(dut, symbols, max_cycles=512, output_stall_cycles=0):
    observed = []
    index = 0
    dut.s_axis_valid.value = 0

    for _ in range(max_cycles):
        dut.m_axis_ready.value = 0 if _ < output_stall_cycles else 1
        if index < len(symbols) and int(dut.s_axis_ready.value) == 1:
            symbol = symbols[index]
            kind, data = symbol[0], symbol[1]
            last = bool(symbol[2]) if len(symbol) > 2 else index == len(symbols) - 1
            dut.s_axis_valid.value = 1
            dut.s_axis_kind.value = kind
            dut.s_axis_data.value = data
            dut.s_axis_last.value = last
        else:
            dut.s_axis_valid.value = 0
            dut.s_axis_last.value = 0

        await ReadOnly()

        if int(dut.s_axis_valid.value) == 1 and int(dut.s_axis_ready.value) == 1:
            index += 1

        if int(dut.m_axis_valid.value) == 1 and int(dut.m_axis_ready.value) == 1:
            if not dut.m_axis_data.value.is_resolvable:
                dut._log.error(
                    "X CABAC byte: stream_state=%s bit_state=%s emit_valid=%s emit_value=%s "
                    "emit_count=%s low=%s range=%s bits_left=%s bit_value=%s "
                    "bit_bits_left=%s bit_partial=%s bit_out=%s",
                    dut.stream_writer.state_q.value,
                    dut.stream_writer.bit_writer.state_q.value,
                    dut.stream_writer.emit_valid_q.value,
                    dut.stream_writer.emit_value_q.value,
                    dut.stream_writer.emit_count_q.value,
                    dut.stream_writer.low_q.value,
                    dut.stream_writer.range_q.value,
                    dut.stream_writer.bits_left_q.value,
                    dut.stream_writer.bit_writer.value_q.value,
                    dut.stream_writer.bit_writer.bits_left_q.value,
                    dut.stream_writer.bit_writer.partial_byte_q.value,
                    dut.stream_writer.bit_writer.out_byte_q.value,
                )
            observed.append(known_int(dut.m_axis_data, "m_axis_data"))
            if int(dut.m_axis_last.value) == 1:
                return bytes(observed)

        await Timer(1, unit="ps")
        await RisingEdge(dut.clk)

    raise AssertionError("CABAC pipeline did not finish")


@cocotb.test()
async def cabac_pipeline_accepts_symbols_and_emits_bytes(dut):
    await reset_dut(dut)
    await start_pipeline(dut)
    symbols = [(SYMBOL_BIN_EP, i & 1) for i in range(40)]
    symbols.append((SYMBOL_BIN_TRM, 1))
    observed = await drive_symbols_and_collect(dut, symbols)
    assert observed != b""


@cocotb.test()
async def cabac_pipeline_accepts_context_symbols(dut):
    await reset_dut(dut)
    await start_pipeline(dut)
    symbols = [
        (SYMBOL_BIN_CTX, pack_ctx(0, ctx_id=0)),
        (SYMBOL_BIN_CTX, pack_ctx(1, ctx_id=1)),
        (SYMBOL_BIN_CTX, pack_ctx(0, ctx_id=8)),
    ]
    symbols.extend((SYMBOL_BIN_EP, i & 1) for i in range(32))
    symbols.append((SYMBOL_BIN_TRM, 1))
    observed = await drive_symbols_and_collect(dut, symbols)
    assert observed != b""


@cocotb.test()
async def cabac_pipeline_matches_rust_encoder_vector(dut):
    await reset_dut(dut)
    await start_pipeline(dut)
    symbols, expected_bytes, expected_last_bits = load_rust_cabac_vector()
    observed = await drive_symbols_and_collect(dut, symbols, max_cycles=2048)
    assert observed == expected_bytes, (observed.hex(), expected_bytes.hex())
    assert int(dut.stream_last_byte_bits.value) == expected_last_bits, (
        int(dut.stream_last_byte_bits.value),
        expected_last_bits,
    )


@cocotb.test()
async def cabac_pipeline_matches_chroma_ac_vector(dut):
    await reset_dut(dut)
    await start_pipeline(dut)
    y = bytes([128] * 64)
    cb = bytearray()
    cr = bytearray()
    for row in range(4):
        for col in range(4):
            cb.append(40 if (row + col) % 2 == 0 else 216)
            cr.append(216 if row < 2 else 40)
    symbols, expected_bytes, expected_last_bits = load_rust_cabac_vector_from_bytes(
        8,
        8,
        y + bytes(cb) + bytes(cr),
    )
    observed = await drive_symbols_and_collect(dut, symbols, max_cycles=2048)
    assert observed == expected_bytes, (observed.hex(), expected_bytes.hex())
    assert int(dut.stream_last_byte_bits.value) == expected_last_bits, (
        int(dut.stream_last_byte_bits.value),
        expected_last_bits,
    )


@cocotb.test()
async def cabac_pipeline_replays_symbol_trace(dut):
    trace = os.environ.get("FRAMEFORGE_RTL_CABAC_SYMBOL_TRACE")
    if trace is None:
        dut._log.info("FRAMEFORGE_RTL_CABAC_SYMBOL_TRACE not set; trace replay is inactive")
        return
    symbols = load_symbol_trace(trace)
    max_cycles = int(os.environ.get("FRAMEFORGE_RTL_CABAC_SYMBOL_TRACE_MAX_CYCLES", len(symbols) * 64 + 4096))
    output_stall_cycles = int(os.environ.get("FRAMEFORGE_RTL_CABAC_OUTPUT_STALL_CYCLES", "0"))
    segments = []
    segment = []
    for symbol in symbols:
        segment.append(symbol)
        if symbol[2]:
            segments.append(segment)
            segment = []
    if segment:
        kind, data, _last = segment[-1]
        segment[-1] = (kind, data, 1)
        segments.append(segment)

    await reset_dut(dut)
    for segment in segments:
        await start_pipeline(dut)
        observed = await drive_symbols_and_collect(
            dut,
            segment,
            max_cycles=max_cycles,
            output_stall_cycles=output_stall_cycles,
        )
        assert observed != b""
        await Timer(1, unit="ps")
        await RisingEdge(dut.clk)


@cocotb.test()
async def cabac_pipeline_matches_multiple_rust_encoder_vectors(dut):
    cases = [
        (8, 8, 0, 128, 128),
        (16, 16, 0, 128, 128),
        (16, 16, 64, 128, 128),
        (24, 16, 64, 128, 128),
        (16, 24, 64, 128, 128),
        (32, 32, 0, 128, 128),
        (64, 64, 64, 128, 128),
    ]
    for width, height, y, u, v in cases:
        await reset_dut(dut)
        await start_pipeline(dut)
        symbols, expected_bytes, expected_last_bits = load_rust_cabac_vector(
            width=width, height=height, y=y, u=u, v=v
        )
        observed = await drive_symbols_and_collect(dut, symbols, max_cycles=8192)
        assert observed == expected_bytes, (
            width,
            height,
            y,
            observed.hex(),
            expected_bytes.hex(),
        )
        assert int(dut.stream_last_byte_bits.value) == expected_last_bits, (
            width,
            height,
            y,
            int(dut.stream_last_byte_bits.value),
            expected_last_bits,
        )
        await Timer(1, unit="ps")


@cocotb.test()
async def cabac_pipeline_restarts_without_reset_against_rust_vector(dut):
    symbols, expected_bytes, expected_last_bits = load_rust_cabac_vector(width=16, height=16)

    await reset_dut(dut)
    await start_pipeline(dut)
    first = await drive_symbols_and_collect(dut, symbols, max_cycles=4096)
    assert first == expected_bytes, (first.hex(), expected_bytes.hex())
    assert int(dut.stream_last_byte_bits.value) == expected_last_bits

    await Timer(1, unit="ps")
    await RisingEdge(dut.clk)
    await start_pipeline(dut)
    second = await drive_symbols_and_collect(dut, symbols, max_cycles=4096)
    assert second == expected_bytes, (second.hex(), expected_bytes.hex())
    assert int(dut.stream_last_byte_bits.value) == expected_last_bits
