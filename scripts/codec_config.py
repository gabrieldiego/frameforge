"""Codec-specific paths shared by FrameForge helper scripts."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SUPPORTED_CODECS = ("vvc", "av2")


@dataclass(frozen=True)
class CodecConfig:
    name: str
    rust_encode_command: str
    bitstream_extension: str
    rtl_dir: Path
    rtl_include_dirs: tuple[Path, ...]
    default_synth_dut: str
    reference_dir: Path
    legacy_reference_dirs: tuple[Path, ...]


def add_codec_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--codec",
        required=True,
        choices=SUPPORTED_CODECS,
        help="codec namespace to operate on",
    )


def resolve_codec_config(codec: str) -> CodecConfig:
    normalized = codec.lower()
    if normalized == "vvc":
        return CodecConfig(
            name="vvc",
            rust_encode_command="vvc-encode",
            bitstream_extension="vvc",
            rtl_dir=REPO_ROOT / "rtl" / "vvc",
            rtl_include_dirs=(REPO_ROOT / "rtl" / "vvc" / "cabac",),
            default_synth_dut="vvc-cabac-stream-writer",
            reference_dir=REPO_ROOT / "verification" / "codecs" / "vvc" / "reference",
            legacy_reference_dirs=(REPO_ROOT / "verification" / "reference",),
        )
    if normalized == "av2":
        return CodecConfig(
            name="av2",
            rust_encode_command="av2-encode",
            bitstream_extension="av2",
            rtl_dir=REPO_ROOT / "rtl" / "av2",
            rtl_include_dirs=(),
            default_synth_dut="av2-encoder",
            reference_dir=REPO_ROOT / "verification" / "codecs" / "av2" / "reference",
            legacy_reference_dirs=(),
        )
    raise ValueError(f"unsupported codec '{codec}'")


def codec_config_from_args(args: argparse.Namespace) -> CodecConfig:
    return resolve_codec_config(args.codec)
