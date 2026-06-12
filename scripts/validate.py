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

from codec_config import add_codec_arg, codec_config_from_args

try:
    from PIL import Image
except ImportError:  # pragma: no cover - exercised only when validating PNG inputs.
    Image = None


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = Path("verification/generated/checksums")
RTL_SUPPORTED_FORMAT = "yuv420p8"
VTM_CRASH_SKIP_EXIT = 77
RAW_INPUT_FORMATS = {"auto", "raw", "raw-yuv", "yuv"}
LOSSLESS_IMAGE_INPUT_FORMATS = {"png"}
SUPPORTED_INPUT_FORMATS = RAW_INPUT_FORMATS | LOSSLESS_IMAGE_INPUT_FORMATS
SUPPORTED_RECON_FORMATS = {"codec", "raw", "rgb24", "png"}

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
    add_codec_arg(parser)
    parser.add_argument("input", help="input raw YUV file, or a lossless PNG still image")
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
    parser.add_argument(
        "--input-format",
        default="auto",
        choices=sorted(SUPPORTED_INPUT_FORMATS),
        help="input container/pixel source; auto treats .png as PNG and everything else as raw YUV",
    )
    parser.add_argument(
        "--recon-format",
        default="codec",
        choices=sorted(SUPPORTED_RECON_FORMATS),
        help="optional inspection copy for reconstructions; PNG/RGB24 interprets yuv444p8 components as planar GBR",
    )
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
        help="skip RTL simulation and synthesis; VVC validates only the Rust software encoder against VTM",
    )
    args = parser.parse_args()
    codec = codec_config_from_args(args)

    input_path = Path(args.input).resolve()
    if not input_path.exists():
        print(f"FAIL: input file does not exist: {input_path}", file=sys.stderr)
        return 2

    try:
        input_format = resolve_input_format(input_path, args.input_format)
        info = resolve_input_info(input_path, args, input_format)
        validate_supported_input(
            input_path,
            info,
            args.max_width,
            args.max_height,
            input_format,
            args.sw_only or codec.name == "av2",
            allow_trailing=args.frames is not None,
        )
    except ValueError as err:
        print(f"FAIL: {err}", file=sys.stderr)
        return 2

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    stem = f"{input_path.stem}_{info.width}x{info.height}_{info.frames}f_{info.fmt}"
    sw_bitstream = out_dir / f"{stem}_software.{codec.bitstream_extension}"
    rtl_bitstream = out_dir / f"{stem}_rtl.{codec.bitstream_extension}"
    sw_internal_recon = out_dir / f"{stem}_software_internal_rec.yuv"
    rtl_internal_recon = out_dir / f"{stem}_rtl_internal_rec.yuv"
    vtm_recon = out_dir / f"{stem}_vtm_from_decodable_bitstream.yuv"
    validation_input_path = materialized_validation_input(input_path, info, out_dir, stem, input_format)
    if codec.name == "av2":
        return validate_av2_fixed_black_bitstream(
            codec,
            args,
            validation_input_path,
            info,
            out_dir,
            stem,
        )
    if codec.name != "vvc":
        print(
            f"FAIL: {codec.name.upper()} validation is not implemented yet",
            file=sys.stderr,
        )
        return 2

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
            codec.rust_encode_command,
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
                    "--codec",
                    codec.name,
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
        print_bitrate_report("software_bitstream", sw_bitstream, info)
        print_psnr_report("software_internal_recon", validation_input_path, sw_internal_recon)
        if has_vtm_recon:
            print_psnr_report("vtm_recon_from_software_bitstream", validation_input_path, vtm_recon)
        write_recon_views(
            args.recon_format,
            info,
            out_dir,
            stem,
            {
                "input": validation_input_path,
                "software_internal_recon": sw_internal_recon,
                "vtm_recon_from_software_bitstream": vtm_recon if has_vtm_recon else None,
            },
        )

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
        run(["make", "synth", f"CODEC={codec.name}", f"SYNTH_DUT={args.synth_dut}"])

    env = os.environ.copy()
    rtl_sample_bits = format_bit_depth(info.fmt) if format_chroma_sampling(info.fmt) == "444" else 8
    env["RTL_SAMPLE_BITS"] = str(rtl_sample_bits)
    env["RTL_SOURCE_SAMPLE_BITS"] = str(format_bit_depth(info.fmt))
    env["RTL_CHROMA_FORMAT_IDC"] = str(rtl_chroma_format_idc(info))
    env["FRAMEFORGE_RTL_VVC_ENCODER_FRAMES"] = str(info.frames)
    env.setdefault(
        "COCOTB_TEST_FILTER",
        "^test_vvc_encoder\\.vvc_encoder_matches_software_stream$",
    )
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
            f"CODEC={codec.name}",
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
                "--codec",
                codec.name,
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
    print_bitrate_report("software_bitstream", sw_bitstream, info)
    print_bitrate_report("rtl_bitstream", rtl_bitstream, info)
    print_psnr_report("software_internal_recon", validation_input_path, sw_internal_recon)
    print_psnr_report("rtl_internal_recon", validation_input_path, rtl_internal_recon)
    if has_vtm_recon:
        print_psnr_report("vtm_recon_from_decodable_bitstream", validation_input_path, vtm_recon)
    write_recon_views(
        args.recon_format,
        info,
        out_dir,
        stem,
        {
            "input": validation_input_path,
            "software_internal_recon": sw_internal_recon,
            "rtl_internal_recon": rtl_internal_recon,
            "vtm_recon_from_decodable_bitstream": vtm_recon if has_vtm_recon else None,
        },
    )

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


