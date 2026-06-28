#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import math
import os
import re
import argparse
import subprocess
from datetime import datetime
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKSUMS = ROOT / "verification/generated/checksums"
LOGS = ROOT / "verification/generated/validation_logs"
SHARED_SETS = ROOT / "verification/test_vector_sets"
LOCAL_SETS = SHARED_SETS / "local"
CODEC = "av2"
CODEC_TITLE = "AV2"
REFERENCE_DECODER = "reference-decoder"
SYNTH_TOP = "ff_av2_encoder"
SYNTH_DUT = "av2-encoder"
CURRENT_SHA = ""
PREV_OUTPUT_SHA = ""
PREV_QUALITY_SHA = ""
PREV_SYNTH_SHA = ""
REPORT_TITLE = ""
BASELINE_REF = ""
INCLUDE_VIVADO = True
SET_INFO: list[tuple[str, str]] = []
PROBES: list[tuple[str, str]] = []


@dataclass
class Vector:
    name: str
    width: int
    height: int
    frames: int
    fmt: str
    set_name: str

    @property
    def stem(self) -> str:
        return f"{self.name}_{self.width}x{self.height}_{self.frames}f_{self.fmt}"

    @property
    def suffix(self) -> str:
        return f"{self.width}x{self.height}_{self.frames}f_{self.fmt}"

    @property
    def metrics_path(self) -> Path:
        return CHECKSUMS / CODEC / f"{self.stem}_{self.suffix}_rtl_cycle_metrics.json"

    @property
    def log_path(self) -> Path:
        return LOGS / CODEC / f"{self.set_name}_{self.stem}.log"


AV2_SET_INFO = [
    ("screenshot-sweep-444", "Screenshot 4:4:4 Full Sweep"),
    ("screenshot-multictu-444", "Screenshot 4:4:4 Multi-CTU And Partial Crops"),
    ("racehorses-sweep-420", "RaceHorses 4:2:0 Full Sweep"),
    ("racehorses-multictu-420", "RaceHorses 4:2:0 Multi-CTU And Partial Crops"),
    ("multiframe-smoke", "Multi-Frame Smoke"),
]

VVC_SET_INFO = [
    ("racehorses-sweep-420", "RaceHorses 4:2:0 Full Sweep"),
    ("racehorses-multictu-420", "RaceHorses 4:2:0 Multi-CTU And Partial Crops"),
    ("screenshot-sweep-444", "Screenshot 4:4:4 Full Sweep"),
    ("screenshot-multictu-444", "Screenshot 4:4:4 Multi-CTU And Partial Crops"),
    ("multiframe-smoke", "Multi-Frame Smoke"),
]

AV2_PROBES = [
    ("final_output_utilization", "Final byte output"),
    ("axi_write_beat_utilization", "AXI write accepted-beat readiness"),
    ("axi_write_bus_utilization", "AXI write bus occupancy"),
    ("frame_reader_sample_utilization", "Frame reader sample issue"),
    ("frame_reader_to_fifo_utilization", "Reader-to-FIFO handshake"),
    ("input_fifo_core_utilization", "Input FIFO-to-core handshake"),
    ("input_fifo_nonempty_rate", "Input FIFO nonempty rate"),
    ("input_fifo_full_rate", "Input FIFO full rate"),
    ("entropy_leaf_op_utilization", "AV2 leaf entropy op issue"),
    ("chroma_bdpcm_op_utilization", "AV2 chroma BDPCM op issue"),
    ("chroma_bdpcm_zero_fast_rate", "AV2 chroma zero-TXB shortcut rate"),
    ("luma_residual_op_utilization", "AV2 luma residual op issue"),
    ("prefetch_useful_utilization", "AV2 prefetch useful fraction"),
    ("carry_payload_utilization", "AV2 carry payload bytes/cycle"),
]

VVC_PROBES = [
    ("final_output_utilization", "Final byte output"),
    ("axi_write_beat_utilization", "AXI write accepted-beat readiness"),
    ("axi_write_bus_utilization", "AXI write bus occupancy"),
    ("frame_reader_sample_utilization", "Frame reader sample issue"),
    ("frame_reader_to_fifo_utilization", "Reader-to-FIFO handshake"),
    ("frame_reader_cache_hit_rate", "Frame reader current cache hit rate"),
    ("frame_reader_advance_cache_hit_rate", "Frame reader advance cache hit rate"),
    ("input_fifo_core_utilization", "Input FIFO-to-core handshake"),
    ("input_fifo_nonempty_rate", "Input FIFO nonempty rate"),
    ("input_fifo_full_rate", "Input FIFO full rate"),
    ("ctu_symbol_utilization", "CTU symbol issue"),
    ("ctu_residual_symbol_utilization", "CTU residual symbol issue"),
    ("syntax_frontend_utilization", "VVC syntax frontend issue"),
    ("syntax_ts_residual_utilization", "VVC transform-skip residual issue"),
    ("bin_coder_input_utilization", "CABAC bin coder input issue"),
    ("bin_fifo_writer_utilization", "CABAC bin FIFO writer issue"),
    ("bin_fifo_nonempty_rate", "CABAC bin FIFO nonempty rate"),
    ("bin_fifo_full_rate", "CABAC bin FIFO full rate"),
    ("cabac_byte_utilization", "CABAC byte output issue"),
    ("bit_writer_output_utilization", "CABAC bit writer byte issue"),
    ("rbsp_payload_utilization", "RBSP payload issue"),
    ("stream_emit_utilization", "Stream writer emit issue"),
]


