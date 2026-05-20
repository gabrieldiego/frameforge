#!/usr/bin/env python3
"""Validate FrameForge toy 4x4 VVC software/RTL streams by checksum."""

from __future__ import annotations

import argparse
import hashlib
import os
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = Path("verification/generated/checksums")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=int, default=1, choices=(1, 2))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    args = parser.parse_args()

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    stem = f"toy4x4_{args.frames}f"
    sw_bitstream = out_dir / f"{stem}_software.vvc"
    rtl_bitstream = out_dir / f"{stem}_rtl.vvc"
    sw_recon = out_dir / f"{stem}_software_dec.yuv"
    rtl_recon = out_dir / f"{stem}_rtl_dec.yuv"
    expected_recon = out_dir / f"{stem}_expected_black.yuv"

    frame_len = 4 * 4 * 3 // 2
    expected_recon.write_bytes(bytes(frame_len * args.frames))

    run(
        [
            "cargo",
            "run",
            "--quiet",
            "--",
            "vvc-toy-4x4-black-video",
            "--frames",
            str(args.frames),
            "--output",
            str(sw_bitstream),
        ]
    )

    env = os.environ.copy()
    if args.frames == 1:
        env["FRAMEFORGE_RTL_TOY4X4_OUT_1F"] = str(rtl_bitstream)
    else:
        env["FRAMEFORGE_RTL_TOY4X4_OUT"] = str(rtl_bitstream)
    run(["make", "rtl-test", "DUT=vvc-toy4x4"], env=env)

    run(
        [
            sys.executable,
            "scripts/validate_decode.py",
            str(sw_bitstream),
            "--output",
            str(sw_recon),
        ]
    )
    run(
        [
            sys.executable,
            "scripts/validate_decode.py",
            str(rtl_bitstream),
            "--output",
            str(rtl_recon),
        ]
    )

    digests = {
        "software_bitstream": sha256(sw_bitstream),
        "rtl_bitstream": sha256(rtl_bitstream),
        "software_recon": sha256(sw_recon),
        "rtl_recon": sha256(rtl_recon),
        "expected_recon": sha256(expected_recon),
    }

    print("FrameForge toy 4x4 validation checksums")
    for name, digest in digests.items():
        print(f"{digest}  {name}")

    if digests["software_bitstream"] != digests["rtl_bitstream"]:
        print("FAIL: software and RTL bitstreams differ", file=sys.stderr)
        return 1
    if not (
        digests["software_recon"]
        == digests["rtl_recon"]
        == digests["expected_recon"]
    ):
        print(
            "FAIL: software decode, RTL decode, and expected reconstruction differ",
            file=sys.stderr,
        )
        return 1

    print("OK: software and RTL bitstreams match")
    print("OK: VTM reconstructions match the expected black 4x4 frame data")
    return 0


def run(cmd: list[str], env: dict[str, str] | None = None) -> None:
    subprocess.run(cmd, cwd=REPO_ROOT, env=env, check=True)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