def validate_av2_fixed_black_bitstream(
    codec,
    args: argparse.Namespace,
    validation_input_path: Path,
    info: InputInfo,
    out_dir: Path,
    stem: str,
) -> int:
    reference_bitstream = out_dir / f"{stem}_ref.{codec.bitstream_extension}"
    reference_recon = out_dir / f"{stem}_ref_recon.yuv"
    sw_bitstream = out_dir / f"{stem}_software.{codec.bitstream_extension}"
    sw_internal_recon = out_dir / f"{stem}_software_internal_rec.yuv"
    sw_ref_decoded_recon = out_dir / f"{stem}_software_ref_decoded.yuv"
    rtl_bitstream = out_dir / f"{stem}_rtl.{codec.bitstream_extension}"
    rtl_internal_recon = out_dir / f"{stem}_rtl_internal_rec.yuv"
    expected_recon = av2_black_64x64_444_reconstruction(info)
    if expected_recon is None:
        print(
            "FAIL: fixed AV2 software validation only supports one 64x64 "
            "yuv444p8 black frame",
            file=sys.stderr,
        )
        return 2
    if validation_input_path.read_bytes() != expected_recon:
        print(
            "FAIL: fixed AV2 software validation expects a black 64x64 yuv444p8 input",
            file=sys.stderr,
        )
        return 1

    print(
        f"FrameForge validate: AV2 software fixed encode {info.frames} frame(s), "
        f"{info.width}x{info.height} {info.fmt}",
        flush=True,
    )
    sw = subprocess.run(
        [
            "cargo",
            "run",
            "--quiet",
            "--",
            codec.rust_encode_command,
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
        cwd=REPO_ROOT,
        check=False,
    )
    if sw.returncode != 0:
        print("FAIL: AV2 software fixed encode failed", file=sys.stderr)
        return sw.returncode

    print("FrameForge validate: AV2 REF decode software bitstream", flush=True)
    sw_decoded = subprocess.run(
        [
            sys.executable,
            "scripts/validate_decode.py",
            "--codec",
            codec.name,
            str(sw_bitstream),
            "--output",
            str(sw_ref_decoded_recon),
            "--rawvideo",
        ],
        cwd=REPO_ROOT,
        check=False,
    )
    if sw_decoded.returncode != 0:
        print("FAIL: AV2 REF decoder rejected software bitstream", file=sys.stderr)
        return sw_decoded.returncode

    print(
        f"FrameForge validate: AV2 REF encode {info.frames} frame(s), "
        f"{info.width}x{info.height} {info.fmt}",
        flush=True,
    )
    completed = subprocess.run(
        [
            sys.executable,
            "scripts/reference_encode_av2.py",
            "--codec",
            codec.name,
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
            str(reference_bitstream),
            "--recon",
            str(reference_recon),
        ],
        cwd=REPO_ROOT,
        check=False,
    )
    if completed.returncode != 0:
        print("FAIL: AV2 REF encode/decode failed", file=sys.stderr)
        return completed.returncode

    if not args.skip_synth:
        print("SKIP: AV2 fixed software path is not ready for synthesis validation")

    ran_rtl = False
    if not args.sw_only:
        ran_rtl = True
        print("FrameForge validate: AV2 RTL temporary black-frame payload", flush=True)
        env = os.environ.copy()
        env["RTL_CHROMA_FORMAT_IDC"] = "3"
        env["FRAMEFORGE_RTL_AV2_ENCODER_OUT_1F"] = str(rtl_bitstream)
        env["FRAMEFORGE_RTL_AV2_ENCODER_RECON_OUT_1F"] = str(rtl_internal_recon)
        env["COCOTB_TEST_FILTER"] = (
            "^test_av2_encoder\\.av2_encoder_emits_temporary_black_64x64_444_payload$"
        )
        rtl = subprocess.run(
            [
                "make",
                "-B",
                "rtl-test",
                f"CODEC={codec.name}",
                "DUT=av2-encoder",
                "RTL_VISIBLE_WIDTH=64",
                "RTL_VISIBLE_HEIGHT=64",
                "RTL_CHROMA_FORMAT_IDC=3",
            ],
            cwd=REPO_ROOT,
            env=env,
            check=False,
        )
        if rtl.returncode != 0:
            print("FAIL: AV2 RTL temporary payload simulation failed", file=sys.stderr)
            return rtl.returncode

    digests = {
        "input_yuv": sha256(validation_input_path),
        "software_bitstream": sha256(sw_bitstream),
        "software_internal_recon": sha256(sw_internal_recon),
        "software_ref_decoded_recon": sha256(sw_ref_decoded_recon),
        "ref_bitstream": sha256(reference_bitstream),
        "ref_recon": sha256(reference_recon),
    }
    if ran_rtl:
        digests["rtl_temporary_payload"] = sha256(rtl_bitstream)
        digests["rtl_temporary_recon"] = sha256(rtl_internal_recon)

    print("FrameForge AV2 validation checksums")
    print(
        f"input={validation_input_path} width={info.width} height={info.height} "
        f"frames={info.frames} format={info.fmt}"
    )
    for name, digest in digests.items():
        print(f"{digest}  {name}")
    print_bitrate_report("software_bitstream", sw_bitstream, info)
    print_bitrate_report("ref_bitstream", reference_bitstream, info)
    if ran_rtl:
        print_bitrate_report("rtl_temporary_payload", rtl_bitstream, info)
    print_psnr_report("software_internal_recon", validation_input_path, sw_internal_recon)
    print_psnr_report("software_ref_decoded_recon", validation_input_path, sw_ref_decoded_recon)
    print_psnr_report("ref_recon", validation_input_path, reference_recon)
    if ran_rtl:
        print_psnr_report("rtl_temporary_recon", validation_input_path, rtl_internal_recon)
    recon_views = {
        "input": validation_input_path,
        "software_internal_recon": sw_internal_recon,
        "software_ref_decoded_recon": sw_ref_decoded_recon,
        "ref_recon": reference_recon,
    }
    if ran_rtl:
        recon_views["rtl_temporary_recon"] = rtl_internal_recon
    write_recon_views(
        args.recon_format,
        info,
        out_dir,
        stem,
        recon_views,
    )
    if digests["software_internal_recon"] != digests["input_yuv"]:
        print("FAIL: AV2 software internal reconstruction differs from black input", file=sys.stderr)
        return 1
    if digests["software_ref_decoded_recon"] != digests["input_yuv"]:
        print("FAIL: AV2 REF decode of software bitstream differs from black input", file=sys.stderr)
        return 1
    if digests["ref_recon"] != digests["input_yuv"]:
        print("FAIL: AV2 REF reconstruction differs from black input", file=sys.stderr)
        return 1
    print("OK: AV2 software bitstream decodes to black 64x64 yuv444p8")
    print("OK: AV2 software internal reconstruction matches black input")
    print("OK: AV2 REF decode of software bitstream matches black input")
    print("OK: AV2 REF reconstruction matches black input")
    if ran_rtl:
        if digests["rtl_temporary_payload"] != digests["software_bitstream"]:
            print("FAIL: AV2 RTL still emits the temporary raw payload, not the fixed OBU bitstream", file=sys.stderr)
            return 1
        if digests["rtl_temporary_recon"] != digests["input_yuv"]:
            print("FAIL: AV2 RTL temporary reconstruction differs from black input", file=sys.stderr)
            return 1
        print("OK: AV2 RTL temporary reconstruction matches black input")
    return 0


def av2_black_64x64_444_reconstruction(info: InputInfo) -> bytes | None:
    if info.width != 64 or info.height != 64 or info.frames != 1:
        return None
    if normalize_format(info.fmt) != "yuv444p8":
        return None
    return bytes(frame_len(info))


def resolve_input_format(input_path: Path, requested: str) -> str:
    value = requested.lower()
    if value not in SUPPORTED_INPUT_FORMATS:
        raise ValueError(f"unsupported input format {requested}")
    if value != "auto":
        return "raw-yuv" if value in RAW_INPUT_FORMATS else value
    if input_path.suffix.lower() == ".png":
        return "png"
    return "raw-yuv"


def resolve_input_info(input_path: Path, args: argparse.Namespace, input_format: str) -> InputInfo:
    inferred = infer_from_filename(input_path.name)
    width = args.width if args.width is not None else inferred.width
    height = args.height if args.height is not None else inferred.height
    frames = args.frames if args.frames is not None else inferred.frames
    fmt = args.format if args.format is not None else inferred.fmt

    if input_format == "png":
        png_width, png_height = png_dimensions(input_path)
        width = args.width if args.width is not None else png_width
        height = args.height if args.height is not None else png_height
        frames = args.frames if args.frames is not None else 1
        fmt = args.format if args.format is not None else "yuv444p8"

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
    input_format: str,
    sw_only: bool = False,
    allow_trailing: bool = False,
) -> None:
    if normalize_format(info.fmt) not in SUPPORTED_FORMATS.values():
        raise ValueError(
            f"unsupported format {info.fmt}; supported VVC formats are "
            "yuv420p/yuv422p/yuv444p at 8, 10, 12, or 16 bits"
        )
    if not sw_only and (info.width > max_width or info.height > max_height):
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

    if input_format == "png":
        if normalize_format(info.fmt) != "yuv444p8":
            raise ValueError("PNG validation is currently lossless RGB carried as yuv444p8/GBR only")
        if info.frames != 1:
            raise ValueError("PNG validation currently supports one still-image frame")
        png_width, png_height = png_dimensions(input_path)
        if (info.width, info.height) != (png_width, png_height):
            raise ValueError(
                f"PNG input dimensions are {png_width}x{png_height}; crop with a manifest "
                "or pass matching --width/--height"
            )
        return

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


