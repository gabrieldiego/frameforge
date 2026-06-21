#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installer=""
license=""
force_extract=0
force_auth=0
skip_auth=0
skip_install=0

usage() {
  cat <<'EOF'
Usage:
  ./install-vivado-local.sh --installer /path/to/FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1114_2157_Lin64.bin [options]

Options:
  --license PATH       Copy a Xilinx.lic file into .tools/Xilinx.lic.
  --force-extract     Replace an existing .tools/vivado-installer extraction.
  --force-auth        Run xsetup AuthTokenGen even if a local token exists.
  --skip-auth         Do not run xsetup AuthTokenGen.
  --skip-install      Prepare/configure/extract only; do not run xsetup Install.
  -h, --help          Show this help.

All Vivado installer state is redirected under this checkout's .tools/ tree:
  .tools/Xilinx              Vivado install destination
  .tools/vivado-installer    extracted AMD installer
  .tools/tmp                 temporary files
  .tools/home                HOME for xsetup
  .tools/xdg-*               XDG cache/config/data/state
  .tools/Xilinx.lic          optional local license copy

When bubblewrap is available, the AMD installer runs with / mounted read-only
and this checkout's .tools/ as the writable install/cache area.
EOF
}

while (($#)); do
  case "$1" in
    --installer)
      installer="${2:-}"
      shift 2
      ;;
    --license)
      license="${2:-}"
      shift 2
      ;;
    --force-extract)
      force_extract=1
      shift
      ;;
    --force-auth)
      force_auth=1
      shift
      ;;
    --skip-auth)
      skip_auth=1
      shift
      ;;
    --skip-install)
      skip_install=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$installer" ]]; then
  echo "Missing required --installer PATH" >&2
  usage >&2
  exit 2
fi

if [[ ! -r "$installer" ]]; then
  echo "Installer is not readable: $installer" >&2
  exit 2
fi

if [[ -n "$license" && ! -r "$license" ]]; then
  echo "License is not readable: $license" >&2
  exit 2
fi

mkdir -p \
  "$root/.tools/Xilinx" \
  "$root/.tools/tmp" \
  "$root/.tools/home" \
  "$root/.tools/xdg-cache" \
  "$root/.tools/xdg-config" \
  "$root/.tools/xdg-data" \
  "$root/.tools/xdg-state" \
  "$root/.tools/xdg-runtime"
chmod 700 "$root/.tools/xdg-runtime"

export HOME="$root/.tools/home"
export TMPDIR="$root/.tools/tmp"
export TMP="$root/.tools/tmp"
export TEMP="$root/.tools/tmp"
export XDG_CACHE_HOME="$root/.tools/xdg-cache"
export XDG_CONFIG_HOME="$root/.tools/xdg-config"
export XDG_DATA_HOME="$root/.tools/xdg-data"
export XDG_STATE_HOME="$root/.tools/xdg-state"
export XDG_RUNTIME_DIR="$root/.tools/xdg-runtime"
export XILINXD_LICENSE_FILE="$root/.tools/Xilinx.lic"

echo "FrameForge Vivado local install"
echo "  checkout:    $root"
echo "  root fs:     $(df -h / | awk 'NR == 2 {print $4 " free on " $1}')"
echo "  project fs:  $(df -h "$root" | awk 'NR == 2 {print $4 " free on " $1}')"
echo "  HOME:        $HOME"
echo "  TMPDIR:      $TMPDIR"
echo "  destination: $root/.tools/Xilinx"

prepare_args=(prepare)
if [[ -n "$license" ]]; then
  prepare_args+=(--license "$license")
fi

python3 "$root/scripts/setup_vivado.py" "${prepare_args[@]}"
python3 "$root/scripts/setup_vivado.py" config

extract_args=(extract --installer "$installer")
if ((force_extract)); then
  extract_args+=(--force)
fi
python3 "$root/scripts/setup_vivado.py" "${extract_args[@]}"

if [[ -f "$root/.tools/home/.Xilinx/wi_authentication_key" && "$force_auth" -eq 0 ]]; then
  echo "Existing project-local AMD auth token found; skipping AuthTokenGen."
  skip_auth=1
fi

if ((!skip_auth)); then
  python3 "$root/scripts/setup_vivado.py" auth
fi

if ((!skip_install)); then
  python3 "$root/scripts/setup_vivado.py" install --log .tools/vivado-install-run.log
fi

echo "Vivado local install flow finished."
echo "Run 'make synth-check' to confirm the project-local Vivado detection."
