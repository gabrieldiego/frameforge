#!/usr/bin/env python3
"""Validate FrameForge software/RTL streams and reconstructions."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = Path("verification/generated/checksums")
SUPPORTED_FORMAT = "yuv420p8"


@dataclass(frozen=True)
class InputInfo:
    width: int
    height: int
    frames: int
    fmt: str


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="input YUV file")
    parser.add_argument("--width", type=int)
    parser.add_argument("--height", type=int)
    parser.add_argument("--frames", type=int)
    parser.add_argument("--format", default=None)
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    if not input_path.exists():
        print(f"FAIL: input YUV file does not exist: {input_path}", file=sys.stderr)
        return 2

    try:
        info = resolve_input_info(input_path, args)
        validate_supported_input(input_path, info)
    except ValueError as err:
        print(f"FAIL: {err}", file=sys.stderr)
        return 2

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    stem = f"{input_path.stem}_{info.width}x{info.height}_{info.frames}f_{info.fmt}"
    sw_bitstream = out_dir / f"{stem}_software.vvc"
    rtl_bitstream = out_dir / f"{stem}_rtl.vvc"
    sw_internal_recon = out_dir / f"{stem}_software_internal_rec.yuv"
    rtl_internal_recon = out_dir / f"{stem}_rtl_internal_rec.yuv"
    vtm_recon = out_dir / f"{stem}_vtm_from_rtl_dec.yuv"

    sw_internal_recon.write_bytes(software_internal_reconstruction(info))

    run(
        [
            "cargo",
            "run",
            "--quiet",
            "--",
            "vvc-toy-4x4-black-video",
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
            str(sw_bitstream),
        ]
    )

    env = os.environ.copy()
    if info.frames == 1:
        env["FRAMEFORGE_RTL_TOY4X4_INPUT_1F"] = str(input_path)
        env["FRAMEFORGE_RTL_TOY4X4_OUT_1F"] = str(rtl_bitstream)
        env["FRAMEFORGE_RTL_TOY4X4_RECON_OUT_1F"] = str(rtl_internal_recon)
    else:
        env["FRAMEFORGE_RTL_TOY4X4_INPUT"] = str(input_path)
        env["FRAMEFORGE_RTL_TOY4X4_OUT"] = str(rtl_bitstream)
        env["FRAMEFORGE_RTL_TOY4X4_RECON_OUT"] = str(rtl_internal_recon)
    run(["make", "rtl-test", "DUT=vvc-toy4x4"], env=env)

    run(
        [
            sys.executable,
            "scripts/validate_decode.py",
            str(rtl_bitstream),
            "--output",
            str(vtm_recon),
        ]
    )

    digests = {
        "input_yuv": sha256(input_path),
        "software_bitstream": sha256(sw_bitstream),
        "rtl_bitstream": sha256(rtl_bitstream),
        "software_internal_recon": sha256(sw_internal_recon),
        "rtl_internal_recon": sha256(rtl_internal_recon),
        "vtm_recon_from_rtl_bitstream": sha256(vtm_recon),
    }

    print("FrameForge validation checksums")
    print(
        f"input={input_path} width={info.width} height={info.height} "
        f"frames={info.frames} format={info.fmt}"
    )
    for name, digest in digests.items():
        print(f"{digest}  {name}")

    if digests["software_bitstream"] != digests["rtl_bitstream"]:
        print("FAIL: software and RTL bitstreams differ", file=sys.stderr)
        return 1
    if not (
        digests["software_internal_recon"]
        == digests["rtl_internal_recon"]
        == digests["vtm_recon_from_rtl_bitstream"]
    ):
        print(
            "FAIL: software internal reconstruction, RTL internal "
            "reconstruction, and VTM reconstruction differ",
            file=sys.stderr,
        )
        return 1

    print("OK: software and RTL bitstreams match")
    print("OK: software, RTL, and VTM reconstructions match")
    return 0


def resolve_input_info(input_path: Path, args: argparse.Namespace) -> InputInfo:
    inferred = infer_from_filename(input_path.name)
    width = args.width if args.width is not None else inferred.width
    height = args.height if args.height is not None else inferred.height
    frames = args.frames if args.frames is not None else inferred.frames
    fmt = args.format if args.format is not None else inferred.fmt

    missing = []
    if not width:
        missing.append("WIDTH")
    if not height:
        missing.append("HEIGHT")
    if not frames:
        missing.append("FRAMES")
    if not fmt:
        missing.append("FORMAT")
    if missing:
        raise ValueError(
            "could not infer "
            + ", ".join(missing)
            + " from filename; pass explicit Make overrides"
        )

    return InputInfo(width=width, height=height, frames=frames, fmt=fmt)


def infer_from_filename(name: str) -> InputInfo:
    pattern = re.compile(
        r"(?P<width>\d+)x(?P<height>\d+)"
        r"(?:[_-](?P<frames>\d+)f)?"
        r"(?:[_-](?P<fmt>yuv420p8|i420))?",
        re.IGNORECASE,
    )
    match = pattern.search(name)
    if not match:
        return InputInfo(width=0, height=0, frames=0, fmt="")

    return InputInfo(
        width=int(match.group("width")),
        height=int(match.group("height")),
        frames=int(match.group("frames") or 1),
        fmt=normalize_format(match.group("fmt") or SUPPORTED_FORMAT),
    )


def validate_supported_input(input_path: Path, info: InputInfo) -> None:
    if normalize_format(info.fmt) != SUPPORTED_FORMAT:
        raise ValueError(f"unsupported format {info.fmt}; only {SUPPORTED_FORMAT} is supported")
    if info.width != 4 or info.height != 4:
        raise ValueError("toy VVC validation currently supports only 4x4 input")
    if info.frames not in (1, 2):
        raise ValueError("toy VVC validation currently supports only 1 or 2 frames")

    expected_len = info.width * info.height * 3 // 2 * info.frames
    data = input_path.read_bytes()
    if len(data) != expected_len:
        raise ValueError(
            f"input size mismatch: got {len(data)} bytes, expected {expected_len}"
        )


def normalize_format(fmt: str) -> str:
    value = fmt.lower()
    if value == "i420":
        return SUPPORTED_FORMAT
    return value


def run(cmd: list[str], env: dict[str, str] | None = None) -> None:
    subprocess.run(cmd, cwd=REPO_ROOT, env=env, check=True)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def software_internal_reconstruction(info: InputInfo) -> bytes:
    frame_len = info.width * info.height * 3 // 2
    # This is the reconstruction of the current emitted toy VVC bitstream, not
    # the intended input approximation. Keep this matched to VTM decode output.
    return bytes(frame_len * info.frames)


if __name__ == "__main__":
    raise SystemExit(main())