def print_bitrate_report(label: str, bitstream_path: Path, info: InputInfo) -> None:
    encoded_bytes = bitstream_path.stat().st_size
    encoded_bits = encoded_bytes * 8
    luma_pixels = info.width * info.height * info.frames
    source_bytes = frame_len(info) * info.frames
    bpp = encoded_bits / luma_pixels if luma_pixels else float("nan")
    source_ratio = encoded_bytes / source_bytes if source_bytes else float("nan")
    print(f"{encoded_bytes}  {label}_bytes")
    print(f"{encoded_bits}  {label}_bits")
    print(f"{bpp:.4f}  {label}_bits_per_luma_pixel")
    print(f"{source_ratio:.4f}  {label}_encoded_to_source_bytes")


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


def materialized_validation_input(
    input_path: Path,
    info: InputInfo,
    out_dir: Path,
    stem: str,
    input_format: str,
) -> Path:
    if input_format == "png":
        out = out_dir / f"{stem}_input_gbrp_as_yuv444p8.yuv"
        out.write_bytes(png_to_gbr_yuv444p8(input_path, info))
        return out

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


def require_pillow() -> None:
    if Image is None:
        raise ValueError("PNG validation requires Pillow; install requirements-dev.txt")


def png_dimensions(input_path: Path) -> tuple[int, int]:
    require_pillow()
    with Image.open(input_path) as image:
        return image.size


