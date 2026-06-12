#!/usr/bin/env python3
"""Optional external decoder wrapper for future FrameForge validation."""

import argparse
import os
import signal
import shlex
import subprocess
import sys
from pathlib import Path

from codec_config import add_codec_arg, codec_config_from_args


REPO_ROOT = Path(__file__).resolve().parents[1]
VTM_CRASH_SKIP_EXIT = 77
VTM_CRASH_SIGNALS = {
    signal.SIGABRT,
    signal.SIGBUS,
    signal.SIGFPE,
    signal.SIGILL,
    signal.SIGSEGV,
}


def find_decoder_command(codec) -> list[str] | None:
    decoder = os.environ.get("FRAMEFORGE_DECODER")
    if decoder:
        return shlex.split(decoder)

    decoder = os.environ.get("FRAMEFORGE_VTM_DECODER")
    if decoder:
        return [decoder]

    helper = Path(__file__).with_name("ensure_reference_decoder.py")
    completed = subprocess.run(
        [sys.executable, str(helper), "--codec", codec.name, "--print-command"],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        if completed.stderr:
            print(completed.stderr, end="", file=sys.stderr)
        return None

    command = completed.stdout.strip()
    return shlex.split(command) if command else None


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Run an optional external decoder. FrameForge output is currently "
            "placeholder data, so successful decoding is not guaranteed."
        )
    )
    add_codec_arg(parser)
    parser.add_argument("bitstream", help="bitstream path to pass to the decoder")
    parser.add_argument("-o", "--output", help="optional decoded output path")
    args, extra = parser.parse_known_args()
    codec = codec_config_from_args(args)

    cmd = find_decoder_command(codec)
    if not cmd:
        print(
            "No external decoder is configured or available. Set FRAMEFORGE_DECODER, "
            "FRAMEFORGE_VTM_DECODER, or FRAMEFORGE_VTM_ROOT, or allow the reference "
            f"decoder helper to clone/build VTM under {codec.reference_dir}.",
            file=sys.stderr,
        )
        return 2

    if is_vtm_decoder(cmd):
        cmd.extend(["-b", args.bitstream])
        if is_vtm_analyser(cmd) and not any(arg.startswith("--Stats") for arg in cmd):
            cmd.append("--Stats=0")
    else:
        cmd.append(args.bitstream)
    if args.output:
        cmd.extend(["-o", args.output])
    cmd.extend(extra)

    quiet_success = is_vtm_analyser(cmd)
    try:
        completed = subprocess.run(
            cmd,
            check=False,
            capture_output=quiet_success,
            text=quiet_success,
        )
    except FileNotFoundError:
        print(
            f"decoder '{cmd[0]}' was not found. Set FRAMEFORGE_DECODER to an "
            "installed decoder executable such as vvdecapp or a VTM decoder.",
            file=sys.stderr,
        )
        return 127

    if completed.returncode != 0:
        if quiet_success:
            if completed.stdout:
                print(completed.stdout, end="")
            if completed.stderr:
                print(completed.stderr, end="", file=sys.stderr)
        if is_vtm_executable(cmd):
            signum = decoder_crash_signal(completed.returncode)
            if signum is not None:
                print(
                    f"SKIP: VTM decoder terminated by {signal.Signals(signum).name}; "
                    "skip only the external VTM comparison for this run. The same "
                    "test vector can still be used for software/RTL comparisons, "
                    "and can be retried against VTM after the generated bitstream changes.",
                    file=sys.stderr,
                )
                return VTM_CRASH_SKIP_EXIT
        print(
            "decoder returned a non-zero status. This is expected for experimental "
            "FrameForge streams that are not yet decodable VVC/H.266 pictures, and "
            "does not imply conformance.",
            file=sys.stderr,
        )
    return completed.returncode


def decoder_crash_signal(returncode: int) -> int | None:
    if returncode < 0:
        signum = -returncode
    elif returncode >= 128:
        signum = returncode - 128
    else:
        return None

    try:
        sig = signal.Signals(signum)
    except ValueError:
        return None
    return signum if sig in VTM_CRASH_SIGNALS else None


def is_vtm_executable(cmd: list[str]) -> bool:
    if not cmd:
        return False
    name = Path(cmd[0]).name
    return name.startswith("DecoderApp") or name.startswith("DecoderAnalyserApp")


def is_vtm_decoder(cmd: list[str]) -> bool:
    if not cmd:
        return False
    name = Path(cmd[0]).name
    return (
        (name.startswith("DecoderApp") or name.startswith("DecoderAnalyserApp"))
        and "-b" not in cmd
        and "--BitstreamFile" not in cmd
    )


def is_vtm_analyser(cmd: list[str]) -> bool:
    return bool(cmd) and Path(cmd[0]).name.startswith("DecoderAnalyserApp")


if __name__ == "__main__":
    raise SystemExit(main())