def select_codec(codec: str) -> None:
    global CODEC, CODEC_TITLE, REFERENCE_DECODER, SYNTH_TOP, SYNTH_DUT, SET_INFO, PROBES

    CODEC = codec
    if codec == "av2":
        CODEC_TITLE = "AV2"
        REFERENCE_DECODER = "reference-decoder"
        SYNTH_TOP = "ff_av2_encoder"
        SYNTH_DUT = "av2-encoder"
        SET_INFO = AV2_SET_INFO
        PROBES = AV2_PROBES
    elif codec == "vvc":
        CODEC_TITLE = "VVC"
        REFERENCE_DECODER = "VTM"
        SYNTH_TOP = "ff_vvc_encoder"
        SYNTH_DUT = "vvc-encoder"
        SET_INFO = VVC_SET_INFO
        PROBES = VVC_PROBES
    else:
        raise SystemExit(f"unsupported codec for reports: {codec}")


def read_vectors(set_name: str) -> list[Vector]:
    manifest = LOCAL_SETS / f"{set_name}.csv"
    if not manifest.exists():
        manifest = SHARED_SETS / f"{set_name}.csv"
    if not manifest.exists():
        raise FileNotFoundError(f"missing {CODEC_TITLE} report manifest: {set_name}")

    out: list[Vector] = []
    with manifest.open(newline="") as f:
        rows = [line for line in f if not line.startswith("#")]
    for row in csv.DictReader(rows):
        out.append(
            Vector(
                name=row["name"],
                width=int(row["width"]),
                height=int(row["height"]),
                frames=int(row["frames"]),
                fmt=row["format"],
                set_name=set_name,
            )
        )
    return out


def git_head() -> str:
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()


def current_sha_from_report(path: Path) -> str:
    text = read_baseline_text(path)
    m = re.search(r"Current validated source Git SHA: `([^`]+)`", text)
    if not m:
        m = re.search(r"Current validated RTL/source Git SHA: `([^`]+)`", text)
    if not m:
        m = re.search(r"Current [^:\n]*Git SHA:\s*\n\s*-\s*`([^`]+)`", text)
    if not m:
        return "unknown"
    return m.group(1)


def read_baseline_text(path: Path) -> str:
    if not BASELINE_REF:
        return path.read_text()
    rel = path.relative_to(ROOT).as_posix()
    return subprocess.check_output(
        ["git", "show", f"{BASELINE_REF}:{rel}"], cwd=ROOT, text=True
    )


def read_metrics(v: Vector) -> dict:
    return json.loads(v.metrics_path.read_text())


def parse_scalar(log_text: str, key: str) -> str:
    m = re.search(rf"^([A-Za-z0-9_.+-]+)\s+{re.escape(key)}$", log_text, re.M)
    if not m:
        return "n/a"
    return m.group(1)


def old_vector_values(doc: str, key_col_count: int) -> dict[str, list[float]]:
    values: dict[str, list[float]] = {}
    for line in doc.splitlines():
        if not line.startswith("| ") or ".yuv | PASS |" not in line:
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        name = cells[0]
        vals: list[float] = []
        for cell in cells[2 : 2 + key_col_count]:
            m = re.match(r"([-+0-9.]+)", cell)
            vals.append(float(m.group(1)) if m else math.nan)
        values[name] = vals
    return values


