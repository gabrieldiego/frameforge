#!/usr/bin/env python3
"""Run a narrow VTM decode plus RTL synthesis checkpoint.

This intentionally does not claim the RTL top emits the full VVC Annex-B stream.
It checks the current standards-facing software stream against VTM, then checks
that a selected synthesizable RTL block still passes synthesis.
"""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
from pathlib import Path

import validate as frameforge_validate


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = Path("verification/generated/vtm-synth")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="input YUV file")
    parser.add_argument("--width", type=int)
    parser.add_argument("--height", type=int)
    parser.add_argument("--frames", type=int)
    parser.add_argument("--format")
    parser.add_argument("--max-width", type=int, default=64)
    parser.add_argument("--max-height", type=int, default=64)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--synth-dut", default="vvc-cabac-pipeline")
    parser.add_argument(
        "--synth-backend",
        choices=("yosys", "vivado-remote", "none"),
        default="yosys",
        help="synthesis backend to run after VTM decode comparison",
    )
    parser.add_argument("--clock-mhz", type=float, default=50.0)
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    if not input_path.exists():
        print(f"FAIL: input YUV file does not exist: {input_path}", file=sys.stderr)
        return 2

    try:
        info = frameforge_validate.resolve_input_info(input_path, args)
        frameforge_validate.validate_supported_input(
            input_path, info, args.max_width, args.max_height
        )
    except ValueError as err:
        print(f"FAIL: {err}", file=sys.stderr)
        return 2

    if not frameforge_validate.vtm_decode_supported(input_path, info):
        print(
            f"FAIL: VTM decode comparison is not wired for {info.width}x{info.height} {info.fmt}",
            file=sys.stderr,
        )
        return 2

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = f"{input_path.stem}_{info.width}x{info.height}_{info.frames}f_{info.fmt}"
    bitstream = out_dir / f"{stem}_software.vvc"
    internal_recon = out_dir / f"{stem}_software_internal_rec.yuv"
    vtm_recon = out_dir / f"{stem}_vtm_decoded_rec.yuv"

    run(
        [
            "cargo",
            "run",
            "--quiet",
            "--",
            "vvc-encode",
            "--input",
            str(input_path),
            "--frames",
            str(info.frames),
            "--width",
            str(info.width),
            "--height",
            str(info.height),
            "--format",
            info.fmt,
            "--output",
            str(bitstream),
            "--recon",
            str(internal_recon),
        ]
    )
    run(
        [
            sys.executable,
            "scripts/validate_decode.py",
            str(bitstream),
            "--output",
            str(vtm_recon),
        ]
    )

    internal_digest = sha256(internal_recon)
    vtm_digest = sha256(vtm_recon)
    bitstream_digest = sha256(bitstream)
    print("FrameForge VTM+synthesis checkpoint")
    print(
        f"input={input_path} width={info.width} height={info.height} "
        f"frames={info.frames} format={info.fmt}"
    )
    print(f"{bitstream_digest}  software_bitstream")
    print(f"{internal_digest}  software_internal_recon")
    print(f"{vtm_digest}  vtm_recon_from_software_bitstream")
    if internal_digest != vtm_digest:
        print("FAIL: software internal reconstruction and VTM reconstruction differ", file=sys.stderr)
        return 1
    print("OK: software reconstruction matches VTM reconstruction")

    if args.synth_backend == "yosys":
        run(["make", "synth", f"SYNTH_DUT={args.synth_dut}", f"SYNTH_CLOCK_MHZ={args.clock_mhz:g}"])
    elif args.synth_backend == "vivado-remote":
        run(
            [
                "make",
                "synth-vivado-remote",
                f"SYNTH_DUT={args.synth_dut}",
                f"SYNTH_CLOCK_MHZ={args.clock_mhz:g}",
            ]
        )
    else:
        print("SKIP: synthesis backend disabled")
        return 0

    print(f"OK: synthesis checkpoint passed for {args.synth_dut} using {args.synth_backend}")
    return 0


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
