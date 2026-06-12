#!/usr/bin/env python3
"""Find or build a codec reference decoder for validation.

FrameForge does not vendor VTM source code. This helper uses configured local
paths first and only clones/builds VTM into the selected codec reference tree
when needed.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

from codec_config import add_codec_arg, codec_config_from_args


DEFAULT_VTM_REPO = "https://vcgit.hhi.fraunhofer.de/jvet/VVCSoftware_VTM.git"
DECODER_NAMES = (
    "DecoderAnalyserAppStatic",
    "DecoderAnalyserAppStatic.exe",
    "DecoderAnalyserApp",
    "DecoderAnalyserApp.exe",
    "DecoderAppStatic",
    "DecoderAppStatic.exe",
    "DecoderApp",
    "DecoderApp.exe",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    add_codec_arg(parser)
    parser.add_argument(
        "--no-build",
        action="store_true",
        help="find an existing decoder but do not clone or build VTM",
    )
    parser.add_argument(
        "--print-command",
        action="store_true",
        help="print the decoder executable path or configured command",
    )
    args = parser.parse_args()
    codec = codec_config_from_args(args)

    configured = configured_decoder()
    if configured:
        if args.print_command:
            print(configured)
        return 0

    root = configured_vtm_root()
    if root is None and default_vtm_root(codec).exists():
        root = default_vtm_root(codec)
    elif root is None:
        for legacy in codec.legacy_reference_dirs:
            legacy_vtm = legacy / "vtm"
            if legacy_vtm.exists():
                root = legacy_vtm
                break
    decoder = find_decoder(root) if root else None
    if decoder:
        if args.print_command:
            print(decoder)
        return 0

    if args.no_build:
        print(
            "No decoder found. Set FRAMEFORGE_DECODER, FRAMEFORGE_VTM_DECODER, "
            "or FRAMEFORGE_VTM_ROOT, or run without --no-build to clone/build VTM.",
            file=sys.stderr,
        )
        return 2

    root = root or default_vtm_root(codec)
    if not root.exists():
        clone_vtm(root)

    build_vtm(root)
    decoder = find_decoder(root)
    if not decoder:
        print(
            f"VTM build completed but no decoder executable was found under {root}. "
            f"Looked for: {', '.join(DECODER_NAMES)}",
            file=sys.stderr,
        )
        return 1

    if args.print_command:
        print(decoder)
    else:
        print(f"reference decoder ready: {decoder}")
    return 0


def configured_decoder() -> str | None:
    decoder = os.environ.get("FRAMEFORGE_DECODER")
    if decoder:
        return decoder

    decoder_path = os.environ.get("FRAMEFORGE_VTM_DECODER")
    if decoder_path:
        path = Path(decoder_path)
        if path.exists():
            return str(path)
        print(f"FRAMEFORGE_VTM_DECODER does not exist: {path}", file=sys.stderr)
        return None

    return None


def configured_vtm_root() -> Path | None:
    root = os.environ.get("FRAMEFORGE_VTM_ROOT")
    return Path(root) if root else None


def default_vtm_root(codec) -> Path:
    base = Path(os.environ.get("FRAMEFORGE_REF_DIR", codec.reference_dir))
    return base / "vtm"


def clone_vtm(root: Path) -> None:
    repo = os.environ.get("FRAMEFORGE_VTM_REPO", DEFAULT_VTM_REPO)
    ref = os.environ.get("FRAMEFORGE_VTM_REF")

    root.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["git", "clone", "--depth", "1"]
    if ref:
        cmd.extend(["--branch", ref])
    cmd.extend([repo, str(root)])
    print(f"cloning VTM reference software into {root}", file=sys.stderr)
    run(cmd)


def build_vtm(root: Path) -> None:
    if not shutil.which("cmake"):
        raise SystemExit("cmake is required to build VTM")

    build_dir = Path(os.environ.get("FRAMEFORGE_VTM_BUILD_DIR", root / "build"))
    build_type = os.environ.get("FRAMEFORGE_VTM_BUILD_TYPE", "Release")
    jobs = os.environ.get("FRAMEFORGE_BUILD_JOBS")

    configure = [
        "cmake",
        "-S",
        str(root),
        "-B",
        str(build_dir),
        f"-DCMAKE_BUILD_TYPE={build_type}",
    ]
    build = ["cmake", "--build", str(build_dir), "--config", build_type]
    if jobs:
        build.extend(["--parallel", jobs])

    print(f"configuring VTM in {build_dir}", file=sys.stderr)
    run(configure)
    print("building VTM decoder tools", file=sys.stderr)
    run(build)


def find_decoder(root: Path) -> str | None:
    if not root.exists():
        return None

    for name in DECODER_NAMES:
        for path in root.rglob(name):
            if path.is_file() and os.access(path, os.X_OK):
                return str(path)
    return None


def run(cmd: list[str]) -> None:
    completed = subprocess.run(cmd, check=False, stdout=sys.stderr)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)


if __name__ == "__main__":
    raise SystemExit(main())
