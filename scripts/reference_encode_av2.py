#!/usr/bin/env python3
"""Generate an AV2 reference bitstream with the external AVM encoder."""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path

from codec_config import add_codec_arg, codec_config_from_args, CodecConfig
from validate import InputInfo, format_bit_depth, format_chroma_sampling, frame_len, normalize_format


REPO_ROOT = Path(__file__).resolve().parents[1]
ENCODER_NAMES = ("avmenc", "avmenc.exe", "aomenc", "aomenc.exe")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    add_codec_arg(parser)
    parser.add_argument("--input", required=True, help="planar raw YUV input path")
    parser.add_argument("--output", required=True, help="AV2 reference bitstream output path")
    parser.add_argument("--recon", help="optional decoded reconstruction output path")
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--frames", type=int, required=True)
    parser.add_argument("--format", required=True)
    parser.add_argument("--cpu-used", type=int, default=8)
    parser.add_argument("--cq-level", type=int, default=0)
    parser.add_argument(
        "--keep-y4m",
        action="store_true",
        help="keep the generated Y4M adapter file next to the bitstream",
    )
    args = parser.parse_args()
    codec = codec_config_from_args(args)
    if codec.name != "av2":
        print("reference_encode_av2.py only supports --codec av2", file=sys.stderr)
        return 2

    info = InputInfo(
        width=args.width,
        height=args.height,
        frames=args.frames,
        fmt=normalize_format(args.format),
    )
    try:
        validate_reference_input(Path(args.input), info)
        encoder = find_encoder(codec)
    except RuntimeError as err:
        print(err, file=sys.stderr)
        return 2

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    y4m_path = output_path.with_suffix(output_path.suffix + ".input.y4m")
    write_y4m(Path(args.input), y4m_path, info)

    completed = run_encoder(encoder, y4m_path, output_path, info, args)
    if completed.returncode != 0:
        if not args.keep_y4m:
            y4m_path.unlink(missing_ok=True)
        return completed.returncode

    if args.recon:
        recon_path = Path(args.recon)
        recon_path.parent.mkdir(parents=True, exist_ok=True)
        decoded = decode_reference(codec, output_path, recon_path)
        if decoded != 0:
            if not args.keep_y4m:
                y4m_path.unlink(missing_ok=True)
            return decoded
        print(f"wrote AV2 reference reconstruction: {recon_path}")

    if not args.keep_y4m:
        y4m_path.unlink(missing_ok=True)
    print(f"wrote AV2 reference bitstream: {output_path}")
    return 0


def validate_reference_input(input_path: Path, info: InputInfo) -> None:
    if info.width <= 0 or info.height <= 0:
        raise RuntimeError("reference AV2 encode expects positive dimensions")
    if info.frames <= 0:
        raise RuntimeError("reference AV2 encode expects at least one frame")
    if format_bit_depth(info.fmt) != 8:
        raise RuntimeError("initial AV2 reference encode wrapper supports only 8-bit YUV")
    if format_chroma_sampling(info.fmt) == "420" and (info.width % 2 or info.height % 2):
        raise RuntimeError("reference AV2 4:2:0 encode expects even width and height")
    if format_chroma_sampling(info.fmt) == "422" and info.width % 2:
        raise RuntimeError("reference AV2 4:2:2 encode expects even width")
    expected = frame_len(info) * info.frames
    actual = input_path.stat().st_size
    if actual < expected:
        raise RuntimeError(f"input size mismatch: got {actual} bytes, expected at least {expected}")


def write_y4m(input_path: Path, y4m_path: Path, info: InputInfo) -> None:
    y4m_path.parent.mkdir(parents=True, exist_ok=True)
    chroma = y4m_chroma(info)
    header = f"YUV4MPEG2 W{info.width} H{info.height} F1:1 Ip A1:1 C{chroma}\n"
    frame_bytes = frame_len(info)
    remaining_frames = info.frames
    with input_path.open("rb") as src, y4m_path.open("wb") as dst:
        dst.write(header.encode("ascii"))
        while remaining_frames:
            frame = src.read(frame_bytes)
            if len(frame) != frame_bytes:
                raise RuntimeError("input ended before all requested AV2 reference frames were read")
            dst.write(b"FRAME\n")
            dst.write(frame)
            remaining_frames -= 1


def y4m_chroma(info: InputInfo) -> str:
    sampling = format_chroma_sampling(info.fmt)
    if sampling == "420":
        return "420jpeg"
    if sampling == "422":
        return "422"
    if sampling == "444":
        return "444"
    raise RuntimeError(f"unsupported AV2 reference chroma format {info.fmt}")


