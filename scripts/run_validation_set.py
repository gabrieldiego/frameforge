#!/usr/bin/env python3
"""Run named FrameForge validation sets generated on demand."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
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
        print(f"  {result.status}: {result.reason}", flush=True)
        if result.status != "PASS" and args.stop_on_fail:
            break

    print()
    print(f"FrameForge validation set: {args.set}")
    print("| # | vector | result | reason | log |")
    print("|---:|---|---|---|---|")
    for index, result in enumerate(results, start=1):
        rel_log = result.log_path.resolve().relative_to(REPO_ROOT)
        print(
            f"| {index} | {result.path.name} | {result.status} | "
            f"{markdown_escape(result.reason)} | {rel_log} |"
        )

    failed = [result for result in results if result.status != "PASS"]
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
    if process.returncode == 0:
        reason = "SW/REF checks passed" if args.sw_only else "SW/RTL/REF checks passed"
        return ValidationResult(
            path=path,
            status="PASS",
            reason=reason,
            log_path=log_path,
        )
    return ValidationResult(
        path=path,
        status="FAIL",
        reason=extract_failure_reason(process.stdout),
        log_path=log_path,
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


if __name__ == "__main__":
    raise SystemExit(main())
