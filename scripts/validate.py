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
RTL_SUPPORTED_FORMAT = "yuv420p8"
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
    "i422": "yuv422p8",
    "yuv422p8": "yuv422p8",
    "yuv422p10": "yuv422p10le",
    "yuv422p10le": "yuv422p10le",
    "i210": "yuv422p10le",
    "yuv422p12": "yuv422p12le",
    "yuv422p12le": "yuv422p12le",
    "i212": "yuv422p12le",
    "yuv422p16": "yuv422p16le",
    "yuv422p16le": "yuv422p16le",
    "i216": "yuv422p16le",
    "i444": "yuv444p8",
    "yuv444p8": "yuv444p8",
    "yuv444p10": "yuv444p10le",
    "yuv444p10le": "yuv444p10le",
    "i410": "yuv444p10le",
    "yuv444p12": "yuv444p12le",
    "yuv444p12le": "yuv444p12le",
    "i412": "yuv444p12le",
    "yuv444p16": "yuv444p16le",
    "yuv444p16le": "yuv444p16le",
    "i416": "yuv444p16le",
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
    palette_recon = out_dir / f"{stem}_frameforge_palette_dec.yuv"
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
    env["RTL_SAMPLE_BITS"] = "8"
    env["RTL_SOURCE_SAMPLE_BITS"] = str(format_bit_depth(info.fmt))
    env["RTL_CHROMA_FORMAT_IDC"] = str(rtl_chroma_format_idc(info))
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

    palette_lossless = supports_palette_lossless(info)
    if palette_lossless:
        run(
            [
                "cargo",
                "run",
                "--quiet",
                "--",
                "vvc-toy-4x4-decode",
                "--input",
                str(rtl_bitstream),
                "--output",
                str(palette_recon),
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
    if palette_lossless:
        digests["frameforge_palette_decode"] = sha256(palette_recon)

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
    if palette_lossless and digests["frameforge_palette_decode"] != digests["input_yuv"]:
        print(
            "FAIL: FrameForge palette decode does not match the input YUV",
            file=sys.stderr,
        )
        return 1

    print("OK: software and RTL bitstreams match")
    print("OK: software, RTL, and VTM reconstructions match")
    if palette_lossless:
        print("OK: FrameForge palette decode matches input losslessly")
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
        r"(?:[_-](?P<fmt>yuv(?:420|422|444)p(?:8|10le?|12le?|16le?)|i(?:420|422|444|010|012|016|210|212|216|410|412|416)))?",
        re.IGNORECASE,
    )
    match = pattern.search(name)
    if not match:
        return InputInfo(width=0, height=0, frames=0, fmt="")

    return InputInfo(
        width=int(match.group("width")),
        height=int(match.group("height")),
        frames=int(match.group("frames") or 1),
        fmt=normalize_format(match.group("fmt") or RTL_SUPPORTED_FORMAT),
    )


def validate_supported_input(input_path: Path, info: InputInfo) -> None:
    if normalize_format(info.fmt) not in SUPPORTED_FORMATS.values():
        raise ValueError(
            f"unsupported format {info.fmt}; supported toy formats are "
            "yuv420p/yuv422p/yuv444p at 8, 10, 12, or 16 bits"
        )
    if info.width != 4 or info.height != 4:
        raise ValueError("toy VVC validation currently supports only 4x4 input")
    sampling = format_chroma_sampling(info.fmt)
    if sampling == "420" and (info.width % 2 or info.height % 2):
        raise ValueError("yuv420p formats require even width and height")
    if sampling == "422" and info.width % 2:
        raise ValueError("yuv422p formats require even width")
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
    frame = normalized_first_frame_to_yuv420p8(input_path, info)
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
    first_frame = normalized_first_frame_to_yuv420p8(input_path, info)
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
    if format_bit_depth(info.fmt) == 8:
        return input_path

    out = out_dir / f"{stem}_rtl_input_yuv{format_chroma_sampling(info.fmt)}p8.yuv"
    out.write_bytes(normalized_input_to_yuv8(input_path, info))
    return out


def normalized_input_to_yuv8(input_path: Path, info: InputInfo) -> bytes:
    data = input_path.read_bytes()
    src_frame_len = frame_len(info)
    out = bytearray()
    total_samples = info.width * info.height + (chroma_plane_samples(info) * 2)
    for frame_idx in range(info.frames):
        frame = data[frame_idx * src_frame_len : (frame_idx + 1) * src_frame_len]
        out.extend(read_normalized_sample(frame, sample_idx, info) for sample_idx in range(total_samples))
    return bytes(out)


def normalized_input_to_yuv420p8(input_path: Path, info: InputInfo) -> bytes:
    data = input_path.read_bytes()
    src_frame_len = frame_len(info)
    out = bytearray()
    for frame_idx in range(info.frames):
        frame = data[frame_idx * src_frame_len : (frame_idx + 1) * src_frame_len]
        out.extend(normalize_frame_to_yuv420p8(frame, info))
    return bytes(out)


def normalized_first_frame_to_yuv420p8(input_path: Path, info: InputInfo) -> bytes:
    return normalize_frame_to_yuv420p8(input_path.read_bytes()[: frame_len(info)], info)


def normalize_frame_to_yuv420p8(frame: bytes, info: InputInfo) -> bytes:
    luma_samples = info.width * info.height
    chroma_samples = chroma_plane_samples(info)
    luma = [
        read_normalized_sample(frame, sample_idx, info)
        for sample_idx in range(luma_samples)
    ]
    if chroma_samples == 0:
        u = 0
        v = 0
    else:
        u = read_normalized_sample(frame, luma_samples, info)
        v = read_normalized_sample(frame, luma_samples + chroma_samples, info)
    return bytes(luma + [u] * (luma_samples // 4) + [v] * (luma_samples // 4))


def read_normalized_sample(frame: bytes, sample_idx: int, info: InputInfo) -> int:
    bit_depth = format_bit_depth(info.fmt)
    sample_bytes = bytes_per_sample(info.fmt)
    offset = sample_idx * sample_bytes
    if bit_depth == 8:
        return frame[offset]

    sample = int.from_bytes(frame[offset : offset + 2], "little")
    return sample >> (bit_depth - 8)


def frame_len(info: InputInfo) -> int:
    return (info.width * info.height + (chroma_plane_samples(info) * 2)) * bytes_per_sample(
        info.fmt
    )


def chroma_plane_samples(info: InputInfo) -> int:
    luma = info.width * info.height
    sampling = format_chroma_sampling(info.fmt)
    if sampling == "420":
        return luma // 4
    if sampling == "422":
        return luma // 2
    if sampling == "444":
        return luma
    raise ValueError(f"unsupported chroma sampling for {info.fmt}")


def bytes_per_sample(fmt: str) -> int:
    return 1 if format_bit_depth(fmt) == 8 else 2


def format_bit_depth(fmt: str) -> int:
    normalized = normalize_format(fmt)
    if normalized.endswith("p8"):
        return 8
    if normalized.endswith("p10le"):
        return 10
    if normalized.endswith("p12le"):
        return 12
    if normalized.endswith("p16le"):
        return 16
    raise ValueError(f"unsupported format {fmt}")


def format_chroma_sampling(fmt: str) -> str:
    normalized = normalize_format(fmt)
    if normalized.startswith("yuv420p"):
        return "420"
    if normalized.startswith("yuv422p"):
        return "422"
    if normalized.startswith("yuv444p"):
        return "444"
    raise ValueError(f"unsupported format {fmt}")


def rtl_chroma_format_idc(info: InputInfo) -> int:
    sampling = format_chroma_sampling(info.fmt)
    if sampling == "420":
        return 1
    if sampling == "422":
        return 2
    if sampling == "444":
        return 3
    raise ValueError(f"unsupported chroma sampling for {info.fmt}")


def supports_palette_lossless(info: InputInfo) -> bool:
    return (
        info.frames == 1
        and info.width == 4
        and info.height == 4
        and normalize_format(info.fmt) == "yuv444p8"
    )


def quantized_luma(sample: int) -> int:
    return min(
        (((16 - rem) * 114 + 8) // 16 for rem in range(17)),
        key=lambda value: abs(value - sample),
    )


if __name__ == "__main__":
    raise SystemExit(main())
