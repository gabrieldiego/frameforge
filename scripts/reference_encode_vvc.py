#!/usr/bin/env python3
"""Generate a tiny real VVC bitstream with the external VTM encoder."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


DEFAULT_REF_DIR = Path("verification/reference")
DEFAULT_GENERATED_DIR = Path("verification/generated")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", help="optional yuv420p8 input path")
    parser.add_argument("--output", required=True, help="VVC bitstream output path")
    parser.add_argument("--recon", help="optional reconstructed YUV output path")
    parser.add_argument("--width", type=int, default=4)
    parser.add_argument("--height", type=int, default=4)
    args = parser.parse_args()

    if args.width <= 0 or args.height <= 0 or args.width % 2 or args.height % 2:
        print("reference VVC encode currently expects positive even dimensions", file=sys.stderr)
        return 2

    try:
        encoder = find_encoder()
    except RuntimeError as err:
        print(err, file=sys.stderr)
        return 2

    input_path = Path(args.input) if args.input else default_black_yuv420(args.width, args.height)
    output_path = Path(args.output)
    recon_path = Path(args.recon) if args.recon else output_path.with_suffix(".rec.yuv")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    recon_path.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        str(encoder),
        "-c",
        str(vtm_root() / "cfg" / "encoder_intra_vtm.cfg"),
        "-i",
        str(input_path),
        "-b",
        str(output_path),
        "-o",
        str(recon_path),
        "-wdt",
        str(args.width),
        "-hgt",
        str(args.height),
        "-f",
        "1",
        "-fr",
        "1",
        "--InputChromaFormat=420",
        "--ChromaFormatIDC=420",
        "--InputBitDepth=8",
        "--InternalBitDepth=8",
        "--OutputBitDepth=8",
        "--Level=none",
        "--Profile=auto",
        "--TemporalSubsampleRatio=1",
        "--CTUSize=64",
        "--MinQTLumaISlice=8",
        "--MinQTChromaISliceInChromaSamples=4",
        "--MinQTNonISlice=8",
        "--MaxBTNonISlice=64",
        "--MaxTTNonISlice=64",
        "--SAO=0",
        "--ALF=0",
        "--CCALF=0",
        "--LMCSEnable=0",
        "--MTS=0",
        "--LFNST=0",
        "--ISP=0",
        "--MIP=0",
        "--TransformSkip=0",
    ]

    completed = subprocess.run(cmd, check=False)
    if completed.returncode != 0:
        return completed.returncode

    print(f"wrote VVC bitstream: {output_path}")
    print(f"wrote reconstructed YUV: {recon_path}")
    return 0


def find_encoder() -> Path:
    configured = os.environ.get("FRAMEFORGE_VTM_ENCODER")
    if configured:
        path = Path(configured)
        if path.exists():
            return path
        raise RuntimeError(f"FRAMEFORGE_VTM_ENCODER does not exist: {path}")

    root = vtm_root()
    names = ("EncoderAppStatic", "EncoderAppStatic.exe", "EncoderApp", "EncoderApp.exe")
    for name in names:
        for path in root.rglob(name):
            if path.is_file() and os.access(path, os.X_OK):
                return path

    helper = Path(__file__).with_name("ensure_reference_decoder.py")
    completed = subprocess.run([sys.executable, str(helper)], check=False)
    if completed.returncode != 0:
        raise RuntimeError("failed to build VTM reference tools")

    for name in names:
        for path in root.rglob(name):
            if path.is_file() and os.access(path, os.X_OK):
                return path

    raise RuntimeError(f"no VTM encoder executable found under {root}")


def vtm_root() -> Path:
    if root := os.environ.get("FRAMEFORGE_VTM_ROOT"):
        return Path(root)
    return Path(os.environ.get("FRAMEFORGE_REF_DIR", DEFAULT_REF_DIR)) / "vtm"


def default_black_yuv420(width: int, height: int) -> Path:
    out_dir = Path(os.environ.get("FRAMEFORGE_GENERATED_DIR", DEFAULT_GENERATED_DIR))
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"black_{width}x{height}_yuv420p8.yuv"
    frame_len = width * height * 3 // 2
    path.write_bytes(bytes(frame_len))
    return path


if __name__ == "__main__":
    raise SystemExit(main())
