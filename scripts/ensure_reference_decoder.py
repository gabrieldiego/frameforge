#!/usr/bin/env python3
"""Find or build a codec reference decoder for validation.

FrameForge does not vendor reference source code. This helper uses configured
local paths first and only clones/builds reference tools into the selected codec
reference tree when needed.
"""

import argparse
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

from codec_config import add_codec_arg, codec_config_from_args


DEFAULT_VTM_REPO = "https://vcgit.hhi.fraunhofer.de/jvet/VVCSoftware_VTM.git"
DEFAULT_AVM_REPO = "https://github.com/AOMediaCodec/avm.git"
VTM_DECODER_NAMES = (
    "DecoderAnalyserAppStatic",
    "DecoderAnalyserAppStatic.exe",
    "DecoderAnalyserApp",
    "DecoderAnalyserApp.exe",
    "DecoderAppStatic",
    "DecoderAppStatic.exe",
    "DecoderApp",
    "DecoderApp.exe",
)
AVM_DECODER_NAMES = (
    "avmdec",
    "avmdec.exe",
    "aomdec",
    "aomdec.exe",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    add_codec_arg(parser)
    parser.add_argument(
        "--no-build",
        action="store_true",
        help="find an existing decoder but do not clone or build reference tools",
    )
    parser.add_argument(
        "--print-command",
        action="store_true",
        help="print the decoder executable path or configured command",
    )
    args = parser.parse_args()
    codec = codec_config_from_args(args)

    configured = configured_decoder(codec.name)
    if configured:
        if args.print_command:
            print(configured)
        return 0

    root = configured_reference_root(codec.name)
    if root is None and default_reference_root(codec).exists():
        root = default_reference_root(codec)
    elif root is None and codec.name == "vvc":
        root = first_existing_legacy_vtm_root(codec)

    decoder = find_decoder(root, decoder_names(codec.name)) if root else None
    if decoder:
        if args.print_command:
            print(decoder)
        return 0

    if args.no_build:
        print(no_decoder_message(codec.name), file=sys.stderr)
        return 2

    root = root or default_reference_root(codec)
    if not root.exists():
        clone_reference(codec.name, root)

    build_reference(codec.name, root)
    decoder = find_decoder(root, decoder_names(codec.name))
    if not decoder:
        names = ", ".join(decoder_names(codec.name))
        print(
            f"{codec.name.upper()} reference build completed but no decoder "
            f"executable was found under {root}. Looked for: {names}",
            file=sys.stderr,
        )
        return 1

    if args.print_command:
        print(decoder)
    else:
        print(f"reference decoder ready: {decoder}")
    return 0


def configured_decoder(codec_name: str) -> str | None:
    decoder = os.environ.get("FRAMEFORGE_DECODER")
    if decoder:
        return decoder

    for env_name in decoder_env_names(codec_name):
        decoder_path = os.environ.get(env_name)
        if decoder_path:
            path = Path(decoder_path)
            if path.exists():
                return str(path)
            print(f"{env_name} does not exist: {path}", file=sys.stderr)
            return None

    return None


def configured_reference_root(codec_name: str) -> Path | None:
    for env_name in root_env_names(codec_name):
        root = os.environ.get(env_name)
        if root:
            return Path(root)
    return None


def default_reference_root(codec) -> Path:
    base = Path(os.environ.get("FRAMEFORGE_REF_DIR", codec.reference_dir))
    if codec.name == "vvc":
        return base / "vtm"
    if codec.name == "av2":
        return base / "avm"
    raise ValueError(f"unsupported codec '{codec.name}'")


def first_existing_legacy_vtm_root(codec) -> Path | None:
    for legacy in codec.legacy_reference_dirs:
        legacy_vtm = legacy / "vtm"
        if legacy_vtm.exists():
            return legacy_vtm
    return None


def decoder_names(codec_name: str) -> tuple[str, ...]:
    if codec_name == "vvc":
        return VTM_DECODER_NAMES
    if codec_name == "av2":
        return AVM_DECODER_NAMES
    raise ValueError(f"unsupported codec '{codec_name}'")


def decoder_env_names(codec_name: str) -> tuple[str, ...]:
    if codec_name == "vvc":
        return ("FRAMEFORGE_VTM_DECODER",)
    if codec_name == "av2":
        return ("FRAMEFORGE_AV2_DECODER", "FRAMEFORGE_AVM_DECODER")
    raise ValueError(f"unsupported codec '{codec_name}'")


def root_env_names(codec_name: str) -> tuple[str, ...]:
    if codec_name == "vvc":
        return ("FRAMEFORGE_VTM_ROOT",)
    if codec_name == "av2":
        return ("FRAMEFORGE_AV2_ROOT", "FRAMEFORGE_AVM_ROOT")
    raise ValueError(f"unsupported codec '{codec_name}'")


def no_decoder_message(codec_name: str) -> str:
    if codec_name == "vvc":
        return (
            "No decoder found. Set FRAMEFORGE_DECODER, FRAMEFORGE_VTM_DECODER, "
            "or FRAMEFORGE_VTM_ROOT, or run without --no-build to clone/build VTM."
        )
    if codec_name == "av2":
        return (
            "No decoder found. Set FRAMEFORGE_DECODER, FRAMEFORGE_AV2_DECODER, "
            "FRAMEFORGE_AVM_DECODER, FRAMEFORGE_AV2_ROOT, or FRAMEFORGE_AVM_ROOT, "
            "or run without --no-build to clone/build AVM."
        )
    raise ValueError(f"unsupported codec '{codec_name}'")


def clone_reference(codec_name: str, root: Path) -> None:
    if codec_name == "vvc":
        repo = os.environ.get("FRAMEFORGE_VTM_REPO", DEFAULT_VTM_REPO)
        ref = os.environ.get("FRAMEFORGE_VTM_REF")
        label = "VTM"
    elif codec_name == "av2":
        repo = os.environ.get(
            "FRAMEFORGE_AV2_REPO",
            os.environ.get("FRAMEFORGE_AVM_REPO", DEFAULT_AVM_REPO),
        )
        ref = os.environ.get("FRAMEFORGE_AV2_REF", os.environ.get("FRAMEFORGE_AVM_REF"))
        label = "AVM"
    else:
        raise ValueError(f"unsupported codec '{codec_name}'")

    root.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["git", "clone", "--depth", "1"]
    if ref:
        cmd.extend(["--branch", ref])
    cmd.extend([repo, str(root)])
    print(f"cloning {label} reference software into {root}", file=sys.stderr)
    run(cmd)


def build_reference(codec_name: str, root: Path) -> None:
    if not shutil.which("cmake"):
        raise SystemExit(f"cmake is required to build {codec_name.upper()} reference tools")

    build_dir = configured_build_dir(codec_name, root)
    build_type = configured_build_type(codec_name)
    jobs = os.environ.get("FRAMEFORGE_BUILD_JOBS")

    configure = [
        "cmake",
        "-S",
        str(root),
        "-B",
        str(build_dir),
        f"-DCMAKE_BUILD_TYPE={build_type}",
    ]
    configure.extend(configured_cmake_args(codec_name))
    build = ["cmake", "--build", str(build_dir), "--config", build_type]
    if jobs:
        build.extend(["--parallel", jobs])

    print(f"configuring {codec_name.upper()} reference in {build_dir}", file=sys.stderr)
    run(configure)
    print(f"building {codec_name.upper()} reference tools", file=sys.stderr)
    run(build)


def configured_build_dir(codec_name: str, root: Path) -> Path:
    if codec_name == "vvc":
        env_names = ("FRAMEFORGE_VTM_BUILD_DIR",)
    elif codec_name == "av2":
        env_names = ("FRAMEFORGE_AV2_BUILD_DIR", "FRAMEFORGE_AVM_BUILD_DIR")
    else:
        raise ValueError(f"unsupported codec '{codec_name}'")

    for env_name in env_names:
        if value := os.environ.get(env_name):
            return Path(value)
    return root / "build"


def configured_build_type(codec_name: str) -> str:
    if codec_name == "vvc":
        env_names = ("FRAMEFORGE_VTM_BUILD_TYPE",)
    elif codec_name == "av2":
        env_names = ("FRAMEFORGE_AV2_BUILD_TYPE", "FRAMEFORGE_AVM_BUILD_TYPE")
    else:
        raise ValueError(f"unsupported codec '{codec_name}'")

    for env_name in env_names:
        if value := os.environ.get(env_name):
            return value
    return "Release"


def configured_cmake_args(codec_name: str) -> list[str]:
    if codec_name == "vvc":
        if value := os.environ.get("FRAMEFORGE_VTM_CMAKE_ARGS"):
            return shlex.split(value)
        return []
    if codec_name == "av2":
        for env_name in ("FRAMEFORGE_AV2_CMAKE_ARGS", "FRAMEFORGE_AVM_CMAKE_ARGS"):
            if value := os.environ.get(env_name):
                return shlex.split(value)
        if not shutil.which("yasm") and not shutil.which("nasm"):
            print(
                "AVM assembler not found; configuring with -DAVM_TARGET_CPU=generic",
                file=sys.stderr,
            )
            return ["-DAVM_TARGET_CPU=generic"]
        return []
    raise ValueError(f"unsupported codec '{codec_name}'")


def find_decoder(root: Path, names: tuple[str, ...]) -> str | None:
    if not root.exists():
        return None

    for name in names:
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
