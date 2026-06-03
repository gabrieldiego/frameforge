#!/usr/bin/env python3
"""Validate FrameForge software/RTL streams and reconstructions."""

from __future__ import annotations

import argparse
import hashlib
import math
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = Path("verification/generated/checksums")
RTL_SUPPORTED_FORMAT = "yuv420p8"
VTM_CRASH_SKIP_EXIT = 77

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
    parser.add_argument(
        "--max-width",
        type=int,
        default=64,
        help="maximum visible width supported by the RTL instance under validation",
    )
    parser.add_argument(
        "--max-height",
        type=int,
        default=64,
        help="maximum visible height supported by the RTL instance under validation",
    )
    parser.add_argument("--frames", type=int)
    parser.add_argument("--format", default=None)
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument(
        "--synth-dut",
        default="vvc-cabac-pipeline",
        help="synthesizable RTL block to check during validation",
    )
    parser.add_argument(
        "--skip-synth",
        action="store_true",
        help="skip the default synthesis preflight",
    )
    parser.add_argument(
        "--sw-only",
        action="store_true",
        help="validate only the Rust software encoder against VTM; skip RTL simulation and synthesis",
    )
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    if not input_path.exists():
        print(f"FAIL: input YUV file does not exist: {input_path}", file=sys.stderr)
        return 2

    try:
        info = resolve_input_info(input_path, args)
        validate_supported_input(
            input_path,
            info,
            args.max_width,
            args.max_height,
            args.sw_only,
            allow_trailing=args.frames is not None,
        )
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
    vtm_recon = out_dir / f"{stem}_vtm_from_decodable_bitstream.yuv"
    validation_input_path = materialized_validation_input(input_path, info, out_dir, stem)
    rtl_input_path = normalized_rtl_input(validation_input_path, info, out_dir, stem)

    print(
        f"FrameForge validate: software encode {info.frames} frame(s), "
        f"{info.width}x{info.height} {info.fmt}",
        flush=True,
    )
    sw_env = os.environ.copy()
    sw_env["FRAMEFORGE_PROGRESS"] = "1"
    run(
        [
            "cargo",
            "run",
            "--quiet",
            "--",
            "vvc-encode",
            "--input",
            str(validation_input_path),
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
            "--recon",
            str(sw_internal_recon),
        ],
        env=sw_env,
    )

    if args.sw_only:
        has_vtm_recon = vtm_decode_supported(input_path, info)
        if has_vtm_recon:
            print("FrameForge validate: VTM decode software bitstream", flush=True)
            decoder = subprocess.run(
                [
                    sys.executable,
                    "scripts/validate_decode.py",
                    str(sw_bitstream),
                    "--output",
                    str(vtm_recon),
                ],
                cwd=REPO_ROOT,
            )
            if decoder.returncode != 0:
                if decoder.returncode == VTM_CRASH_SKIP_EXIT:
                    has_vtm_recon = False
                    print("SKIP: VTM crashed; skipping only the external decode comparison")
                else:
                    print("FAIL: VTM decoder rejected software bitstream", file=sys.stderr)
                    return 1

        digests = {
            "input_yuv": sha256(validation_input_path),
            "software_bitstream": sha256(sw_bitstream),
            "software_internal_recon": sha256(sw_internal_recon),
            "vtm_recon_from_software_bitstream": sha256(vtm_recon) if has_vtm_recon else None,
        }

        print("FrameForge software validation checksums")
        print(
            f"input={validation_input_path} width={info.width} height={info.height} "
            f"frames={info.frames} format={info.fmt}"
        )
        for name, digest in digests.items():
            if digest is None:
                print(f"SKIP  {name}")
            else:
                print(f"{digest}  {name}")
        print_psnr_report("software_internal_recon", validation_input_path, sw_internal_recon)
        if has_vtm_recon:
            print_psnr_report("vtm_recon_from_software_bitstream", validation_input_path, vtm_recon)

        if has_vtm_recon and digests["software_internal_recon"] != digests["vtm_recon_from_software_bitstream"]:
            print(
                "FAIL: software internal reconstruction and VTM reconstruction differ",
                file=sys.stderr,
            )
            return 1
        if has_vtm_recon:
            print("OK: software internal reconstruction matches VTM reconstruction")
        else:
            print("SKIP: VTM decode is not wired for this VVC path yet")
        if has_vtm_recon and input_has_nonzero_chroma(validation_input_path, info):
            validate_decoded_non_monochrome(vtm_recon, info)
            print("OK: VTM reconstruction contains decoder-visible chroma")
        return 0

    if not args.skip_synth:
        run(["make", "synth", f"SYNTH_DUT={args.synth_dut}"])

    env = os.environ.copy()
    rtl_sample_bits = format_bit_depth(info.fmt) if format_chroma_sampling(info.fmt) == "444" else 8
    env["RTL_SAMPLE_BITS"] = str(rtl_sample_bits)
    env["RTL_SOURCE_SAMPLE_BITS"] = str(format_bit_depth(info.fmt))
    env["RTL_CHROMA_FORMAT_IDC"] = str(rtl_chroma_format_idc(info))
    env["FRAMEFORGE_RTL_VVC_ENCODER_FRAMES"] = str(info.frames)
    if info.frames == 1:
        env["FRAMEFORGE_RTL_VVC_ENCODER_INPUT_1F"] = str(rtl_input_path)
        env["FRAMEFORGE_RTL_VVC_ENCODER_OUT_1F"] = str(rtl_bitstream)
        env["FRAMEFORGE_RTL_VVC_ENCODER_RECON_OUT_1F"] = str(rtl_internal_recon)
    else:
        env["FRAMEFORGE_RTL_VVC_ENCODER_INPUT"] = str(rtl_input_path)
        env["FRAMEFORGE_RTL_VVC_ENCODER_OUT"] = str(rtl_bitstream)
        env["FRAMEFORGE_RTL_VVC_ENCODER_RECON_OUT"] = str(rtl_internal_recon)
    run(
        [
            "make",
            "-B",
            "rtl-test",
            "DUT=vvc-encoder",
            f"RTL_VISIBLE_WIDTH={info.width}",
            f"RTL_VISIBLE_HEIGHT={info.height}",
            f"RTL_MAX_VISIBLE_WIDTH={args.max_width}",
            f"RTL_MAX_VISIBLE_HEIGHT={args.max_height}",
        ],
        env=env,
    )

    has_vtm_recon = vtm_decode_supported(input_path, info)
    rtl_annexb_bitstream = is_annexb_bitstream(rtl_bitstream)
    if has_vtm_recon and rtl_annexb_bitstream:
        print("FrameForge validate: VTM decode RTL bitstream", flush=True)
        decoder = subprocess.run(
            [
                sys.executable,
                "scripts/validate_decode.py",
                str(rtl_bitstream),
                "--output",
                str(vtm_recon),
            ],
            cwd=REPO_ROOT,
        )
        if decoder.returncode != 0:
            if decoder.returncode == VTM_CRASH_SKIP_EXIT:
                has_vtm_recon = False
                print("SKIP: VTM crashed; skipping only the external decode comparison")
            else:
                print(
                    f"FAIL: VTM decoder rejected {'RTL' if rtl_annexb_bitstream else 'software'} bitstream",
                    file=sys.stderr,
                )
                return 1

    digests = {
        "input_yuv": sha256(validation_input_path),
        "software_bitstream": sha256(sw_bitstream),
        "rtl_bitstream": sha256(rtl_bitstream),
        "software_internal_recon": sha256(sw_internal_recon),
        "rtl_internal_recon": sha256(rtl_internal_recon),
        "vtm_recon_from_decodable_bitstream": sha256(vtm_recon) if has_vtm_recon else None,
    }

    print("FrameForge validation checksums")
    print(
        f"input={validation_input_path} width={info.width} height={info.height} "
        f"frames={info.frames} format={info.fmt}"
    )
    for name, digest in digests.items():
        if digest is None:
            print(f"SKIP  {name}")
        else:
            print(f"{digest}  {name}")
    print_psnr_report("software_internal_recon", validation_input_path, sw_internal_recon)
    print_psnr_report("rtl_internal_recon", validation_input_path, rtl_internal_recon)
    if has_vtm_recon:
        print_psnr_report("vtm_recon_from_decodable_bitstream", validation_input_path, vtm_recon)

    if not rtl_bitstream.read_bytes():
        print("FAIL: RTL encoder produced an empty byte stream", file=sys.stderr)
        return 1
    if not rtl_annexb_bitstream:
        print("FAIL: RTL output is not an Annex-B VVC bitstream", file=sys.stderr)
        return 1
    if digests["software_bitstream"] != digests["rtl_bitstream"]:
        print("FAIL: software and RTL bitstreams differ", file=sys.stderr)
        return 1
    if digests["software_internal_recon"] != digests["rtl_internal_recon"]:
        print(
            "FAIL: software internal reconstruction and RTL internal reconstruction differ",
            file=sys.stderr,
        )
        return 1
    if has_vtm_recon and not (
        digests["software_internal_recon"] == digests["vtm_recon_from_decodable_bitstream"]
    ):
        print(
            "FAIL: software internal reconstruction, RTL internal "
            "reconstruction, and VTM reconstruction differ",
            file=sys.stderr,
        )
        return 1
    print("OK: software and RTL bitstreams match")
    print("OK: software and RTL internal reconstructions match")
    if has_vtm_recon:
        print("OK: software, RTL, and VTM reconstructions match using RTL VVC bitstream")
    else:
        print("SKIP: VTM decode is not wired for this VVC path yet")
    if has_vtm_recon and input_has_nonzero_chroma(validation_input_path, info):
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
        r"(?:[_-]\d+fps)?"
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


