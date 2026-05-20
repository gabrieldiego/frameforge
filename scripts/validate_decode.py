#!/usr/bin/env python3
"""Optional external decoder wrapper for future FrameForge validation."""

import argparse
import os
import shlex
import subprocess
import sys


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

    decoder = os.environ.get("FRAMEFORGE_DECODER")
    if not decoder:
        print(
            "FRAMEFORGE_DECODER is not set. External decoder validation is planned "
            "but not required for the current placeholder bitstream.",
            file=sys.stderr,
        )
        return 2

    cmd = shlex.split(decoder)
    if not cmd:
        print("FRAMEFORGE_DECODER is empty.", file=sys.stderr)
        return 2

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
            "decoder returned a non-zero status. This is expected for the current "
            "FrameForge placeholder output and does not imply conformance.",
            file=sys.stderr,
        )
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