def find_encoder(codec: CodecConfig) -> Path:
    for env_name in ("FRAMEFORGE_AV2_ENCODER", "FRAMEFORGE_AVM_ENCODER"):
        configured = os.environ.get(env_name)
        if configured:
            path = Path(configured)
            if path.exists():
                return path
            raise RuntimeError(f"{env_name} does not exist: {path}")

    found = find_executable_in_roots(ENCODER_NAMES, candidate_avm_roots(codec))
    if found:
        return found

    helper = Path(__file__).with_name("ensure_reference_decoder.py")
    completed = subprocess.run(
        [sys.executable, str(helper), "--codec", codec.name],
        cwd=REPO_ROOT,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError("failed to build AVM reference tools")

    found = find_executable_in_roots(ENCODER_NAMES, candidate_avm_roots(codec))
    if found:
        return found

    roots = ", ".join(str(root) for root in candidate_avm_roots(codec))
    raise RuntimeError(f"no AVM encoder executable found under: {roots}")


def find_executable_in_roots(names: tuple[str, ...], roots: list[Path]) -> Path | None:
    for root in roots:
        if not root.exists():
            continue
        for name in names:
            for path in root.rglob(name):
                if path.is_file() and os.access(path, os.X_OK):
                    return path
    return None


def candidate_avm_roots(codec: CodecConfig) -> list[Path]:
    if root := os.environ.get("FRAMEFORGE_AV2_ROOT"):
        return [Path(root)]
    if root := os.environ.get("FRAMEFORGE_AVM_ROOT"):
        return [Path(root)]
    return [Path(os.environ.get("FRAMEFORGE_REF_DIR", codec.reference_dir)) / "avm"]


def run_encoder(
    encoder: Path,
    y4m_path: Path,
    output_path: Path,
    info: InputInfo,
    args: argparse.Namespace,
) -> subprocess.CompletedProcess:
    if template := os.environ.get("FRAMEFORGE_AV2_ENCODER_CMD"):
        command = command_from_template(template, encoder, y4m_path, output_path, info, args)
        return run_single_encoder_command(command, output_path)
    if template := os.environ.get("FRAMEFORGE_AVM_ENCODER_CMD"):
        command = command_from_template(template, encoder, y4m_path, output_path, info, args)
        return run_single_encoder_command(command, output_path)

    attempts = default_encoder_commands(encoder, y4m_path, output_path, info, args)
    failures: list[tuple[list[str], subprocess.CompletedProcess]] = []
    for command in attempts:
        completed = run_single_encoder_command(command, output_path)
        if completed.returncode == 0:
            return completed
        output_path.unlink(missing_ok=True)
        failures.append((command, completed))

    print("AVM encoder failed for all known command forms.", file=sys.stderr)
    for command, completed in failures:
        print(f"$ {shlex.join(command)}", file=sys.stderr)
        print(f"exit status: {completed.returncode}", file=sys.stderr)
        if completed.stdout:
            print_tail("stdout", completed.stdout)
        if completed.stderr:
            print_tail("stderr", completed.stderr)
    return failures[-1][1]


def command_from_template(
    template: str,
    encoder: Path,
    y4m_path: Path,
    output_path: Path,
    info: InputInfo,
    args: argparse.Namespace,
) -> list[str]:
    values = {
        "encoder": str(encoder),
        "input": str(y4m_path),
        "output": str(output_path),
        "frames": str(info.frames),
        "width": str(info.width),
        "height": str(info.height),
        "format": info.fmt,
        "sampling": format_chroma_sampling(info.fmt),
        "bit_depth": str(format_bit_depth(info.fmt)),
        "cpu_used": str(args.cpu_used),
        "cq_level": str(args.cq_level),
    }
    return shlex.split(template.format(**values))


def default_encoder_commands(
    encoder: Path,
    y4m_path: Path,
    output_path: Path,
    info: InputInfo,
    args: argparse.Namespace,
) -> list[list[str]]:
    common = [
        f"--limit={info.frames}",
        f"--cpu-used={args.cpu_used}",
        "--passes=1",
    ]
    quality = [
        "--lossless=1",
        "--end-usage=q",
        f"--cq-level={args.cq_level}",
    ]
    output = ["-o", str(output_path), str(y4m_path)]
    return [
        [str(encoder), "--codec=av2", *common, *quality, "--obu", *output],
        [str(encoder), *common, *quality, "--obu", *output],
        [
            str(encoder),
            "--codec=av2",
            *common,
            "--end-usage=q",
            f"--cq-level={args.cq_level}",
            "--obu",
            *output,
        ],
        [str(encoder), *common, "--end-usage=q", f"--cq-level={args.cq_level}", "--obu", *output],
        [str(encoder), f"--limit={info.frames}", "--obu", "-o", str(output_path), str(y4m_path)],
    ]


def run_single_encoder_command(command: list[str], output_path: Path) -> subprocess.CompletedProcess:
    output_path.unlink(missing_ok=True)
    return subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )


def decode_reference(codec: CodecConfig, bitstream_path: Path, recon_path: Path) -> int:
    helper = Path(__file__).with_name("validate_decode.py")
    cmd = [
        sys.executable,
        str(helper),
        "--codec",
        codec.name,
        str(bitstream_path),
        "--output",
        str(recon_path),
    ]
    cmd.extend(configured_decoder_args())
    completed = subprocess.run(cmd, cwd=REPO_ROOT, check=False)
    return completed.returncode


def configured_decoder_args() -> list[str]:
    for env_name in ("FRAMEFORGE_AV2_DECODER_ARGS", "FRAMEFORGE_AVM_DECODER_ARGS"):
        if env_name in os.environ:
            return shlex.split(os.environ[env_name])
    return ["--rawvideo"]


def print_tail(label: str, text: str) -> None:
    tail = text[-4000:]
    print(f"{label} tail:", file=sys.stderr)
    print(tail, end="" if tail.endswith("\n") else "\n", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