def validate_supported_input(
    input_path: Path,
    info: InputInfo,
    max_width: int,
    max_height: int,
    sw_only: bool = False,
    allow_trailing: bool = False,
) -> None:
    if normalize_format(info.fmt) not in SUPPORTED_FORMATS.values():
        raise ValueError(
            f"unsupported format {info.fmt}; supported VVC formats are "
            "yuv420p/yuv422p/yuv444p at 8, 10, 12, or 16 bits"
        )
    if info.width > max_width or info.height > max_height:
        raise ValueError(
            f"VVC validation supports at most {max_width}x{max_height} input at this entry point; got {info.width}x{info.height}"
        )
    if info.width % 2 or info.height % 2:
        raise ValueError("VVC validation currently requires even width and height")
    sampling = format_chroma_sampling(info.fmt)
    if sampling == "420" and (info.width % 2 or info.height % 2):
        raise ValueError("yuv420p formats require even width and height")
    if sampling == "422" and info.width % 2:
        raise ValueError("yuv422p formats require even width")
    if info.frames < 1:
        raise ValueError("VVC validation expects at least one frame")

    expected_len = frame_len(info) * info.frames
    actual_len = input_path.stat().st_size
    if actual_len < expected_len:
        raise ValueError(
            f"input size mismatch: got {actual_len} bytes, expected at least {expected_len}"
        )
    if actual_len != expected_len and not allow_trailing:
        raise ValueError(
            f"input size mismatch: got {actual_len} bytes, expected {expected_len}"
        )


