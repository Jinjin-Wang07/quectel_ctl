#!/usr/bin/env bash
set -euo pipefail

## Setup helper for SCAT in this repository.
## - Creates a local Python virtual environment
## - Installs SCAT from ./scat in editable mode
## - Fails immediately on any error (no fallback paths)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAT_DIR="${ROOT_DIR}/scat"
VENV_DIR="${SCAT_VENV_DIR:-${ROOT_DIR}/.venv-scat}"

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

check_python_version() {
  python3 - <<'PY'
import sys

if sys.version_info < (3, 10):
    print("Python 3.10+ is required.")
    raise SystemExit(1)
PY
}

install_venv_support_if_missing() {
  local probe_dir
  probe_dir="$(mktemp -d)"

  if python3 -m venv "${probe_dir}/probe" >/dev/null 2>&1; then
    rm -rf "${probe_dir}"
    return 0
  fi

  rm -rf "${probe_dir}"
  echo "[INFO] python venv support is missing. Installing venv package..."

  if ! command -v apt-get >/dev/null 2>&1; then
    die "python venv support is missing and apt-get is unavailable. Install python3-venv manually."
  fi

  local py_mm pkg
  py_mm="$(python3 - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
  pkg="python${py_mm}-venv"

  if [[ "$(id -u)" -eq 0 ]]; then
    apt-get update
    if apt-cache show "${pkg}" >/dev/null 2>&1; then
      apt-get install -y "${pkg}"
    else
      apt-get install -y python3-venv
    fi
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    if apt-cache show "${pkg}" >/dev/null 2>&1; then
      sudo apt-get install -y "${pkg}"
    else
      sudo apt-get install -y python3-venv
    fi
  else
    die "Need elevated privileges to install venv package. Re-run as root or install python3-venv manually."
  fi
}

install_tshark_if_missing() {
  if command -v tshark >/dev/null 2>&1; then
    return 0
  fi

  echo "[INFO] tshark is missing. Installing tshark..."

  if ! command -v apt-get >/dev/null 2>&1; then
    die "tshark is missing and apt-get is unavailable. Install tshark manually."
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y tshark
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tshark
  else
    die "Need elevated privileges to install tshark. Re-run as root or install tshark manually."
  fi
}

echo "[1/6] Checking prerequisites..."
require_cmd python3
check_python_version

if [[ ! -d "${SCAT_DIR}" ]]; then
  die "SCAT directory not found: ${SCAT_DIR}"
fi

echo "[2/6] Creating virtual environment..."
install_venv_support_if_missing
python3 -m venv "${VENV_DIR}"

# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

echo "[3/6] Upgrading pip tooling in venv..."
python -m pip install --upgrade pip setuptools wheel

echo "[4/6] Installing SCAT (editable mode)..."
python -m pip install -e "${SCAT_DIR}[fastcrc]"

echo "[5/6] Ensuring tshark is available..."
install_tshark_if_missing

echo "[6/6] Verifying installation..."
python - <<'PY'
import scat.main
print("SCAT Python module import: OK")
PY

echo "Setup complete."
echo "- SCAT source   : ${SCAT_DIR}"
echo "- Venv location : ${VENV_DIR}"
echo
echo "Next step:"
echo "source ${VENV_DIR}/bin/activate && scat --help"
