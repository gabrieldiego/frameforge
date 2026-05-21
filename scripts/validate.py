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
SUPPORTED_FORMATS = {
    "i420": "yuv420p8",
    "yuv420p8": "yuv420p8",
    "yuv420p10": "yuv420p10le",
    "yuv420p10le": "yuv420p10le",
    "i010": "yuv420p10le",
    "yuv420p12": "yuv420p12le",
    "yuv420p12le": "yuv420p12le",
    "i012": "yuv420p12le",
    "yuv420p16": "yuv420p16le",
    "yuv420p16le": "yuv420p16le",
    "i016": "yuv420p16le",
}


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
    rtl_input_path = normalized_rtl_input(input_path, info, out_dir, stem)

    sw_internal_recon.write_bytes(software_internal_reconstruction(input_path, info))

    run(
        [
            "cargo",
            "run",
            "--quiet",
            "--",
            "vvc-toy-4x4-video",
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
        env["FRAMEFORGE_RTL_TOY4X4_INPUT_1F"] = str(rtl_input_path)
        env["FRAMEFORGE_RTL_TOY4X4_OUT_1F"] = str(rtl_bitstream)
        env["FRAMEFORGE_RTL_TOY4X4_RECON_OUT_1F"] = str(rtl_internal_recon)
    else:
        env["FRAMEFORGE_RTL_TOY4X4_INPUT"] = str(rtl_input_path)
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
    if input_has_nonzero_chroma(input_path, info):
        validate_decoded_non_monochrome(vtm_recon, info)
        print("OK: VTM reconstruction contains decoder-visible chroma")
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
        r"(?:[_-](?P<fmt>yuv420p8|i420|yuv420p10le?|i010|yuv420p12le?|i012|yuv420p16le?|i016))?",
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
    if normalize_format(info.fmt) not in SUPPORTED_FORMATS.values():
        raise ValueError(
            f"unsupported format {info.fmt}; supported toy formats are "
            "yuv420p8, yuv420p10le, yuv420p12le, and yuv420p16le"
        )
    if info.width != 4 or info.height != 4:
        raise ValueError("toy VVC validation currently supports only 4x4 input")
    if info.frames not in (1, 2):
        raise ValueError("toy VVC validation currently supports only 1 or 2 frames")

    expected_len = frame_len(info) * info.frames
    data = input_path.read_bytes()
    if len(data) != expected_len:
        raise ValueError(
            f"input size mismatch: got {len(data)} bytes, expected {expected_len}"
        )


def normalize_format(fmt: str) -> str:
    value = fmt.lower()
    return SUPPORTED_FORMATS.get(value, value)


def run(cmd: list[str], env: dict[str, str] | None = None) -> None:
    subprocess.run(cmd, cwd=REPO_ROOT, env=env, check=True)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def software_internal_reconstruction(input_path: Path, info: InputInfo) -> bytes:
    frame = normalized_first_frame(input_path, info)
    y = inverse_transform_luma_dc(quantized_luma_dc(forward_luma_dc(frame[:16])))
    chroma = reconstructed_chroma(frame[16], frame[20])
    # This is the reconstruction of the emitted toy VVC bitstream, not the
    # original input. Keep this matched to VTM decode output after quantization.
    frame = bytes([y] * 16 + [chroma] * 4 + [chroma] * 4)
    return frame * info.frames


def forward_luma_dc(samples: bytes) -> int:
    return ((sum(samples) + 8) >> 4) - 114


def quantized_luma_dc(dc_coeff: int) -> int:
    sample = max(0, min(255, dc_coeff + 114))
    return quantized_luma(sample) - 114


def inverse_transform_luma_dc(dc_coeff: int) -> int:
    return max(0, min(255, dc_coeff + 114))


def reconstructed_chroma(u: int, v: int) -> int:
    return 0 if u == 0 and v == 0 else 96


def input_has_nonzero_chroma(input_path: Path, info: InputInfo) -> bool:
    first_frame = normalized_first_frame(input_path, info)
    luma_len = info.width * info.height
    return any(sample != 0 for sample in first_frame[luma_len:])


def validate_decoded_non_monochrome(path: Path, info: InputInfo) -> None:
    data = path.read_bytes()
    luma_len = info.width * info.height
    chroma_len = luma_len // 4
    first_frame_chroma = data[luma_len : luma_len + (chroma_len * 2)]
    if not any(sample != 0 for sample in first_frame_chroma):
        raise SystemExit("FAIL: VTM reconstruction has no decoder-visible chroma")


def normalized_rtl_input(input_path: Path, info: InputInfo, out_dir: Path, stem: str) -> Path:
    if normalize_format(info.fmt) == SUPPORTED_FORMAT:
        return input_path

    out = out_dir / f"{stem}_rtl_input_yuv420p8.yuv"
    out.write_bytes(normalized_input(input_path, info))
    return out


def normalized_input(input_path: Path, info: InputInfo) -> bytes:
    data = input_path.read_bytes()
    src_frame_len = frame_len(info)
    out = bytearray()
    for frame_idx in range(info.frames):
        frame = data[frame_idx * src_frame_len : (frame_idx + 1) * src_frame_len]
        out.extend(normalize_frame_bytes(frame, info))
    return bytes(out)


def normalized_first_frame(input_path: Path, info: InputInfo) -> bytes:
    return normalize_frame_bytes(input_path.read_bytes()[: frame_len(info)], info)


def normalize_frame_bytes(frame: bytes, info: InputInfo) -> bytes:
    bit_depth = format_bit_depth(info.fmt)
    if bit_depth == 8:
        return frame

    out = bytearray()
    for offset in range(0, len(frame), 2):
        sample = int.from_bytes(frame[offset : offset + 2], "little")
        out.append(sample >> (bit_depth - 8))
    return bytes(out)


def frame_len(info: InputInfo) -> int:
    return info.width * info.height * 3 // 2 * bytes_per_sample(info.fmt)


def bytes_per_sample(fmt: str) -> int:
    return 1 if format_bit_depth(fmt) == 8 else 2


def format_bit_depth(fmt: str) -> int:
    normalized = normalize_format(fmt)
    if normalized == "yuv420p8":
        return 8
    if normalized == "yuv420p10le":
        return 10
    if normalized == "yuv420p12le":
        return 12
    if normalized == "yuv420p16le":
        return 16
    raise ValueError(f"unsupported format {fmt}")


def quantized_luma(sample: int) -> int:
    return min(
        (((16 - rem) * 114 + 8) // 16 for rem in range(17)),
        key=lambda value: abs(value - sample),
    )


if __name__ == "__main__":
    raise SystemExit(main())
