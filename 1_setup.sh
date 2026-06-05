#!/usr/bin/env bash
set -euo pipefail

## Build helper for this repository.
## - Builds quectel_QCom and quectel_qlog
## - Intended for Ubuntu 24.04 host or the provided Ubuntu 24.04 container

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/2] Building quectel_QCom..."
make -C "${ROOT_DIR}/quectel_QCom"

echo "[2/2] Building quectel_qlog..."
make -C "${ROOT_DIR}/quectel_qlog"

echo "Build complete."
echo "- QCom binaries: ${ROOT_DIR}/quectel_QCom/out"
echo "- QLog binary : ${ROOT_DIR}/quectel_qlog/out/QLog"
echo "- Restart helper: ${ROOT_DIR}/quectel_QCom/scripts/restart-modem.sh"

echo "Build complete."