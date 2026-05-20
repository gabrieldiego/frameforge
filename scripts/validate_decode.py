#!/usr/bin/env python3
"""Optional external decoder wrapper for future FrameForge validation."""

import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path


def find_decoder_command() -> list[str] | None:
    decoder = os.environ.get("FRAMEFORGE_DECODER")
    if decoder:
        return shlex.split(decoder)

    decoder = os.environ.get("FRAMEFORGE_VTM_DECODER")
    if decoder:
        return [decoder]

    helper = Path(__file__).with_name("ensure_reference_decoder.py")
    completed = subprocess.run(
        [sys.executable, str(helper), "--print-command"],
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
    parser.add_argument("bitstream", help="bitstream path to pass to the decoder")
    parser.add_argument("-o", "--output", help="optional decoded output path")
    args, extra = parser.parse_known_args()

    cmd = find_decoder_command()
    if not cmd:
        print(
            "No external decoder is configured or available. Set FRAMEFORGE_DECODER, "
            "FRAMEFORGE_VTM_DECODER, or FRAMEFORGE_VTM_ROOT, or allow the reference "
            "decoder helper to clone/build VTM under verification/reference.",
            file=sys.stderr,
        )
        return 2

    if is_vtm_decoder(cmd):
        cmd.extend(["-b", args.bitstream])
    else:
        cmd.append(args.bitstream)
    if args.output:
        cmd.extend(["-o", args.output])
    cmd.extend(extra)

    try:
        completed = subprocess.run(cmd, check=False)
    except FileNotFoundError:
        print(
            f"decoder '{cmd[0]}' was not found. Set FRAMEFORGE_DECODER to an "
            "installed decoder executable such as vvdecapp or a VTM decoder.",
            file=sys.stderr,
        )
        return 127

    if completed.returncode != 0:
        print(
            "decoder returned a non-zero status. This is expected for experimental "
            "FrameForge streams that are not yet decodable VVC/H.266 pictures, and "
            "does not imply conformance.",
            file=sys.stderr,
        )
    return completed.returncode


def is_vtm_decoder(cmd: list[str]) -> bool:
    if not cmd:
        return False
    name = Path(cmd[0]).name
    return name.startswith("DecoderApp") and "-b" not in cmd and "--BitstreamFile" not in cmd


if __name__ == "__main__":
    raise SystemExit(main())
