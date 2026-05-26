#!/usr/bin/env python3
"""Install optional local open-source synthesis tools for FrameForge.

The default path installs oss-cad-suite under .tools/oss-cad-suite.  That gives
FrameForge a local Yosys/Icarus toolchain for synthesis smoke checks without
requiring proprietary EDA tools.  Vendor timing for Zynq-7000 still requires a
separate Vivado install; this script detects it but does not download it.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path


OSS_CAD_SUITE_API = "https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--prefix",
        type=Path,
        default=Path(".tools"),
        help="directory that will contain oss-cad-suite (default: .tools)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="replace an existing oss-cad-suite installation",
    )
    parser.add_argument(
        "--skip-download",
        action="store_true",
        help="only print detected tool paths and environment setup",
    )
    args = parser.parse_args()

    repo = Path.cwd()
    install_dir = args.prefix / "oss-cad-suite"

    print("FrameForge synthesis environment setup\n")
    print_detected_tools(repo, install_dir)

    if args.skip_download:
        return 0

    if install_dir.exists():
        if not args.force:
            print(f"\n[ok] Local oss-cad-suite already exists: {install_dir}")
            print_env_hint(install_dir)
            return 0
        shutil.rmtree(install_dir)

    asset_url = find_oss_cad_suite_asset()
    archive = args.prefix / "oss-cad-suite.tgz"
    args.prefix.mkdir(parents=True, exist_ok=True)

    print(f"\nDownloading oss-cad-suite:\n  {asset_url}")
    urllib.request.urlretrieve(asset_url, archive)

    print(f"Extracting {archive} into {args.prefix}")
    with tarfile.open(archive, "r:gz") as tar:
        safe_extract(tar, args.prefix)
    archive.unlink(missing_ok=True)

    if not install_dir.exists():
        candidates = sorted(args.prefix.glob("oss-cad-suite*"))
        if candidates:
            candidates[0].rename(install_dir)

    print("\nInstalled local synthesis tools.")
    print_env_hint(install_dir)
    return 0


def print_detected_tools(repo: Path, install_dir: Path) -> None:
    local_bin = install_dir / "bin"
    path = os.environ.get("PATH", "")
    search_path = f"{local_bin}{os.pathsep}{path}" if local_bin.exists() else path
    for tool in ("yosys", "yosys-config", "iverilog", "vvp", "vivado"):
        found = shutil.which(tool, path=search_path) or find_project_vivado(repo, tool)
        status = "ok" if found else "missing"
        print(f"[{status}] {tool}: {found or 'not found'}")
    settings = find_project_vivado_settings(repo)
    license_file = repo / ".tools" / "Xilinx.lic"
    if settings:
        print(f"[ok] Vivado settings: {settings}")
    else:
        print("[missing] Vivado settings: not found under .tools/Xilinx/Vivado/*/settings64.sh")
    if license_file.exists():
        print(f"[ok] Vivado license: {license_file}")
    else:
        print("[optional] Vivado license: .tools/Xilinx.lic not found")
    if not (repo / ".tools").exists():
        print("\n.tools is gitignored and intended for local downloads.")


def find_project_vivado(repo: Path, tool: str) -> str | None:
    if tool != "vivado":
        return None
    pattern = repo / ".tools" / "Xilinx" / "Vivado" / "*" / "bin" / "vivado"
    candidates = sorted(glob.glob(str(pattern)), reverse=True)
    return candidates[0] if candidates else None


def find_project_vivado_settings(repo: Path) -> Path | None:
    candidates = sorted((repo / ".tools" / "Xilinx" / "Vivado").glob("*/settings64.sh"), reverse=True)
    return candidates[0] if candidates else None


def print_env_hint(install_dir: Path) -> None:
    print("\nTo use the local toolchain in this shell:")
    print(f'  export PATH="{install_dir.resolve()}/bin:$PATH"')
    print("\nThen run:")
    print("  make synth")
    print("  make synth-postsim")


def find_oss_cad_suite_asset() -> str:
    if platform.system() != "Linux" or platform.machine() not in {"x86_64", "AMD64"}:
        raise SystemExit("Only Linux x86_64 oss-cad-suite auto-install is wired right now.")

    with urllib.request.urlopen(OSS_CAD_SUITE_API, timeout=30) as response:
        release = json.loads(response.read().decode("utf-8"))

    assets = release.get("assets", [])
    for asset in assets:
        name = asset.get("name", "")
        if "linux-x64" in name and name.endswith((".tgz", ".tar.gz")):
            return asset["browser_download_url"]

    raise SystemExit("Could not find a linux-x64 oss-cad-suite release asset.")


def safe_extract(tar: tarfile.TarFile, destination: Path) -> None:
    destination = destination.resolve()
    for member in tar.getmembers():
        target = (destination / member.name).resolve()
        if not str(target).startswith(str(destination)):
            raise SystemExit(f"Refusing unsafe archive path: {member.name}")
    tar.extractall(destination)


if __name__ == "__main__":
    raise SystemExit(main())
