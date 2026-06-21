#!/usr/bin/env python3
"""Prepare and run a project-local AMD Vivado installer flow.

This script intentionally keeps downloaded payloads, installer state, and
license files under .tools/, which is gitignored.  It does not store AMD account
credentials.
"""

from __future__ import annotations

import argparse
import os
import pwd
import shutil
import subprocess
from pathlib import Path


DEFAULT_TEMPLATE = Path("synth/vivado/install_config.template")
DEFAULT_CONFIG = Path(".tools/vivado-install_config.txt")
DEFAULT_INSTALLER_DIR = Path(".tools/vivado-installer")
DEFAULT_TOOLS_DIR = Path(".tools")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare = subparsers.add_parser("prepare", help="create .tools directories and optional ~/.Xilinx symlink")
    prepare.add_argument("--root", type=Path, default=Path.cwd(), help="FrameForge checkout root")
    prepare.add_argument("--license", type=Path, help="optional Xilinx.lic file to copy into .tools")
    prepare.add_argument("--link-home-cache", action="store_true", help="symlink ~/.Xilinx to .tools/home-Xilinx")

    config = subparsers.add_parser("config", help="write a machine-local Vivado install config")
    config.add_argument("--root", type=Path, default=Path.cwd(), help="FrameForge checkout root")
    config.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    config.add_argument("--output", type=Path, default=DEFAULT_CONFIG)

    extract = subparsers.add_parser("extract", help="extract the AMD web installer into .tools/vivado-installer")
    extract.add_argument("--root", type=Path, default=Path.cwd(), help="FrameForge checkout root")
    extract.add_argument("--installer", type=Path, required=True, help="AMD FPGAs/Adaptive SoCs .bin installer")
    extract.add_argument("--force", action="store_true", help="replace an existing extracted installer")

    auth = subparsers.add_parser("auth", help="run xsetup AuthTokenGen")
    auth.add_argument("--root", type=Path, default=Path.cwd(), help="FrameForge checkout root")

    install = subparsers.add_parser("install", help="run xsetup batch install")
    install.add_argument("--root", type=Path, default=Path.cwd(), help="FrameForge checkout root")
    install.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    install.add_argument("--log", type=Path, help="optional log file path")

    args = parser.parse_args()
    root = args.root.resolve()

    if args.command == "prepare":
        prepare_tree(root, args.license, args.link_home_cache)
        return 0
    if args.command == "config":
        write_config(root, args.template, args.output)
        return 0
    if args.command == "extract":
        extract_installer(root, args.installer, args.force)
        return 0
    if args.command == "auth":
        return run_xsetup(root, ["-b", "AuthTokenGen"])
    if args.command == "install":
        command = [
            "-a",
            "XilinxEULA,3rdPartyEULA",
            "-b",
            "Install",
            "-c",
            str((root / args.config).resolve() if not args.config.is_absolute() else args.config),
        ]
        return run_xsetup(root, command, args.log)

    raise AssertionError(args.command)


def prepare_tree(root: Path, license_file: Path | None, link_home_cache: bool) -> None:
    tools = root / DEFAULT_TOOLS_DIR
    for path in (
        tools,
        tools / "Xilinx",
        tools / "tmp",
        tools / "home",
        tools / "home" / ".Xilinx",
        tools / "home-Xilinx",
        tools / "xdg-cache",
        tools / "xdg-config",
        tools / "xdg-data",
        tools / "xdg-state",
        tools / "vivado-install-logs",
    ):
        path.mkdir(parents=True, exist_ok=True)

    if license_file:
        target = tools / "Xilinx.lic"
        shutil.copy2(license_file, target)
        print(f"Copied license to {target}")

    if link_home_cache:
        target = tools / "home-Xilinx"
        link = Path.home() / ".Xilinx"
        if link.exists() and not link.is_symlink():
            backup = tools / f"home-Xilinx.backup"
            if backup.exists():
                raise SystemExit(f"Refusing to overwrite existing backup: {backup}")
            link.rename(backup)
            print(f"Moved existing {link} to {backup}")
        link.unlink(missing_ok=True)
        link.symlink_to(target)
        print(f"Linked {link} -> {target}")

    print("Vivado local state:")
    print(f"  install destination: {tools / 'Xilinx'}")
    print(f"  installer extraction: {root / DEFAULT_INSTALLER_DIR}")
    print(f"  temporary files:      {tools / 'tmp'}")
    print(f"  project HOME:         {tools / 'home'}")
    print(f"  XDG cache/config:     {tools / 'xdg-cache'} / {tools / 'xdg-config'}")


def write_config(root: Path, template: Path, output: Path) -> None:
    template_path = template if template.is_absolute() else root / template
    output_path = output if output.is_absolute() else root / output
    destination = root / ".tools" / "Xilinx"
    text = template_path.read_text().replace("{DESTINATION}", str(destination))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text)
    print(f"Wrote Vivado install config: {output_path}")
    print(f"Install destination: {destination}")