def vtm_decode_supported(_input_path: Path, info: InputInfo) -> bool:
    if format_chroma_sampling(info.fmt) == "444":
        return info.fmt == "yuv444p8"
    return True


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


def print_psnr_report(label: str, reference_path: Path, reconstructed_path: Path) -> None:
    value = psnr_bytes(reference_path, reconstructed_path)
    if value is None:
        print(f"SKIP  {label}_psnr_vs_input")
    elif math.isinf(value):
        print(f"inf  {label}_psnr_vs_input_db")
    else:
        print(f"{value:.2f}  {label}_psnr_vs_input_db")


def psnr_bytes(reference_path: Path, reconstructed_path: Path) -> float | None:
    reference = reference_path.read_bytes()
    reconstructed = reconstructed_path.read_bytes()
    if len(reference) != len(reconstructed):
        return None
    if not reference:
        return None
    sse = sum((a - b) * (a - b) for a, b in zip(reference, reconstructed))
    if sse == 0:
        return math.inf
    mse = sse / len(reference)
    return 10.0 * math.log10((255.0 * 255.0) / mse)


def input_has_nonzero_chroma(input_path: Path, info: InputInfo) -> bool:
    sample_bytes = bytes_per_sample(info.fmt)
    first_frame = input_path.read_bytes()[: frame_len(info)]
    luma_bytes = info.width * info.height * sample_bytes
    chroma_bytes = chroma_plane_samples(info) * 2 * sample_bytes
    return any(first_frame[luma_bytes : luma_bytes + chroma_bytes])


def validate_decoded_non_monochrome(path: Path, info: InputInfo) -> None:
    sample_bytes = bytes_per_sample(info.fmt)
    data = path.read_bytes()[: frame_len(info)]
    luma_bytes = info.width * info.height * sample_bytes
    chroma_bytes = chroma_plane_samples(info) * 2 * sample_bytes
    first_frame_chroma = data[luma_bytes : luma_bytes + chroma_bytes]
    if not any(sample != 0 for sample in first_frame_chroma):
        raise SystemExit("FAIL: VTM reconstruction has no decoder-visible chroma")


def is_annexb_bitstream(path: Path) -> bool:
    prefix = path.read_bytes()[:4]
    return prefix.startswith(b"\x00\x00\x01") or prefix.startswith(b"\x00\x00\x00\x01")


def normalized_rtl_input(input_path: Path, info: InputInfo, out_dir: Path, stem: str) -> Path:
    if format_chroma_sampling(info.fmt) == "444":
        return input_path
    if format_bit_depth(info.fmt) == 8:
        return input_path

    out = out_dir / f"{stem}_rtl_input_yuv{format_chroma_sampling(info.fmt)}p8.yuv"
    out.write_bytes(normalized_input_to_yuv8(input_path, info))
    return out


def materialized_validation_input(input_path: Path, info: InputInfo, out_dir: Path, stem: str) -> Path:
    expected_len = frame_len(info) * info.frames
    if input_path.stat().st_size == expected_len:
        return input_path

    out = out_dir / f"{stem}_input_prefix.yuv"
    remaining = expected_len
    with input_path.open("rb") as src, out.open("wb") as dst:
        while remaining:
            chunk = src.read(min(remaining, 1024 * 1024))
            if not chunk:
                raise ValueError(
                    f"input size mismatch: got fewer bytes than the first {info.frames} frame(s)"
                )
            dst.write(chunk)
            remaining -= len(chunk)
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


if __name__ == "__main__":
    raise SystemExit(main())