def png_to_gbr_yuv444p8(input_path: Path, info: InputInfo) -> bytes:
    require_pillow()
    with Image.open(input_path) as image:
        if image.size != (info.width, info.height):
            raise ValueError(
                f"PNG input dimensions are {image.size[0]}x{image.size[1]}; expected {info.width}x{info.height}"
            )
        rgb = image.convert("RGB")
        red_plane, green_plane, blue_plane = rgb.split()
        return green_plane.tobytes() + blue_plane.tobytes() + red_plane.tobytes()


def write_recon_views(
    recon_format: str,
    info: InputInfo,
    out_dir: Path,
    stem: str,
    paths: dict[str, Path | None],
) -> None:
    if recon_format in {"codec", "raw"}:
        return
    if info.fmt != "yuv444p8" or info.frames != 1:
        print(f"SKIP  recon_{recon_format}_views")
        return

    if recon_format == "png":
        require_pillow()

    print(f"FrameForge validate: write {recon_format} inspection views")
    for label, path in paths.items():
        if path is None or not path.exists():
            continue
        rgb24 = gbr_yuv444p8_to_rgb24(path.read_bytes(), info)
        if recon_format == "rgb24":
            out = out_dir / f"{stem}_{label}.rgb"
            out.write_bytes(rgb24)
        elif recon_format == "png":
            out = out_dir / f"{stem}_{label}.png"
            image = Image.frombytes("RGB", (info.width, info.height), rgb24)
            image.save(out)
        else:
            raise ValueError(f"unsupported reconstruction format {recon_format}")
        print(f"{sha256(out)}  {label}_{recon_format}={out}")


def gbr_yuv444p8_to_rgb24(data: bytes, info: InputInfo) -> bytes:
    expected_len = frame_len(info)
    if len(data) < expected_len:
        raise ValueError(
            f"reconstruction view source is too short: got {len(data)} bytes, expected at least {expected_len}"
        )
    plane_len = info.width * info.height
    green = data[:plane_len]
    blue = data[plane_len : plane_len * 2]
    red = data[plane_len * 2 : plane_len * 3]
    out = bytearray(plane_len * 3)
    for idx in range(plane_len):
        out[idx * 3] = red[idx]
        out[(idx * 3) + 1] = green[idx]
        out[(idx * 3) + 2] = blue[idx]
    return bytes(out)


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
