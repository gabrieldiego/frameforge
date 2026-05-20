#!/usr/bin/env python3
"""Check FrameForge development tools and suggest Ubuntu install commands."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Tool:
    name: str
    command: str
    required_for: str
    ubuntu: str
    required: bool = True
    version_args: tuple[str, ...] = ("--version",)
    alternate_paths: tuple[str, ...] = ()


TOOLS = (
    Tool(
        name="Git",
        command="git",
        required_for="source checkout and external VTM clone",
        ubuntu="sudo apt update && sudo apt install -y git",
    ),
    Tool(
        name="Rust cargo",
        command="cargo",
        required_for="Rust build and tests",
        ubuntu="curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh",
    ),
    Tool(
        name="rustup",
        command="rustup",
        required_for="Rust toolchain component management",
        ubuntu="curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh",
    ),
    Tool(
        name="rustfmt",
        command="rustfmt",
        required_for="Rust formatting",
        ubuntu="rustup component add rustfmt",
    ),
    Tool(
        name="Python 3",
        command="python3",
        required_for="helper scripts and cocotb tests",
        ubuntu="sudo apt update && sudo apt install -y python3 python3-venv python3-pip",
        version_args=("--version",),
    ),
    Tool(
        name="CMake",
        command="cmake",
        required_for="building the external VTM reference decoder",
        ubuntu="sudo apt update && sudo apt install -y cmake",
    ),
    Tool(
        name="C++ compiler",
        command="c++",
        required_for="building the external VTM reference decoder",
        ubuntu="sudo apt update && sudo apt install -y build-essential",
    ),
    Tool(
        name="Icarus Verilog",
        command="iverilog",
        required_for="default open-source RTL simulator",
        ubuntu="sudo apt update && sudo apt install -y iverilog",
        required=False,
        version_args=("-V",),
    ),
    Tool(
        name="cocotb",
        command="cocotb-config",
        required_for="Python RTL verification",
        ubuntu=(
            "sudo apt update && sudo apt install -y python3-venv python3-pip\n"
            "  python3 -m venv .venv\n"
            "  . .venv/bin/activate\n"
            "  python -m pip install -U pip\n"
            "  python -m pip install -r requirements-dev.txt"
        ),
        required=False,
        alternate_paths=(".venv/bin/cocotb-config",),
    ),
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--strict",
        action="store_true",
        help="return non-zero if optional RTL tools are missing too",
    )
    args = parser.parse_args()

    missing_required: list[Tool] = []
    missing_optional: list[Tool] = []

    print("FrameForge development environment check\n")

    for tool in TOOLS:
        path = find_tool(tool)
        if path:
            version = read_version(path, tool.version_args)
            print(f"[ok]      {tool.name}: {path}{version}")
            continue

        bucket = missing_required if tool.required else missing_optional
        bucket.append(tool)
        level = "missing" if tool.required else "optional"
        print(f"[{level}] {tool.name}: needed for {tool.required_for}")

    print_install_help("Required tools", missing_required)
    print_install_help("Optional tools", missing_optional)

    if missing_required or (args.strict and missing_optional):
        return 1
    return 0


def read_version(command: str, args: tuple[str, ...]) -> str:
    try:
        completed = subprocess.run(
            [command, *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception:
        return ""

    text = (completed.stdout or completed.stderr).strip().splitlines()
    return f" ({text[0]})" if text else ""


def find_tool(tool: Tool) -> str | None:
    path = shutil.which(tool.command)
    if path:
        return path

    for alternate in tool.alternate_paths:
        candidate = Path(alternate)
        if candidate.exists():
            return str(candidate)
    return None


def print_install_help(title: str, tools: list[Tool]) -> None:
    if not tools:
        return

    print(f"\n{title} missing. Ubuntu setup suggestions:")
    seen: set[str] = set()
    for tool in tools:
        if tool.ubuntu in seen:
            continue
        seen.add(tool.ubuntu)
        for line in tool.ubuntu.splitlines():
            print(f"  {line}")


if __name__ == "__main__":
    raise SystemExit(main())
