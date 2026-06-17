#!/usr/bin/env python3
"""Run named FrameForge validation sets generated on demand."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import re
from dataclasses import dataclass
from pathlib import Path

from codec_config import add_codec_arg, codec_config_from_args
import generate_test_vectors


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_VECTOR_DIR = Path("verification/generated/test_vectors")
DEFAULT_LOG_DIR = Path("verification/generated/validation_logs")


@dataclass
class ValidationResult:
    path: Path
    status: str
    reason: str
    log_path: Path
    bitrate_delta: str = "n/a"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    add_codec_arg(parser)
    parser.add_argument("set", help="named vector set manifest to generate and validate")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_VECTOR_DIR)
    parser.add_argument("--set-dir", type=Path, default=generate_test_vectors.DEFAULT_SET_DIR)
    parser.add_argument("--log-dir", type=Path, default=DEFAULT_LOG_DIR)
    parser.add_argument("--max-width", type=int, default=64)
    parser.add_argument("--max-height", type=int, default=64)
    parser.add_argument("--limit", type=int, default=0, help="run only the first N cases")
    parser.add_argument("--with-synth", action="store_true", help="run synthesis inside each validate call")
    parser.add_argument("--sw-only", action="store_true", help="run software/VTM validation only")
    parser.add_argument("--stop-on-fail", action="store_true")
    args = parser.parse_args()
    codec = codec_config_from_args(args)
    args.codec_config = codec

    vector_paths = generate_test_vectors.generate_vectors(args.set, args.out_dir, args.set_dir)
    if args.limit:
        vector_paths = vector_paths[: args.limit]

    args.log_dir.mkdir(parents=True, exist_ok=True)
    results: list[ValidationResult] = []
    for index, path in enumerate(vector_paths, start=1):
        print(f"[{index:03d}/{len(vector_paths):03d}] {path.name}", flush=True)
        result = run_validation(path, args)
        results.append(result)
        print(
            f"  {result.status}: {result.reason} "
            f"(bitrate delta: {result.bitrate_delta})",
            flush=True,
        )
        if result.status != "PASS" and args.stop_on_fail:
            break

    passed = [result for result in results if result.status == "PASS"]
    bitrates = [extract_bpp_delta(result.bitrate_delta) for result in passed]
    comparable = [value for value in bitrates if value is not None]

    print()
    print(f"FrameForge validation set: {args.set}")
    print("| # | vector | result | bitrate_delta | reason | log |")
    print("|---:|---|---|---:|---|---|")
    for index, result in enumerate(results, start=1):
        resolved_log = result.log_path.resolve()
        try:
            rel_log = resolved_log.relative_to(REPO_ROOT)
        except ValueError:
            rel_log = resolved_log
        print(
            f"| {index} | {result.path.name} | {result.status} | {result.bitrate_delta} | "
            f"{markdown_escape(result.reason)} | {rel_log} |"
        )

    failed = [result for result in results if result.status != "PASS"]
    if comparable:
        avg_delta = sum(comparable) / len(comparable)
        min_delta = min(comparable)
        max_delta = max(comparable)
        print(
            f"\nSet bitrate summary (software vs compare stream, bpp): "
            f"avg={avg_delta:.4f} min={min_delta:.4f} max={max_delta:.4f}"
        )
    if failed:
        print(f"\nFAIL: {len(failed)} of {len(results)} validation case(s) failed", file=sys.stderr)
        return 1
    print(f"\nOK: {len(results)} validation case(s) passed")
    return 0


def run_validation(path: Path, args: argparse.Namespace) -> ValidationResult:
    log_path = args.log_dir / f"{args.set}_{path.stem}.log"
    cmd = [
        sys.executable,
        "scripts/validate.py",
        "--codec",
        args.codec_config.name,
        str(path),
        "--max-width",
        str(args.max_width),
        "--max-height",
        str(args.max_height),
    ]
    if not args.with_synth:
        cmd.append("--skip-synth")
    if args.sw_only:
        cmd.append("--sw-only")

    env = os.environ.copy()
    process = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    log_path.write_text(process.stdout)
    bitrate_delta = extract_bitrate_delta(process.stdout, args.codec_config.name)
    if process.returncode == 0:
        reason = (
            "SW/reference-decoder checksum checks passed"
            if args.sw_only
            else "SW/RTL/reference-decoder checksum checks passed"
        )
        return ValidationResult(
            path=path,
            status="PASS",
            reason=reason,
            log_path=log_path,
            bitrate_delta=bitrate_delta,
        )
    return ValidationResult(
        path=path,
        status="FAIL",
        reason=extract_failure_reason(process.stdout),
        log_path=log_path,
        bitrate_delta=bitrate_delta,
    )


def extract_failure_reason(output: str) -> str:
    markers = ("FAIL:", "AssertionError:", "ValueError:", "Error:", "error:")
    for line in output.splitlines():
        stripped = line.strip()
        if any(marker in stripped for marker in markers):
            return stripped
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    return lines[-1] if lines else "validation command failed"


def markdown_escape(value: str) -> str:
    return value.replace("|", "\\|")


def extract_bitrate_delta(output: str, codec: str) -> str:
    metrics = parse_bitrate_metrics(output)
    software_bpp = metrics.get("software_bitstream")
    if software_bpp is None:
        return "n/a"

    compare = None
    compare_order = ("rtl_bitstream", "ref_bitstream")
    for candidate in compare_order:
        if candidate in metrics:
            compare = candidate
            break

    if compare is None:
        return "n/a"
    compare_bpp = metrics[compare]
    delta = compare_bpp - software_bpp
    if software_bpp == 0:
        return "n/a"
    pct = (delta / software_bpp) * 100.0
    return f"{delta:+.4f} ({pct:+.2f}%)"


def extract_bpp_delta(text: str) -> float | None:
    if text == "n/a":
        return None
    match = re.match(r"(?P<delta>[+-]?[0-9]+(?:\.[0-9]+)?)", text)
    if not match:
        return None
    return float(match.group("delta"))


def parse_bitrate_metrics(output: str) -> dict[str, float]:
    bpp_pattern = re.compile(r"^\s*([0-9]+(?:\.[0-9]+)?)\s+([a-z0-9_]+)_bits_per_luma_pixel\s*$")
    metrics: dict[str, float] = {}
    for line in output.splitlines():
        match = bpp_pattern.match(line.strip())
        if not match:
            continue
        value = float(match.group(1))
        label = match.group(2)
        metrics[label] = value
    return metrics


if __name__ == "__main__":
    raise SystemExit(main())