def extract_installer(root: Path, installer: Path, force: bool) -> None:
    installer_dir = root / DEFAULT_INSTALLER_DIR
    if installer_dir.exists():
        if not force:
            print(f"Installer already extracted: {installer_dir}")
            return
        shutil.rmtree(installer_dir)
    installer_dir.parent.mkdir(parents=True, exist_ok=True)
    command = ["sh", str(installer), "--noexec", "--target", str(installer_dir)]
    subprocess.run(
        bubblewrap_command(root, command),
        check=True,
        cwd=root,
        env=project_local_env(root),
    )
    print(f"Extracted installer to {installer_dir}")


def project_local_env(root: Path) -> dict[str, str]:
    tools = root / DEFAULT_TOOLS_DIR
    home = tools / "home"
    tmp = tools / "tmp"
    xdg_cache = tools / "xdg-cache"
    xdg_config = tools / "xdg-config"
    xdg_data = tools / "xdg-data"
    xdg_state = tools / "xdg-state"
    xdg_runtime = tools / "xdg-runtime"

    for path in (
        tools,
        home,
        home / ".Xilinx",
        tmp,
        xdg_cache,
        xdg_config,
        xdg_data,
        xdg_state,
        xdg_runtime,
    ):
        path.mkdir(parents=True, exist_ok=True)

    xdg_runtime.chmod(0o700)

    env = os.environ.copy()
    env["HOME"] = str(home)
    env["TMPDIR"] = str(tmp)
    env["TMP"] = str(tmp)
    env["TEMP"] = str(tmp)
    env["XDG_CACHE_HOME"] = str(xdg_cache)
    env["XDG_CONFIG_HOME"] = str(xdg_config)
    env["XDG_DATA_HOME"] = str(xdg_data)
    env["XDG_STATE_HOME"] = str(xdg_state)
    env["XDG_RUNTIME_DIR"] = str(xdg_runtime)
    env["XILINXD_LICENSE_FILE"] = str(tools / "Xilinx.lic")
    java_home_arg = f"-Duser.home={home}"
    existing_java_options = env.get("_JAVA_OPTIONS", "")
    if java_home_arg not in existing_java_options:
        env["_JAVA_OPTIONS"] = f"{existing_java_options} {java_home_arg}".strip()
    return env


def bubblewrap_command(root: Path, command: list[str], isolate_passwd_home: bool = False) -> list[str]:
    """Run vendor installer commands with only .tools writable when possible."""
    if os.environ.get("FRAMEFORGE_VIVADO_NO_BWRAP") == "1":
        print("Vivado installer isolation: disabled by FRAMEFORGE_VIVADO_NO_BWRAP=1")
        return command

    bwrap = shutil.which("bwrap") or shutil.which("bubblewrap")
    if not bwrap:
        print("Vivado installer isolation: bubblewrap not found; using environment-only isolation")
        return command

    tools = root / DEFAULT_TOOLS_DIR
    home = tools / "home"
    tmp = tools / "tmp"
    xdg_runtime = tools / "xdg-runtime"
    for path in (tools, home, home / ".Xilinx", tmp, xdg_runtime):
        path.mkdir(parents=True, exist_ok=True)
    xdg_runtime.chmod(0o700)

    print("Vivado installer isolation: bubblewrap read-only / with writable .tools")
    wrapped = [
        bwrap,
        "--die-with-parent",
        "--ro-bind",
        "/",
        "/",
        "--dev-bind",
        "/dev",
        "/dev",
        "--proc",
        "/proc",
        "--bind",
        str(tools),
        str(tools),
        "--bind",
        str(tmp),
        "/tmp",
        "--bind",
        str(tmp),
        "/var/tmp",
    ]
    if isolate_passwd_home:
        real_home = Path(pwd.getpwuid(os.getuid()).pw_dir)
        if real_home != home and real_home.exists():
            print(f"Vivado installer isolation: overlaying passwd home {real_home} with {home}")
            wrapped.extend(["--bind", str(home), str(real_home)])
    wrapped.extend(["--chdir", str(root), *command])
    return wrapped


def run_xsetup(root: Path, args: list[str], log: Path | None = None) -> int:
    xsetup = root / DEFAULT_INSTALLER_DIR / "xsetup"
    if not xsetup.exists():
        raise SystemExit(f"xsetup not found: {xsetup}. Run `scripts/setup_vivado.py extract` first.")

    env = project_local_env(root)

    command = bubblewrap_command(root, [str(xsetup), *args], isolate_passwd_home=True)
    if log:
        log_path = log if log.is_absolute() else root / log
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("w") as log_file:
            completed = subprocess.run(command, cwd=root, env=env, stdout=log_file, stderr=subprocess.STDOUT)
        print(f"xsetup log: {log_path}")
        return completed.returncode

    return subprocess.run(command, cwd=root, env=env).returncode


if __name__ == "__main__":
    raise SystemExit(main())
