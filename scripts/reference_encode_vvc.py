#!/usr/bin/env python3
"""Generate a tiny real VVC bitstream with the external VTM encoder."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
from pathlib import Path

from codec_config import add_codec_arg, codec_config_from_args, CodecConfig

DEFAULT_GENERATED_DIR = Path("verification/generated")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    add_codec_arg(parser)
    parser.add_argument("--input", help="optional planar YUV input path matching --bit-depth and --chroma-format")
    parser.add_argument("--output", required=True, help="VVC bitstream output path")
    parser.add_argument("--recon", help="optional reconstructed YUV output path")
    parser.add_argument("--width", type=int, default=4)
    parser.add_argument("--height", type=int, default=4)
    parser.add_argument("--frames", type=int, default=1)
    parser.add_argument("--bit-depth", type=int, choices=(8, 10, 12, 16), default=8)
    parser.add_argument("--chroma-format", choices=("420", "422", "444"), default="420")
    args = parser.parse_args()
    codec = codec_config_from_args(args)

    if args.width <= 0 or args.height <= 0:
        print("reference VVC encode expects positive dimensions", file=sys.stderr)
        return 2
    if args.chroma_format == "420" and (args.width % 2 or args.height % 2):
        print("reference VVC 4:2:0 encode expects even width and height", file=sys.stderr)
        return 2
    if args.chroma_format == "422" and args.width % 2:
        print("reference VVC 4:2:2 encode expects even width", file=sys.stderr)
        return 2
    if args.frames <= 0:
        print("reference VVC encode expects at least one frame", file=sys.stderr)
        return 2

    try:
        encoder, encoder_root = find_encoder(codec)
    except RuntimeError as err:
        print(err, file=sys.stderr)
        return 2

    input_path = (
        Path(args.input)
        if args.input
        else default_black_yuv(
            args.width,
            args.height,
            args.frames,
            args.bit_depth,
            args.chroma_format,
        )
    )
    output_path = Path(args.output)
    recon_path = Path(args.recon) if args.recon else output_path.with_suffix(".rec.yuv")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    recon_path.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        str(encoder),
        "-c",
        str(encoder_root / "cfg" / "encoder_intra_vtm.cfg"),
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
        str(args.frames),
        "-fr",
        "1",
        f"--InputChromaFormat={args.chroma_format}",
        f"--ChromaFormatIDC={args.chroma_format}",
        f"--InputBitDepth={args.bit_depth}",
        f"--InternalBitDepth={args.bit_depth}",
        f"--OutputBitDepth={args.bit_depth}",
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
        if completed.returncode < 0:
            signum = -completed.returncode
            try:
                signame = signal.Signals(signum).name
            except ValueError:
                signame = f"SIG{signum}"
            print(
                f"VTM encoder terminated by {signame}; "
                "try setting FRAMEFORGE_VTM_ENCODER to another build if this persists.",
                file=sys.stderr,
            )
            return 128 + signum
        else:
            print(f"VTM encoder exited with status {completed.returncode}", file=sys.stderr)
            return completed.returncode

    print(f"wrote VVC bitstream: {output_path}")
    print(f"wrote reconstructed YUV: {recon_path}")
    return 0


def find_encoder(codec: CodecConfig) -> tuple[Path, Path]:
    configured = os.environ.get("FRAMEFORGE_VTM_ENCODER")
    if configured:
        path = Path(configured)
        if path.exists():
            return path, vtm_root(codec)
        raise RuntimeError(f"FRAMEFORGE_VTM_ENCODER does not exist: {path}")

    names = ("EncoderAppStatic", "EncoderAppStatic.exe", "EncoderApp", "EncoderApp.exe")
    found = find_encoder_in_roots(names, candidate_vtm_roots(codec))
    if found:
        return found

    helper = Path(__file__).with_name("ensure_reference_decoder.py")
    completed = subprocess.run([sys.executable, str(helper), "--codec", codec.name], check=False)
    if completed.returncode != 0:
        raise RuntimeError("failed to build VTM reference tools")

    found = find_encoder_in_roots(names, candidate_vtm_roots(codec))
    if found:
        return found

    roots = ", ".join(str(root) for root in candidate_vtm_roots(codec))
    raise RuntimeError(f"no VTM encoder executable found under: {roots}")


def find_encoder_in_roots(names: tuple[str, ...], roots: list[Path]) -> tuple[Path, Path] | None:
    for root in roots:
        if not root.exists():
            continue
        for name in names:
            for path in root.rglob(name):
                if path.is_file() and os.access(path, os.X_OK):
                    return path, root
    return None


def candidate_vtm_roots(codec: CodecConfig) -> list[Path]:
    root = vtm_root(codec)
    roots = [root]
    if "FRAMEFORGE_VTM_ROOT" not in os.environ and "FRAMEFORGE_REF_DIR" not in os.environ:
        roots.extend(legacy / "vtm" for legacy in codec.legacy_reference_dirs)
    return roots


def vtm_root(codec: CodecConfig) -> Path:
    if root := os.environ.get("FRAMEFORGE_VTM_ROOT"):
        return Path(root)
    return Path(os.environ.get("FRAMEFORGE_REF_DIR", codec.reference_dir)) / "vtm"


def default_black_yuv(
    width: int,
    height: int,
    frames: int,
    bit_depth: int,
    chroma_format: str,
) -> Path:
    out_dir = Path(os.environ.get("FRAMEFORGE_GENERATED_DIR", DEFAULT_GENERATED_DIR))
    out_dir.mkdir(parents=True, exist_ok=True)
    suffix = f"yuv{chroma_format}p8" if bit_depth == 8 else f"yuv{chroma_format}p{bit_depth}le"
    path = out_dir / f"black_{width}x{height}_{frames}f_{suffix}.yuv"
    luma_samples = width * height
    chroma_samples = frame_samples(width, height, chroma_format) - luma_samples
    if bit_depth == 8:
        frame = bytes(luma_samples) + bytes([128]) * chroma_samples
        path.write_bytes(frame * frames)
    else:
        neutral = (1 << (bit_depth - 1)).to_bytes(2, "little")
        frame = bytes(luma_samples * 2) + neutral * chroma_samples
        path.write_bytes(frame * frames)
    return path


def frame_samples(width: int, height: int, chroma_format: str) -> int:
    luma = width * height
    if chroma_format == "420":
        return luma + (2 * (luma // 4))
    if chroma_format == "422":
        return luma + (2 * (luma // 2))
    if chroma_format == "444":
        return luma * 3
    raise ValueError(f"unsupported chroma format {chroma_format}")


if __name__ == "__main__":
    raise SystemExit(main())