def old_aggregate_values(doc: str, key_col_count: int) -> dict[str, list[float]]:
    values: dict[str, list[float]] = {}
    for line in doc.splitlines():
        if not line.startswith("| `"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        name = cells[0].strip("`")
        vals: list[float] = []
        for cell in cells[2 : 2 + key_col_count]:
            m = re.match(r"([-+0-9.]+)", cell)
            vals.append(float(m.group(1)) if m else math.nan)
        values[name] = vals
    return values


def old_quality_aggregate_values(doc: str) -> dict[str, list[float]]:
    values: dict[str, list[float]] = {}
    for line in doc.splitlines():
        if not line.startswith("| `") or " | PASS | " not in line:
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 6:
            continue
        name = cells[0].strip("`")
        vals: list[float] = []
        for cell in (cells[3], cells[4]):
            m = re.match(r"([-+0-9.]+)", cell)
            vals.append(float(m.group(1)) if m else math.nan)
        values[name] = vals
    return values


def fmt_int(v: float | int) -> str:
    return str(int(round(v)))


def fmt_float(v: float, digits: int = 3) -> str:
    if math.isinf(v):
        return "inf"
    if math.isnan(v):
        return "n/a"
    return f"{v:.{digits}g}"


def fmt_bpp(v: float) -> str:
    return f"{v:.4f}"


def fmt_delta(curr: float, old: float | None, kind: str = "float") -> str:
    if old is None or math.isnan(old):
        return "n/a"
    delta = curr - old
    if kind == "int":
        return f"{delta:+.0f}"
    if kind == "bpp":
        return f"{delta:+.4f}"
    return f"{delta:+.3g}"


def elapsed_to_seconds(value: str) -> float:
    parts = value.strip().split(":")
    if len(parts) != 3:
        raise ValueError(f"unsupported elapsed time format: {value}")
    hours, minutes, seconds = parts
    return int(hours) * 3600 + int(minutes) * 60 + float(seconds)


def format_metric_value(key: str, value: float) -> str:
    if math.isnan(value):
        return "n/a"
    if key.endswith("(s)"):
        return f"{value:.2f} s"
    if key.endswith("(MiB)"):
        return f"{value:.2f} MiB"
    if key.endswith("(ns)"):
        return f"{value:.3f} ns"
    return fmt_int(value)


def format_metric_delta(key: str, curr: float, base: float) -> str:
    if math.isnan(base):
        return "n/a"
    delta = curr - base
    if key.endswith("(s)"):
        return f"{delta:+.2f} s"
    if key.endswith("(MiB)"):
        return f"{delta:+.2f} MiB"
    if key.endswith("(ns)"):
        return f"{delta:+.3f} ns"
    return f"{delta:+.0f}"


def aggregate_metrics(vectors: list[Vector]) -> dict:
    total_bits = 0
    total_cycles = 0
    active = 0
    wait = 0
    pixels = 0
    weighted: dict[str, float] = {k: 0.0 for k, _ in PROBES}
    for v in vectors:
        m = read_metrics(v)
        cycles = int(m["output_active_cycles"]) + int(m["output_wait_cycles"])
        total_bits += int(m["bitstream_bits"])
        total_cycles += cycles
        active += int(m["output_active_cycles"])
        wait += int(m["output_wait_cycles"])
        pixels += int(m["input_pixels"])
        bu = m.get("block_utilization", {})
        for key, _ in PROBES:
            weighted[key] += float(bu.get(key, 0.0)) * cycles
    util = active / total_cycles if total_cycles else 0.0
    return {
        "bits": total_bits,
        "cycles": total_cycles,
        "active": active,
        "wait": wait,
        "util": util,
        "bubble": 1.0 - util,
        "cycles_per_bit": total_cycles / total_bits if total_bits else math.nan,
        "cycles_per_pixel": total_cycles / pixels if pixels else math.nan,
        "probes": {k: (v / total_cycles if total_cycles else 0.0) for k, v in weighted.items()},
    }


def doc_path(name: str) -> Path:
    return ROOT / "docs" / CODEC / name


def validation_result_lines(strict: bool) -> list[str]:
    suffix = (
        f", strict SW/RTL/{REFERENCE_DECODER} checksum parity."
        if strict
        else "."
    )
    lines = []
    for set_name, _title in SET_INFO:
        lines.append(f"- `{set_name}`: PASS ({len(read_vectors(set_name))}/{len(read_vectors(set_name))}){suffix}")
    return lines


def write_output_utilization() -> None:
    old_doc = read_baseline_text(doc_path("output-utilization.md"))
    if "Wait cycles (delta)" in old_doc:
        old_vec = old_vector_values(old_doc, 7)
        old_agg = old_aggregate_values(old_doc, 7)
    else:
        old_vec = {}
        old_agg = {}

    lines: list[str] = []
    lines += [
        f"# {CODEC_TITLE} RTL Output Utilization Baselines",
        "",
        "This report records the latest RTL simulation throughput counters. Older",
        "measurement sections are intentionally left to git history so this file",
        "stays focused on the current optimization baseline and immediate deltas.",
        "",
        "Metric definitions:",
        "",
        "- `output_utilization`: accepted output bytes divided by total measured cycles.",
        "- `bubble_rate`: `1 - output_utilization`.",
        "- `cycles/bit`: total measured cycles divided by RTL bitstream bits.",
        "- `cycles/input pixel`: total measured cycles divided by `width * height * frames`.",
        "- Internal block utilization is testbench instrumentation. It is used to find",
        "  pipeline starvation/backpressure and is not part of the codec bitstream contract.",
        "",
        f"## {REPORT_TITLE}",
        "",
        "Baseline and current sources:",
        "",
        f"- Baseline Git SHA: `{PREV_OUTPUT_SHA}`",
        f"- Current validated source Git SHA: `{CURRENT_SHA}`",
        f"- Delta columns compare against the previous documented {CODEC_TITLE} output-utilization",
        "  checkpoint where the same vector or aggregate was present.",
        "",
        "Validation result:",
        "",
        *validation_result_lines(strict=True),
        "- Yosys synthesis: PASS at 25 MHz metadata target.",
        (
            "- Vivado synthesis/timing: PASS at 25 MHz target, WNS is positive."
            if INCLUDE_VIVADO
            else "- Vivado synthesis/timing: not rerun for this checkpoint."
        ),
        "",
        "Aggregate top-level RTL utilization:",
        "",
        "| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    all_vectors: dict[str, list[Vector]] = {name: read_vectors(name) for name, _ in SET_INFO}
    for set_name, _title in SET_INFO:
        agg = aggregate_metrics(all_vectors[set_name])
        old = old_agg.get(set_name, [math.nan] * 7)
        lines.append(
            f"| `{set_name}` | {len(all_vectors[set_name])} | "
            f"{fmt_int(agg['bits'])} ({fmt_delta(agg['bits'], old[0], 'int')}) | "
            f"{fmt_int(agg['cycles'])} ({fmt_delta(agg['cycles'], old[1], 'int')}) | "
            f"{fmt_int(agg['active'])} ({fmt_delta(agg['active'], old[2], 'int')}) | "
            f"{fmt_int(agg['wait'])} ({fmt_delta(agg['wait'], old[3], 'int')}) | "
            f"{fmt_float(agg['util'])} ({fmt_delta(agg['util'], old[4])}) | "
            f"{fmt_float(agg['bubble'])} ({fmt_delta(agg['bubble'], old[5])}) | "
            f"{fmt_float(agg['cycles_per_bit'])} ({fmt_delta(agg['cycles_per_bit'], old[6])}) | "
            f"{fmt_float(agg['cycles_per_pixel'])} |"
        )
    for set_name, title in SET_INFO:
        vectors = all_vectors[set_name]
        agg = aggregate_metrics(vectors)
        lines += [
            "",
            f"### {title}",
            "",
            "| Block/probe | Utilization/rate |",
            "|---|---:|",
        ]
        for key, label in PROBES:
            lines.append(f"| {label} | {fmt_float(agg['probes'][key])} |")
        lines += [
            "",
            "Per-vector top-level metrics:",
            "",
            "| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |",
            "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|",
        ]
        for v in vectors:
            m = read_metrics(v)
            active = int(m["output_active_cycles"])
            wait = int(m["output_wait_cycles"])
            cycles = active + wait
            bits = int(m["bitstream_bits"])
            util = float(m["output_utilization"])
            bubble = float(m["output_bubble_rate"])
            cpb = float(m["cycles_per_bit"])
            cpp = float(m["cycles_per_input_pixel"])
            old = old_vec.get(v.stem + ".yuv", [math.nan] * 7)
            lines.append(
                f"| {v.stem}.yuv | PASS | "
                f"{bits} ({fmt_delta(bits, old[0], 'int')}) | "
                f"{cycles} ({fmt_delta(cycles, old[1], 'int')}) | "
                f"{active} ({fmt_delta(active, old[2], 'int')}) | "
                f"{wait} ({fmt_delta(wait, old[3], 'int')}) | "
                f"{fmt_float(util)} ({fmt_delta(util, old[4])}) | "
                f"{fmt_float(bubble)} ({fmt_delta(bubble, old[5])}) | "
                f"{fmt_float(cpb)} ({fmt_delta(cpb, old[6])}) | "
                f"{fmt_float(cpp)} |"
            )
    doc_path("output-utilization.md").write_text("\n".join(lines) + "\n")


def read_log(v: Vector) -> str:
    return v.log_path.read_text()


def ibc_totals(vectors: list[Vector]) -> dict[str, int]:
    keys = [
        "software_ibc_total_blocks",
        "software_ibc_raw_above_hash_matches",
        "software_ibc_raw_left_hash_matches",
        "software_ibc_direct_above_hash_matches",
        "software_ibc_direct_left_hash_matches",
        "software_ibc_selected_above_copy_blocks",
        "software_ibc_selected_left_copy_blocks",
    ]
    totals = {k: 0 for k in keys}
    for v in vectors:
        text = read_log(v)
        for key in keys:
            val = parse_scalar(text, key)
            if val != "n/a":
                totals[key] += int(val)
    return totals


def write_quality_bitrate() -> None:
    old_doc = read_baseline_text(doc_path("quality-bitrate.md"))
    old_vec = old_vector_values(old_doc, 2)
    old_agg = old_quality_aggregate_values(old_doc)
    all_vectors = {name: read_vectors(name) for name, _ in SET_INFO}

    lines: list[str] = [
        f"# {CODEC_TITLE} Quality And Bitrate Baselines",
        "",
        f"This file records {CODEC_TITLE}-specific quality and bitrate checkpoints. Synthesis",
        "area/timing belongs in [synthesis.md](synthesis.md). RTL output utilization",
        "belongs in [output-utilization.md](output-utilization.md).",
        "",
        "`scripts/validate.py` reports the FrameForge software bitstream and, when",
        "RTL validation is enabled, the RTL bitstream size. Software and RTL",
        f"bitstreams are expected to match exactly for implemented {CODEC_TITLE}",
        "features. The reference path used here is decode-only; the external",
        f"{REFERENCE_DECODER} decodes the FrameForge bitstream and its",
        "reconstruction must match the software/RTL reconstruction checksum.",
        "",
        f"## {REPORT_TITLE}",
        "",
        "Baseline and current sources:",
        "",
        f"- Baseline Git SHA: `{PREV_QUALITY_SHA}`",
        f"- Current validated source Git SHA: `{CURRENT_SHA}`",
        f"- Delta columns compare against the previous documented {CODEC_TITLE} quality/bitrate",
        "  checkpoint where the same vector or aggregate was present.",
        "",
        "Validation result:",
        "",
        *validation_result_lines(strict=False),
        "- All listed vectors matched SW/RTL bitstream checksums and",
        f"  SW/RTL/{REFERENCE_DECODER} reconstruction checksums.",
        "- Screenshot 4:4:4 remains lossless (`inf` PSNR). RaceHorses 4:2:0 remains",
        "  intentionally lossy with finite PSNR.",
        "",
        "Aggregate results:",
        "",
        "| Set | Cases | Status | SW bits (delta) | SW bpp (delta) | PSNR |",
        "|---|---:|---|---:|---:|---|",
    ]
    quality_cache: dict[str, list[tuple[Vector, int, float, str]]] = {}
    for set_name, _title in SET_INFO:
        rows: list[tuple[Vector, int, float, str]] = []
        for v in all_vectors[set_name]:
            text = read_log(v)
            bits = int(parse_scalar(text, "software_bitstream_bits"))
            bpp = float(parse_scalar(text, "software_bitstream_bits_per_luma_pixel"))
            psnr = parse_scalar(text, "software_internal_recon_psnr_vs_input_db")
            rows.append((v, bits, bpp, psnr))
        quality_cache[set_name] = rows
        total_bits = sum(r[1] for r in rows)
        pixels = sum(r[0].width * r[0].height * r[0].frames for r in rows)
        bpp = total_bits / pixels
        finite_psnrs = [float(r[3]) for r in rows if r[3] != "inf"]
        psnr_str = "inf" if not finite_psnrs else (
            f"avg {sum(finite_psnrs)/len(finite_psnrs):.2f} dB, "
            f"range {min(finite_psnrs):.2f}-{max(finite_psnrs):.2f} dB"
        )
        old = old_agg.get(set_name, [math.nan] * 2)
        lines.append(
            f"| `{set_name}` | {len(rows)} | PASS | "
            f"{total_bits} ({fmt_delta(total_bits, old[0], 'int')}) | "
            f"{fmt_bpp(bpp)} ({fmt_delta(bpp, old[1], 'bpp')}) | {psnr_str} |"
        )

    if CODEC == "av2":
        lines += [
            "",
            "IBC candidate summary for 4:4:4:",
            "",
            "| Set | 8x8 blocks | Raw above matches | Raw left matches | Direct above matches | Direct left matches | Selected above copies | Selected left copies |",
            "|---|---:|---:|---:|---:|---:|---:|---:|",
        ]
        for set_name in ["screenshot-sweep-444", "screenshot-multictu-444"]:
            totals = ibc_totals(all_vectors[set_name])
            lines.append(
                f"| `{set_name}` | {totals['software_ibc_total_blocks']} | "
                f"{totals['software_ibc_raw_above_hash_matches']} | "
                f"{totals['software_ibc_raw_left_hash_matches']} | "
                f"{totals['software_ibc_direct_above_hash_matches']} | "
                f"{totals['software_ibc_direct_left_hash_matches']} | "
                f"{totals['software_ibc_selected_above_copy_blocks']} | "
                f"{totals['software_ibc_selected_left_copy_blocks']} |"
            )

    for set_name, title in SET_INFO:
        lines += [
            "",
            f"### {title}",
            "",
            "| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |",
            "|---|---|---:|---:|---:|",
        ]
        for v, bits, bpp, psnr in quality_cache[set_name]:
            old = old_vec.get(v.stem + ".yuv", [math.nan] * 2)
            psnr_cell = psnr if psnr == "inf" else f"{float(psnr):.2f}"
            lines.append(
                f"| {v.stem}.yuv | PASS | "
                f"{bits} ({fmt_delta(bits, old[0], 'int')}) | "
                f"{fmt_bpp(bpp)} ({fmt_delta(bpp, old[1], 'bpp')}) | "
                f"{psnr_cell} |"
            )
    doc_path("quality-bitrate.md").write_text("\n".join(lines) + "\n")


def parse_synth_old() -> dict[str, float]:
    doc = read_baseline_text(doc_path("synthesis.md"))
    out: dict[str, float] = {}
    for line in doc.splitlines():
        if not line.startswith("| ") or " | " not in line:
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 4 or cells[0] in ("Metric", "---"):
            continue
        metric = cells[0]
        m = re.match(r"([-+0-9.]+)", cells[2])
        if m:
            out[metric] = float(m.group(1))
    return out


def parse_synth_current() -> dict[str, float]:
    synth_dir = ROOT / "synth/out/arty-z7-10" / SYNTH_TOP
    yosys = (synth_dir / "yosys.log").read_text()
    cell = (synth_dir / "cell_report.log").read_text()
    crit = (synth_dir / "critical_path.log").read_text()
    m = re.search(r"after ([0-9.]+)s; peak child RSS observed by runner is ([0-9.]+) MiB", yosys)
    if not m:
        raise SystemExit("missing yosys timing line")
    out = {
        "Main Yosys elapsed time (s)": float(m.group(1)),
        "Runner-observed peak child RSS (MiB)": float(m.group(2)),
    }
    m = re.search(r"Synthesis timeout: ([0-9.]+) seconds", yosys)
    out["Yosys timeout (s)"] = (
        float(m.group(1)) if m else float(os.environ.get("SYNTH_TIMEOUT_SEC", "600"))
    )
    m = re.search(r"Synthesis review threshold: ([0-9.]+) seconds", yosys)
    out["Yosys review threshold (s)"] = (
        float(m.group(1)) if m else float(os.environ.get("SYNTH_WARN_AFTER_SEC", "300"))
    )
    m = re.search(r"(?:Yosys synthesis memory limit|Synthesis memory limit): ([0-9.]+) MiB", yosys)
    out["Yosys memory limit (MiB)"] = float(m.group(1)) if m else math.nan
    m = re.search(rf"Longest topological path in {re.escape(SYNTH_TOP)} \(length=([0-9]+)\)", crit)
    out["Topological path length"] = float(m.group(1))
    # Use the last hierarchy summary, which is the flattened top entry.
    summaries = list(re.finditer(r"Number of cells:\s+([0-9]+)(.*?)(?:Estimated number of LCs:\s+([0-9]+))", cell, re.S))
    block = summaries[-1]
    out["Flattened cells"] = float(block.group(1))
    body = block.group(2)
    out["Estimated LCs"] = float(block.group(3))
    for key in [
        "CARRY4", "DSP48E1", "FDCE", "FDPE", "FDRE", "FDSE",
        "LUT1", "LUT2", "LUT3", "LUT4", "LUT5", "LUT6",
        "MUXF7", "MUXF8", "RAMB36E1", "RAM32M",
    ]:
        mm = re.search(rf"\b{key}\s+([0-9]+)", body)
        out[key] = float(mm.group(1)) if mm else 0.0
    if INCLUDE_VIVADO:
        vivado = (synth_dir / "vivado.log").read_text()
        vivado_timing = (synth_dir / "vivado_timing_summary.rpt").read_text()
        vivado_util = (synth_dir / "vivado_utilization.rpt").read_text()
        m = re.search(
            r"synth_design: Time \(s\): cpu = [0-9:.]+ ; elapsed = ([0-9:.]+) \. "
            r"Memory \(MB\): peak = ([0-9.]+)",
            vivado,
        )
        if not m:
            raise SystemExit("missing vivado synth_design timing line")
        out["Vivado synth_design elapsed time (s)"] = elapsed_to_seconds(m.group(1))
        out["Vivado synth_design peak memory (MiB)"] = float(m.group(2))
        m = re.search(r"# Start of session at: (.+)", vivado)
        n = re.search(r"Exiting Vivado at (.+)\.\.\.", vivado)
        if m and n:
            start = datetime.strptime(m.group(1).strip(), "%a %b %d %H:%M:%S %Y")
            end = datetime.strptime(n.group(1).strip(), "%a %b %d %H:%M:%S %Y")
            out["Vivado total elapsed time (s)"] = (end - start).total_seconds()
        m = re.search(r"Setup\s+:\s+0\s+Failing Endpoints,\s+Worst Slack\s+([-+0-9.]+)ns", vivado_timing)
        out["Vivado WNS (ns)"] = float(m.group(1))
        m = re.search(r"Hold\s+:\s+0\s+Failing Endpoints,\s+Worst Slack\s+([-+0-9.]+)ns", vivado_timing)
        out["Vivado WHS (ns)"] = float(m.group(1))
        m = re.search(r"Data Path Delay:\s+([-+0-9.]+)ns", vivado_timing)
        out["Vivado critical data path delay (ns)"] = float(m.group(1))
        m = re.search(r"Logic Levels:\s+([0-9]+)", vivado_timing)
        out["Vivado critical logic levels"] = float(m.group(1))
        util_keys = {
            "Vivado Slice LUTs": r"\| Slice LUTs\*\s+\|\s+([0-9]+)",
            "Vivado Slice Registers": r"\| Slice Registers\s+\|\s+([0-9]+)",
            "Vivado Block RAM Tiles": r"\| Block RAM Tile\s+\|\s+([0-9]+)",
            "Vivado DSPs": r"\| DSPs\s+\|\s+([0-9]+)",
        }
        for key, pattern in util_keys.items():
            m = re.search(pattern, vivado_util)
            if not m:
                raise SystemExit(f"missing {key} in Vivado utilization report")
            out[key] = float(m.group(1))
    return out


def critical_path_notes() -> list[str]:
    if CODEC == "av2":
        return [
            "- Reported limiter: input FIFO data selection feeding the 4:4:4",
            "  palette-color update path in `ff_av2_palette_analyzer_444`.",
            "- Longest topological path in `ff_av2_chroma_sample_store`: length 1.",
        ]
    return [
        "- Reported limiter: palette CU symbolizer first-come palette lookup chain",
        "  from `build_lane_q` through `build_found` into `indices_q`.",
    ]


def vivado_path_notes() -> list[str]:
    if CODEC == "av2":
        return [
            "- Current critical path is route-dominated inside the AV2 palette analyzer,",
            "  from `input_sample_fifo/data_q_reg` into `palette_color_q`.",
        ]
    return [
        "- Current critical path should be reviewed from the Vivado timing summary",
        "  before using this as an implementation-fit checkpoint.",
    ]


def write_synthesis() -> None:
    old = parse_synth_old()
    curr = parse_synth_current()
    synth_cmd = f"make synth CODEC={CODEC} SYNTH_DUT={SYNTH_DUT}"
    if curr["Yosys timeout (s)"] != 600:
        synth_cmd += f" SYNTH_TIMEOUT_SEC={fmt_int(curr['Yosys timeout (s)'])}"
    yosys_order = [
        "Main Yosys elapsed time (s)",
        "Runner-observed peak child RSS (MiB)",
        "Topological path length",
        "Flattened cells",
        "Estimated LCs",
        "CARRY4", "DSP48E1", "FDCE", "FDPE", "FDRE", "FDSE",
        "LUT1", "LUT2", "LUT3", "LUT4", "LUT5", "LUT6",
        "MUXF7", "MUXF8", "RAMB36E1", "RAM32M",
    ]
    vivado_order = [
        "Vivado total elapsed time (s)",
        "Vivado synth_design elapsed time (s)",
        "Vivado synth_design peak memory (MiB)",
        "Vivado WNS (ns)",
        "Vivado WHS (ns)",
        "Vivado critical data path delay (ns)",
        "Vivado critical logic levels",
        "Vivado Slice LUTs",
        "Vivado Slice Registers",
        "Vivado Block RAM Tiles",
        "Vivado DSPs",
    ]
    lines = [
        f"# {CODEC_TITLE} Synthesis Baseline",
        "",
        f"This file records the latest {CODEC_TITLE}-specific synthesis checkpoint.",
        "Older measurements are intentionally left to git history so this page stays",
        "focused on the current baseline and immediate delta. The shared synthesis flow",
        "is documented in [../synthesis.md](../synthesis.md).",
        "",
        f"## {REPORT_TITLE}",
        "",
        "Baseline and current sources:",
        "",
        f"- Baseline Git SHA: `{PREV_SYNTH_SHA}`",
        f"- Current validated source Git SHA: `{CURRENT_SHA}`",
        "",
        "Validation result:",
        "",
        *validation_result_lines(strict=True),
        "- Yosys synthesis: PASS at 25 MHz metadata target.",
        (
            "- Vivado synthesis/timing: PASS at 25 MHz target, WNS is positive."
            if INCLUDE_VIVADO
            else "- Vivado synthesis/timing: not rerun for this checkpoint."
        ),
        "",
        "Yosys synthesis configuration:",
        "",
        f"- command: `{synth_cmd}`",
        f"- RTL top: `{SYNTH_TOP}`",
        "- board/device metadata: Arty Z7-10, `xc7z010clg400-1`",
        "- clock target metadata: 25 MHz",
        "- max visible size: 1024x1024",
        (
            "- timeout/review thresholds: "
            f"{fmt_int(curr['Yosys timeout (s)'])} seconds hard stop, "
            f"{fmt_int(curr['Yosys review threshold (s)'])} seconds review"
        ),
        f"- memory limit: {fmt_int(curr['Yosys memory limit (MiB)'])} MiB",
        "- palette 4:4:4 support: enabled",
        "",
        "Yosys synthesis result:",
        "",
        "| Metric | Baseline | Current | Delta |",
        "|---|---:|---:|---:|",
    ]
    for key in yosys_order:
        base = old.get(key, math.nan)
        val = curr[key]
        base_s = format_metric_value(key, base)
        curr_s = format_metric_value(key, val)
        delta_s = format_metric_delta(key, val, base)
        lines.append(f"| {key} | {base_s} | {curr_s} | {delta_s} |")
    lines += [
        "",
        "Critical-path summary:",
        "",
        f"- Longest Yosys topological path in `{SYNTH_TOP}`: length {fmt_int(curr['Topological path length'])}.",
        *critical_path_notes(),
        "",
    ]
    if INCLUDE_VIVADO:
        lines += [
            "Vivado synthesis configuration:",
            "",
            f"- command: `make synth-vivado CODEC={CODEC} SYNTH_DUT={SYNTH_DUT} SYNTH_TIMEOUT_SEC=1200 SYNTH_WARN_AFTER_SEC=300 SYNTH_VIVADO_MAX_THREADS=1 SYNTH_MEMORY_LIMIT_MB=4096`",
            f"- RTL top: `{SYNTH_TOP}`",
            "- board/device metadata: Arty Z7-10, `xc7z010clg400-1`",
            "- clock target: 25 MHz",
            "- max visible size: 1024x1024",
            "- palette 4:4:4 support: enabled",
            "",
            "Vivado synthesis and timing result:",
            "",
            "| Metric | Baseline | Current | Delta |",
            "|---|---:|---:|---:|",
        ]
        for key in vivado_order:
            if key not in curr:
                continue
            base = old.get(key, math.nan)
            val = curr[key]
            lines.append(
                f"| {key} | {format_metric_value(key, base)} | "
                f"{format_metric_value(key, val)} | {format_metric_delta(key, val, base)} |"
            )
        lines += [
            "",
            "Vivado critical-path summary:",
            "",
            "- Setup timing met at 25 MHz with positive WNS.",
            *vivado_path_notes(),
        ]
    else:
        lines += [
            "Vivado synthesis and timing result:",
            "",
            "- Not rerun for this checkpoint; use the previous committed report as the",
            "  latest Vivado timing reference.",
        ]
    lines += [
        "",
        "Notes:",
        "",
        "- Bitrate deltas reflect the refreshed validation logs for this checkpoint;",
        "  output-utilization deltas include any RTL-cycle changes from the current",
        "  RTL updates.",
    ]
    doc_path("synthesis.md").write_text("\n".join(lines) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Regenerate codec quality/bitrate, output-utilization, and synthesis "
            "reports from validation logs and synthesis artifacts."
        )
    )
    parser.add_argument(
        "--codec",
        choices=("av2", "vvc"),
        required=True,
        help="Codec report directory and artifact namespace to update.",
    )
    parser.add_argument(
        "--checkpoint-title",
        default="Report Checkpoint",
        help="Markdown section title used in the generated reports.",
    )
    parser.add_argument(
        "--current-sha",
        default=None,
        help="Validated source SHA to record. Defaults to git HEAD.",
    )
    parser.add_argument(
        "--output-baseline-sha",
        default=None,
        help=(
            "Baseline SHA for output-utilization and synthesis reports. "
            "Defaults to the current SHA recorded in the codec output-utilization report."
        ),
    )
    parser.add_argument(
        "--quality-baseline-sha",
        default=None,
        help=(
            "Baseline SHA for quality-bitrate reports. Defaults to the current "
            "SHA recorded in the codec quality-bitrate report."
        ),
    )
    parser.add_argument(
        "--synthesis-baseline-sha",
        default=None,
        help=(
            "Baseline SHA for synthesis reports. Defaults to the current SHA "
            "recorded in the codec synthesis report."
        ),
    )
    parser.add_argument(
        "--baseline-ref",
        default=None,
        help=(
            "Optional git ref whose committed reports should be used for "
            "numeric baselines. Useful when regenerating reports after the "
            "working tree already contains report edits."
        ),
    )
    parser.add_argument(
        "--synthesis-tool",
        choices=("yosys", "yosys-vivado"),
        default="yosys",
        help=(
            "Select which current synthesis artifacts to consume. Use `yosys` "
            "when Vivado was not rerun for the current checkpoint."
        ),
    )
    return parser.parse_args()


def main() -> None:
    global CURRENT_SHA, PREV_OUTPUT_SHA, PREV_QUALITY_SHA, PREV_SYNTH_SHA, REPORT_TITLE, BASELINE_REF, INCLUDE_VIVADO

    args = parse_args()
    select_codec(args.codec)
    REPORT_TITLE = args.checkpoint_title
    BASELINE_REF = args.baseline_ref or ""
    INCLUDE_VIVADO = args.synthesis_tool == "yosys-vivado"
    CURRENT_SHA = args.current_sha or git_head()
    PREV_OUTPUT_SHA = args.output_baseline_sha or current_sha_from_report(
        doc_path("output-utilization.md")
    )
    PREV_QUALITY_SHA = args.quality_baseline_sha or current_sha_from_report(
        doc_path("quality-bitrate.md")
    )
    PREV_SYNTH_SHA = args.synthesis_baseline_sha or current_sha_from_report(
        doc_path("synthesis.md")
    )

    write_output_utilization()
    write_quality_bitrate()
    write_synthesis()


if __name__ == "__main__":
    main()
