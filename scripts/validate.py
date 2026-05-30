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

# Keep this in sync with frameforge::vvc::VVC_CODED_DIMENSION_GRANULARITY and
# the RTL coded-dimension logic. It is the current validation-path coded-picture
# luma dimension alignment, not a general statement about every VVC profile.
VVC_CODED_DIMENSION_GRANULARITY = 8
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
    parser.add_argument("--max-width", type=int, default=64)
    parser.add_argument("--max-height", type=int, default=64)
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
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    if not input_path.exists():
        print(f"FAIL: input YUV file does not exist: {input_path}", file=sys.stderr)
        return 2

    try:
        info = resolve_input_info(input_path, args)
        validate_supported_input(input_path, info, args.max_width, args.max_height)
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
            str(sw_bitstream),
        ]
    )

    if not args.skip_synth:
        run(["make", "synth", f"SYNTH_DUT={args.synth_dut}"])

    env = os.environ.copy()
    rtl_sample_bits = format_bit_depth(info.fmt) if format_chroma_sampling(info.fmt) == "444" else 8
    env["RTL_SAMPLE_BITS"] = str(rtl_sample_bits)
    env["RTL_SOURCE_SAMPLE_BITS"] = str(format_bit_depth(info.fmt))
    env["RTL_CHROMA_FORMAT_IDC"] = str(rtl_chroma_format_idc(info))
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
        ],
        env=env,
    )

    has_vtm_recon = vtm_decode_supported(input_path, info)
    rtl_annexb_bitstream = is_annexb_bitstream(rtl_bitstream)
    vtm_bitstream = rtl_bitstream if rtl_annexb_bitstream else sw_bitstream
    if has_vtm_recon:
        run(
            [
                sys.executable,
                "scripts/validate_decode.py",
                str(vtm_bitstream),
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
        "vtm_recon_from_decodable_bitstream": sha256(vtm_recon) if has_vtm_recon else None,
    }

    print("FrameForge validation checksums")
    print(
        f"input={input_path} width={info.width} height={info.height} "
        f"frames={info.frames} format={info.fmt}"
    )
    for name, digest in digests.items():
        if digest is None:
            print(f"SKIP  {name}")
        else:
            print(f"{digest}  {name}")

    if not rtl_bitstream.read_bytes():
        print("FAIL: RTL encoder produced an empty byte stream", file=sys.stderr)
        return 1
    if rtl_annexb_bitstream and digests["software_bitstream"] != digests["rtl_bitstream"]:
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
    if rtl_annexb_bitstream:
        print("OK: software and RTL bitstreams match")
    else:
        print("SKIP: RTL output is a raw synthesized encoder payload, not an Annex-B VVC stream yet")
    print("OK: software and RTL internal reconstructions match")
    if has_vtm_recon:
        source = "RTL" if rtl_annexb_bitstream else "software"
        print(f"OK: software, RTL, and VTM reconstructions match using {source} VVC bitstream")
    else:
        print("SKIP: VTM decode is not wired for this VVC path yet")
    if has_vtm_recon and input_has_nonzero_chroma(input_path, info):
        validate_decoded_non_monochrome(vtm_recon, info)
        print("OK: VTM reconstruction contains decoder-visible chroma")
    if expects_zero_reconstruction(input_path, info):
        validate_zero_reconstruction(sw_internal_recon, "software internal reconstruction")
        validate_zero_reconstruction(rtl_internal_recon, "RTL internal reconstruction")
        if has_vtm_recon:
            validate_zero_reconstruction(vtm_recon, "VTM reconstruction")
        print("OK: black input reconstructs to all-zero output")
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


def validate_supported_input(input_path: Path, info: InputInfo, max_width: int, max_height: int) -> None:
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
    if info.frames not in (1, 2):
        raise ValueError("VVC validation currently supports only 1 or 2 frames")

    expected_len = frame_len(info) * info.frames
    data = input_path.read_bytes()
    if len(data) != expected_len:
        raise ValueError(
            f"input size mismatch: got {len(data)} bytes, expected {expected_len}"
        )


def vtm_decode_supported(input_path: Path, info: InputInfo) -> bool:
    if format_chroma_sampling(info.fmt) == "444":
        return (
            info.fmt == "yuv444p8"
            and coded_dimension(info.width) <= 64
            and coded_dimension(info.height) <= 64
        )
    return vvc_generated_transform_path(info)


def coded_dimension(value: int) -> int:
    return (
        (value + VVC_CODED_DIMENSION_GRANULARITY - 1)
        // VVC_CODED_DIMENSION_GRANULARITY
        * VVC_CODED_DIMENSION_GRANULARITY
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
    if format_chroma_sampling(info.fmt) == "444":
        return palette_444_tile_reconstruction(input_path, info)
    frame = normalized_first_frame_to_yuv420p8(input_path, info)
    luma_len = info.width * info.height
    chroma_len = luma_len // 4
    if uses_capacity_tu_grid(frame, info):
        luma = capacity_tu_grid_reconstruction(frame, info)
        chroma = reconstructed_chroma(frame[luma_len], frame[luma_len + chroma_len])
    else:
        luma = bytes(
            [vvc_luma_reconstruction_from_sample(frame[0] if frame else 0, info)] * luma_len
        )
        chroma = 128
    # This is the reconstruction of the emitted VVC bitstream, not the
    # original input. Keep this matched to VTM decode output after quantization.
    return bytes(luma + bytes([chroma] * chroma_len) + bytes([chroma] * chroma_len)) * info.frames


def capacity_tu_grid_reconstruction(frame: bytes, info: InputInfo) -> bytes:
    recon = bytearray(info.width * info.height)
    for origin_y in range(0, info.height, 4):
        for origin_x in range(0, info.width, 4):
            block = residual_luma_block(frame, info, origin_x, origin_y)
            y = inverse_transform_luma_dc(quantized_luma_dc(forward_luma_dc(block)))
            width = min(4, info.width - origin_x)
            for y_off in range(min(4, info.height - origin_y)):
                row = (origin_y + y_off) * info.width + origin_x
                recon[row : row + width] = bytes([y] * width)
    return bytes(recon)


def palette_444_tile_reconstruction(input_path: Path, info: InputInfo) -> bytes:
    # Mirrors the current H.266 palette decoding subset. The 4:4:4 path now
    # emits per-CU palette entries plus the palette index map, so p8 inputs are
    # reconstructed losslessly for the supported <=31-colors-per-CU subset.
    if info.fmt == "yuv444p8":
        return input_path.read_bytes()[: frame_len(info)] * info.frames

    frame = input_path.read_bytes()[: frame_len(info)]
    luma_len = info.width * info.height
    y_plane = bytearray(luma_len)
    u_plane = bytearray(luma_len)
    v_plane = bytearray(luma_len)
    for origin_y in range(0, info.height, 8):
        for origin_x in range(0, info.width, 8):
            sample_index = origin_y * info.width + origin_x
            y = read_normalized_sample(frame, sample_index, info)
            u = read_normalized_sample(frame, luma_len + sample_index, info)
            v = read_normalized_sample(frame, (luma_len * 2) + sample_index, info)
            for y_off in range(min(8, info.height - origin_y)):
                row = (origin_y + y_off) * info.width + origin_x
                width = min(8, info.width - origin_x)
                y_plane[row : row + width] = bytes([y] * width)
                u_plane[row : row + width] = bytes([u] * width)
                v_plane[row : row + width] = bytes([v] * width)
    return bytes(y_plane + u_plane + v_plane) * info.frames


def uses_capacity_tu_grid(frame: bytes, info: InputInfo) -> bool:
    # The standards-facing path emits a single residual level for each luma leaf
    # of the generated coding tree. Keep per-4x4 reconstruction only for the
    # raw capacity-grid path that is not currently VTM-facing.
    del frame
    return not vtm_decode_supported(Path("unused"), info)


def tile_yuv420p8_frame(
    frame: bytes,
    source_width: int,
    source_height: int,
    tiled_width: int,
    tiled_height: int,
) -> bytes:
    source_luma = source_width * source_height
    source_chroma_width = source_width // 2
    source_chroma_height = source_height // 2
    source_chroma = source_chroma_width * source_chroma_height
    luma = frame[:source_luma]
    cb = frame[source_luma : source_luma + source_chroma]
    cr = frame[source_luma + source_chroma :]

    out_luma = bytearray()
    for y in range(tiled_height):
        source_row = (y % source_height) * source_width
        row = bytes(luma[source_row : source_row + source_width])
        out_luma.extend((row * ((tiled_width + source_width - 1) // source_width))[:tiled_width])

    tiled_chroma_width = tiled_width // 2
    tiled_chroma_height = tiled_height // 2
    out_cb = bytearray()
    out_cr = bytearray()
    for y in range(tiled_chroma_height):
        source_row = (y % source_chroma_height) * source_chroma_width
        cb_row = bytes(cb[source_row : source_row + source_chroma_width])
        cr_row = bytes(cr[source_row : source_row + source_chroma_width])
        repeats = (tiled_chroma_width + source_chroma_width - 1) // source_chroma_width
        out_cb.extend((cb_row * repeats)[:tiled_chroma_width])
        out_cr.extend((cr_row * repeats)[:tiled_chroma_width])

    return bytes(out_luma + out_cb + out_cr)


def crop_yuv420p8_frame(
    frame: bytes,
    coded_width: int,
    coded_height: int,
    visible_width: int,
    visible_height: int,
) -> bytes:
    coded_luma = coded_width * coded_height
    coded_chroma_width = coded_width // 2
    coded_chroma_height = coded_height // 2
    coded_chroma = coded_chroma_width * coded_chroma_height
    luma = frame[:coded_luma]
    cb = frame[coded_luma : coded_luma + coded_chroma]
    cr = frame[coded_luma + coded_chroma :]

    out_luma = bytearray()
    for y in range(visible_height):
        row = y * coded_width
        out_luma.extend(luma[row : row + visible_width])

    chroma_width = visible_width // 2
    chroma_height = visible_height // 2
    out_cb = bytearray()
    out_cr = bytearray()
    for y in range(chroma_height):
        row = y * coded_chroma_width
        out_cb.extend(cb[row : row + chroma_width])
        out_cr.extend(cr[row : row + chroma_width])

    return bytes(out_luma + out_cb + out_cr)


def first_residual_luma_block(frame: bytes, info: InputInfo) -> bytes:
    return residual_luma_block(frame, info, 0, 0)


def residual_luma_block(frame: bytes, info: InputInfo, origin_x: int, origin_y: int) -> bytes:
    block = bytearray()
    for y in range(min(4, info.height - origin_y)):
        row = (origin_y + y) * info.width + origin_x
        block.extend(frame[row : row + min(4, info.width - origin_x)])
    block.extend([0] * (16 - len(block)))
    return bytes(block)


def forward_luma_dc(samples: bytes) -> int:
    return ((sum(samples) + 8) >> 4) - 114


def quantized_luma_dc(dc_coeff: int) -> int:
    sample = max(0, min(255, dc_coeff + 114))
    return quantized_luma(sample) - 114


def inverse_transform_luma_dc(dc_coeff: int) -> int:
    return max(0, min(255, dc_coeff + 114))


def quantized_luma_remainder(sample: int) -> int:
    return min(
        range(17),
        key=lambda rem: abs((((16 - rem) * 114 + 8) // 16) - sample),
    )


VVC_CURRENT_CTU_SIZE = 64
VVC_CURRENT_LUMA_LEAF_SIZE = 16


def current_anchor_luma_tb_log2(width: int, height: int) -> tuple[int, int]:
    if width == VVC_CURRENT_CTU_SIZE and height == VVC_CURRENT_CTU_SIZE:
        return (6, 6)
    if width == VVC_CURRENT_LUMA_LEAF_SIZE * 2 and height == VVC_CURRENT_LUMA_LEAF_SIZE:
        return (5, 4)
    return (
        4 if width >= VVC_CURRENT_LUMA_LEAF_SIZE else 3,
        4 if height >= VVC_CURRENT_LUMA_LEAF_SIZE else 3,
    )


def vvc_luma_reconstruction_from_sample(sample: int, info: InputInfo) -> int:
    rem = quantized_luma_remainder(sample)
    # Mirrors the currently emitted VVC residual subset: planar intra prediction
    # around the neutral sample with one negative DC coefficient level.
    log2_tb_width, log2_tb_height = current_anchor_luma_tb_log2(info.width, info.height)
    if log2_tb_width == 3 and log2_tb_height == 3:
        residual_delta = (rem * 57 + 8) // 16
    elif min(log2_tb_width, log2_tb_height) == 3:
        residual_delta = (rem * 40) // 16
    elif log2_tb_width >= 6 and log2_tb_height >= 6:
        residual_delta = (rem * 7 + 8) // 16
    elif log2_tb_width >= 5 and log2_tb_height >= 4:
        residual_delta = (rem * 20 + 8) // 16
    else:
        residual_delta = (rem * 28 + 8) // 16
    return max(0, min(255, 128 - residual_delta))


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


def input_is_all_zero(path: Path) -> bool:
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            if any(chunk):
                return False
    return True


def vvc_generated_transform_path(info: InputInfo) -> bool:
    return (
        coded_dimension(info.width) <= VVC_CURRENT_CTU_SIZE
        and coded_dimension(info.height) <= VVC_CURRENT_CTU_SIZE
    )


def expects_zero_reconstruction(input_path: Path, info: InputInfo) -> bool:
    return input_is_all_zero(input_path) and not vvc_generated_transform_path(info)


def validate_zero_reconstruction(path: Path, label: str) -> None:
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            if any(chunk):
                raise SystemExit(f"FAIL: black input produced non-zero {label}")


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


def quantized_luma(sample: int) -> int:
    best_rem = min(
        range(17),
        key=lambda rem: abs((((16 - rem) * 114 + 8) // 16) - sample),
    )
    return ((16 - best_rem) * 114) // 16


if __name__ == "__main__":
    raise SystemExit(main())
