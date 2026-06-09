#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${ROOT_DIR}/output"
DEFAULT_LOG_DIR_0="${OUTPUT_DIR}"
DEFAULT_LOG_DIR_1="${ROOT_DIR}/quectel_qlog/log"
DEFAULT_LOG_DIR_2="${ROOT_DIR}/quectel_qlog/out/logs"

usage() {
  echo "Usage: $0 [qmdl2-log-dir] [scat-lua-path]"
  echo "- qmdl2-log-dir defaults to output, then quectel_qlog/log, then quectel_qlog/out/logs"
  echo "- scat-lua-path defaults to ./scat/wireshark/scat.lua"
}

LOG_DIR="${1:-}"
SCAT_LUA="${2:-${ROOT_DIR}/scat/wireshark/scat.lua}"

if [[ "${LOG_DIR}" == "-h" || "${LOG_DIR}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "${LOG_DIR}" ]]; then
  if [[ -d "${DEFAULT_LOG_DIR_0}" ]]; then
    LOG_DIR="${DEFAULT_LOG_DIR_0}"
  elif [[ -d "${DEFAULT_LOG_DIR_1}" ]]; then
    LOG_DIR="${DEFAULT_LOG_DIR_1}"
  elif [[ -d "${DEFAULT_LOG_DIR_2}" ]]; then
    LOG_DIR="${DEFAULT_LOG_DIR_2}"
  else
    echo "[ERROR] Could not find default QLog directory."
    echo "Tried:"
    echo "- ${DEFAULT_LOG_DIR_0}"
    echo "- ${DEFAULT_LOG_DIR_1}"
    echo "- ${DEFAULT_LOG_DIR_2}"
    echo
    usage
    exit 1
  fi
fi

if [[ ! -d "$LOG_DIR" ]]; then
  echo "[ERROR] QLog directory not found: $LOG_DIR"
  exit 1
fi

if [[ ! -f "$SCAT_LUA" ]]; then
  echo "[ERROR] Lua plugin not found: $SCAT_LUA"
  exit 1
fi

if ! command -v tshark >/dev/null 2>&1; then
  echo "[ERROR] tshark not found in PATH"
  exit 1
fi

if ! command -v scat >/dev/null 2>&1; then
  echo "[ERROR] scat command not found."
  echo "SCAT environment is not ready."
  echo "Run these commands first:"
  echo "  ./3_setup_scat.sh"
  echo "  source .venv-scat/bin/activate"
  exit 1
fi

if [[ -z "${VIRTUAL_ENV:-}" ]]; then
  echo "[ERROR] Python virtual environment is not active."
  echo "Activate SCAT venv first:"
  echo "  source .venv-scat/bin/activate"
  exit 1
fi

check_pcap_rrc() {
  local pcap_file="$1"

  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  trap 'rm -f "$tmp_out" "$tmp_err"' RETURN

  # Decode packets with SCAT Lua dissector and check the Info column text.
  tshark -r "$pcap_file" -X "lua_script:$SCAT_LUA" -T fields -e _ws.col.Info >"$tmp_out" 2>"$tmp_err" || true

  # If the plugin is already globally loaded, retry without -X to avoid duplicate Proto warning.
  if grep -qi 'there cannot be two protocols with the same description' "$tmp_err"; then
    : >"$tmp_err"
    tshark -r "$pcap_file" -T fields -e _ws.col.Info >"$tmp_out" 2>"$tmp_err" || true
  fi

  if [[ -s "$tmp_err" ]]; then
    echo "[INFO] tshark stderr (first 10 lines):"
    head -n 10 "$tmp_err"
  fi

  local setup_re recfg_re
  setup_re='RRCSetp|RRCSetup|RRC[[:space:]_-]*Setup|rrcConnectionSetup'
  recfg_re='RRCReconfiguration|RRC[[:space:]_-]*Reconfiguration|rrcConnectionReconfiguration'

  local has_setup=0
  local has_recfg=0

  grep -Eiq "$setup_re" "$tmp_out" && has_setup=1
  grep -Eiq "$recfg_re" "$tmp_out" && has_recfg=1

  if [[ $has_setup -eq 1 && $has_recfg -eq 1 ]]; then
    echo "[OK] $(basename "$pcap_file"): found both RRC Setup and RRC Reconfiguration"
    return 0
  fi

  echo "[FAIL] $(basename "$pcap_file"): missing expected RRC messages"
  echo "- RRC Setup found          : $has_setup"
  echo "- RRC Reconfiguration found: $has_recfg"
  return 1
}

mkdir -p "$OUTPUT_DIR"

echo "[1/3] Finding qmdl2 logs from: $LOG_DIR"
mapfile -t QMDL_FILES < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.qmdl2' | sort)

if [[ ${#QMDL_FILES[@]} -eq 0 ]]; then
  echo "[ERROR] No .qmdl2 files found in: $LOG_DIR"
  exit 1
fi

echo "[2/3] Parsing qmdl2 files to pcap in: $OUTPUT_DIR"
for src in "${QMDL_FILES[@]}"; do
  base_name="$(basename "$src")"
  pcap_out="${OUTPUT_DIR}/${base_name%.qmdl2}.pcap"
  scat_log="${OUTPUT_DIR}/${base_name%.qmdl2}.scat.log"

  echo "[INFO] Parsing $base_name -> $(basename "$pcap_out")"
  if scat -t qc -d "$src" -F "$pcap_out" >"$scat_log" 2>&1; then
    echo "[OK] Parsed $(basename "$pcap_out")"
  else
    echo "[FAIL] SCAT parse failed for $base_name"
    echo "[INFO] Check log: $scat_log"
    tail -n 10 "$scat_log" || true
    exit 1
  fi
done

echo "[3/3] Checking parsed pcap for RRC Setup/Reconfiguration"
FAIL_COUNT=0

for src in "${QMDL_FILES[@]}"; do
  base_name="$(basename "$src")"
  pcap_out="${OUTPUT_DIR}/${base_name%.qmdl2}.pcap"

  if [[ ! -s "$pcap_out" ]]; then
    echo "[FAIL] $(basename "$pcap_out"): file missing or empty"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  if ! check_pcap_rrc "$pcap_out"; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "[DONE] All parsed pcap files passed RRC checks."
  exit 0
fi

echo "[DONE] Completed with failures: $FAIL_COUNT"
exit 2