#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install host OS packages needed by a project-local Vivado installation.

Usage:
  scripts/install_vivado_host_deps.sh --local [--root <path>] [--version <version>]
  scripts/install_vivado_host_deps.sh --remote <ssh-host> --remote-root <path> [--version <version>]

Examples:
  sudo scripts/install_vivado_host_deps.sh --local

  scripts/install_vivado_host_deps.sh \
    --remote gabriel@192.168.50.55 \
    --remote-root /media/gabriel/Gabriel8TB/Development/frameforge

Notes:
  - This runs AMD's Vivado scripts/installLibs.sh, which installs distro packages.
  - Local mode may be run without sudo; it copies installLibs.sh to /tmp first,
    then runs the /tmp copy with sudo.
  - Remote mode uses ssh -t and sudo on the remote host, so it can prompt there.
  - The /tmp copy avoids requiring root to read SSHFS/FUSE shared-drive mounts.
  - --root is this FrameForge checkout on the current host.
  - --remote-root is this same checkout as mounted on the remote host.
EOF
}

mode=""
remote_host=""
root="$(pwd)"
remote_root=""
version="2025.2"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --local)
      mode="local"
      shift
      ;;
    --remote)
      mode="remote"
      remote_host="${2:-}"
      shift 2
      ;;
    --root)
      root="${2:-}"
      shift 2
      ;;
    --remote-root)
      remote_root="${2:-}"
      shift 2
      ;;
    --version)
      version="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$mode" ]; then
  echo "missing --local or --remote" >&2
  usage >&2
  exit 2
fi

vivado_libs_rel=".tools/Xilinx/${version}/Vivado/scripts/installLibs.sh"

run_local() {
  local checkout="$1"
  local script="${checkout}/${vivado_libs_rel}"
  local tmp_script

  if [ ! -r "$script" ]; then
    echo "Vivado installLibs.sh not found or not executable: $script" >&2
    echo "Check --root and --version, or verify the Vivado install completed." >&2
    exit 1
  fi

  tmp_script="$(mktemp /tmp/frameforge-vivado-installLibs.XXXXXX.sh)"
  cp "$script" "$tmp_script"
  chmod 755 "$tmp_script"

  echo "Running Vivado host dependency installer from a /tmp copy:"
  echo "  $script"
  echo "  $tmp_script"

  if [ "$(id -u)" -eq 0 ]; then
    "$tmp_script"
  else
    sudo "$tmp_script"
  fi
}

if [ "$mode" = "local" ]; then
  run_local "$root"
  exit 0
fi

if [ -z "$remote_host" ] || [ -z "$remote_root" ]; then
  echo "remote mode requires --remote <ssh-host> and --remote-root <path>" >&2
  usage >&2
  exit 2
fi

remote_script="${remote_root}/${vivado_libs_rel}"
echo "Running Vivado host dependency installer over SSH:"
echo "  host: $remote_host"
echo "  script: $remote_script"

ssh -t "$remote_host" "set -e; test -r '$remote_script'; tmp_script=\$(mktemp /tmp/frameforge-vivado-installLibs.XXXXXX.sh); cp '$remote_script' \"\$tmp_script\"; chmod 755 \"\$tmp_script\"; echo Running remote /tmp copy: \"\$tmp_script\"; sudo \"\$tmp_script\""
