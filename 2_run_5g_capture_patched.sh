#!/usr/bin/env bash
set -euo pipefail

# Simple end-to-end helper:
# 1. Check required modem device nodes.
# 2. Send ATI to AT port and verify response contains "quectel".
# 3. Start QLog and QCom (quectel-cm-test) in their own folders.
#
# This script intentionally uses short sleep points so users can follow each step.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Require sudo/root so device and service operations do not fail later.
if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Please run this script with sudo (for example: sudo ./2_run_5g_capture.sh)" >&2
    exit 1
fi

# Modem device defaults (can be overridden with environment variables).
AT_PORT="${AT_PORT:-/dev/ttyUSB2}"
QMI_DEV="${QMI_DEV:-/dev/cdc-wdm0}"
DIAG_PORT="${DIAG_PORT:-/dev/ttyUSB0}"

# Project directories.
QLOG_DIR="${ROOT_DIR}/quectel_qlog"
QCOM_DIR="${ROOT_DIR}/quectel_QCom"

# Required binaries and config files.
QLOG_BIN="${QLOG_DIR}/out/QLog"
QCOM_BIN="${QCOM_DIR}/out/quectel-cm-test"
QLOG_CFG="${QLOG_DIR}/conf/defaultNR5G1216.cfg"
QCOM_CFG="${QCOM_DIR}/configs/qcm-5g.conf"
QLOG_SAVE_DIR="${ROOT_DIR}/output"

STEP_SLEEP="${STEP_SLEEP:-2}"
STOP_MODEMMANAGER="${STOP_MODEMMANAGER:-1}"
MODEM_RESET_BEFORE_RUN="${MODEM_RESET_BEFORE_RUN:-1}"
MODEM_RESET_WAIT_SEC="${MODEM_RESET_WAIT_SEC:-8}"
PING_IFACE="${PING_IFACE:-wwan0}"
PING_TARGET="${PING_TARGET:-8.8.8.8}"
PING_COUNT="${PING_COUNT:-4}"
PING_START_DELAY_SEC="${PING_START_DELAY_SEC:-10}"

# Script requires root privileges, so no sudo prefix is needed.
SUDO=""

# Print an error and stop immediately.
error_exit() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Sleep between steps so users can follow progress.
pause_step() {
    sleep "${STEP_SLEEP}"
}

# Restore original serial settings when AT probing is done.
cleanup_stty() {
    if [[ -n "${OLD_STTY:-}" ]]; then
        stty -F "${AT_PORT}" "${OLD_STTY}" 2>/dev/null || true
    fi
}

# Stop ModemManager to avoid conflicts on cdc-wdm after USB reconnect.
stop_modemmanager_if_needed() {
    if [[ "${STOP_MODEMMANAGER}" != "1" ]]; then
        return 0
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        return 0
    fi

    if systemctl is-active --quiet ModemManager; then
        echo "[INFO] ModemManager is active; stopping it to avoid QMI conflicts..."
        ${SUDO} systemctl stop ModemManager || error_exit "Failed to stop ModemManager"
        # Give systemd a moment to tear down qmi-proxy users.
        sleep 1
    fi
}

# Send a best-effort AT command and collect lines until OK/ERROR or timeout.
run_at_command() {
    local cmd="$1"
    local timeout_sec="${2:-5}"
    local response=""
    local deadline

    exec 3<>"${AT_PORT}" || error_exit "Failed to open ${AT_PORT}"
    printf '%s\r' "${cmd}" >&3 || { exec 3>&- 3<&-; cleanup_stty; error_exit "Failed to write ${cmd} to ${AT_PORT}"; }

    deadline=$((SECONDS + timeout_sec))
    while (( SECONDS < deadline )); do
        if IFS= read -r -t 0.5 line <&3; then
            response+="${line}"$'\n'
            [[ "${line}" == "OK" || "${line}" == "ERROR" ]] && break
        fi
    done

    exec 3>&-
    exec 3<&-
    printf '%s' "${response}"
}

# Soft reset radio stack to recover from unstable state after cable replug.
reset_modem_if_needed() {
    local reset_response=""

    if [[ "${MODEM_RESET_BEFORE_RUN}" != "1" ]]; then
        return 0
    fi

    echo "[INFO] Resetting modem radio stack (AT+CFUN=0/1) before capture..."
    OLD_STTY="$(stty -F "${AT_PORT}" -g 2>/dev/null || true)"
    stty -F "${AT_PORT}" 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts raw -echo min 0 time 5 2>/dev/null || true

    reset_response="$(run_at_command 'AT+CFUN=0' 5 || true)"
    if ! printf '%s' "${reset_response}" | grep -qi "OK"; then
        cleanup_stty
        error_exit "AT+CFUN=0 failed on ${AT_PORT}. Response: ${reset_response//$'\n'/ ; }"
    fi

    sleep 2

    reset_response="$(run_at_command 'AT+CFUN=1' 5 || true)"
    cleanup_stty
    if ! printf '%s' "${reset_response}" | grep -qi "OK"; then
        error_exit "AT+CFUN=1 failed on ${AT_PORT}. Response: ${reset_response//$'\n'/ ; }"
    fi

    sleep "${MODEM_RESET_WAIT_SEC}"
}

# Step 1: verify AT and QMI device nodes exist.
echo "[1/7] Checking modem device nodes..."
[[ -e "${AT_PORT}" ]] || error_exit "AT device not found: ${AT_PORT}"
[[ -e "${QMI_DEV}" ]] || error_exit "QMI device not found: ${QMI_DEV}"
echo "[OK] Found ${AT_PORT} and ${QMI_DEV}"
pause_step

stop_modemmanager_if_needed
reset_modem_if_needed

# Step 2: verify build outputs and configs are available.
echo "[2/7] Checking required binaries and configs..."
[[ -e "${QLOG_BIN}" ]] || error_exit "QLog binary not found: ${QLOG_BIN}. Run ./1_setup.sh first."
[[ -e "${QCOM_BIN}" ]] || error_exit "QCom binary not found: ${QCOM_BIN}. Run ./1_setup.sh first."
[[ -e "${QLOG_CFG}" ]] || error_exit "QLog config not found: ${QLOG_CFG}"
[[ -e "${QCOM_CFG}" ]] || error_exit "QCom config not found: ${QCOM_CFG}"
echo "[OK] Required files are present"
pause_step

# Step 3 pre-check: ensure the AT port is accessible for read/write.
[[ -r "${AT_PORT}" && -w "${AT_PORT}" ]] || error_exit "No read/write access on ${AT_PORT}. Run with sudo."

# Step 3: send ATI command and confirm the modem identity contains "quectel".
echo "[3/7] Sending ATI on ${AT_PORT} and checking modem identity..."

# Configure serial, send ATI, and read a short response window.
OLD_STTY="$(stty -F "${AT_PORT}" -g 2>/dev/null || true)"
stty -F "${AT_PORT}" 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts raw -echo min 0 time 5 2>/dev/null || true

# Open the AT device, send ATI, and capture response lines for a few seconds.
ATI_RESPONSE=""
exec 3<>"${AT_PORT}" || error_exit "Failed to open ${AT_PORT}"
printf 'ATI\r' >&3 || { exec 3>&- 3<&-; cleanup_stty; error_exit "Failed to write ATI to ${AT_PORT}"; }

DEADLINE=$((SECONDS + 5))
while (( SECONDS < DEADLINE )); do
    if IFS= read -r -t 0.5 line <&3; then
        ATI_RESPONSE+="${line}"$'\n'
        [[ "${line}" == "OK" ]] && break
    fi
done

exec 3>&-
exec 3<&-
cleanup_stty

# Fail if ATI response does not include the expected vendor string.
if ! printf '%s' "${ATI_RESPONSE}" | grep -qi "quectel"; then
    error_exit "ATI check failed. Expected 'quectel' in modem response on ${AT_PORT}."
fi

echo "[OK] Modem available"
pause_step

# Step 4: check SIM status and stop if SIM is absent.
echo "[4/7] Checking SIM status on ${AT_PORT}..."

OLD_STTY="$(stty -F "${AT_PORT}" -g 2>/dev/null || true)"
stty -F "${AT_PORT}" 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts raw -echo min 0 time 5 2>/dev/null || true

SIM_RESPONSE=""
exec 3<>"${AT_PORT}" || error_exit "Failed to open ${AT_PORT}"
printf 'AT+CPIN?\r' >&3 || { exec 3>&- 3<&-; cleanup_stty; error_exit "Failed to write AT+CPIN? to ${AT_PORT}"; }

DEADLINE=$((SECONDS + 5))
while (( SECONDS < DEADLINE )); do
    if IFS= read -r -t 0.5 line <&3; then
        SIM_RESPONSE+="${line}"$'\n'
        [[ "${line}" == "OK" ]] && break
    fi
done

exec 3>&-
exec 3<&-
cleanup_stty

if printf '%s' "${SIM_RESPONSE}" | grep -Eqi "(NOT INSERTED|SIM NOT INSERTED|\+CME ERROR)"; then
    echo "[WARN] SIM is absent. Please insert the SIM card."
    error_exit "SIM absent. Please insert the SIM card, then run this script again."
fi

if ! printf '%s' "${SIM_RESPONSE}" | grep -qi "\+CPIN: READY"; then
    error_exit "Unable to confirm SIM ready state. AT+CPIN? response was: ${SIM_RESPONSE//$'\n'/ ; }"
fi

echo "[OK] SIM is ready"
pause_step

# Step 4.5: configure modem network preferences before QLog/QCom starts.
echo "[4.5/7] Configuring RM520 network preferences..."

OLD_STTY="$(stty -F "${AT_PORT}" -g 2>/dev/null || true)"
stty -F "${AT_PORT}" 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts raw -echo min 0 time 5 2>/dev/null || true

send_at_expect_ok() {
    local cmd="$1"
    local timeout_sec="${2:-8}"
    local resp=""

    echo "[AT] ${cmd}"
    resp="$(run_at_command "${cmd}" "${timeout_sec}" || true)"
    printf '%s\n' "${resp}"

    if ! printf '%s' "${resp}" | grep -qi "OK"; then
        cleanup_stty
        error_exit "AT command failed: ${cmd}. Response: ${resp//$'\n'/ ; }"
    fi
}

# Allow roaming. Required for SIM 234-10 on PLMN 226-30.
send_at_expect_ok 'AT+QNWPREFCFG="roam_pref",255' 8

# Print current status before starting quectel-cm.
echo "[AT] AT+QNWPREFCFG=\"roam_pref\""
run_at_command 'AT+QNWPREFCFG="roam_pref"' 5 || true
run_at_command 'AT+QNWPREFCFG="mode_pref"' 5 || true
run_at_command 'AT+COPS?' 5 || true
run_at_command 'AT+C5GREG?' 5 || true
run_at_command 'AT+QENG="servingcell"' 5 || true

cleanup_stty
pause_step

# Ensure QLog output directory exists.
mkdir -p "${QLOG_SAVE_DIR}"
QLOG_STDOUT_LOG="${QLOG_SAVE_DIR}/qlog_$(date +%Y%m%d_%H%M%S).log"

QLOG_PID=""
# Stop background QLog when this script exits or is interrupted.
cleanup() {
    if [[ -n "${QLOG_PID}" ]] && kill -0 "${QLOG_PID}" >/dev/null 2>&1; then
        echo "Stopping QLog (pid ${QLOG_PID})..."
        kill -INT "${QLOG_PID}" >/dev/null 2>&1 || true
        wait "${QLOG_PID}" || true
    fi
}
trap cleanup EXIT INT TERM

# Step 5: start QLog in its own project directory.
echo "[5/7] Starting QLog from ${QLOG_DIR}..."
(
    cd "${QLOG_DIR}"
    ${SUDO} ./out/QLog -p "${DIAG_PORT}" -s "${QLOG_SAVE_DIR}" -f "${QLOG_CFG}" -m 200 -n 20 >"${QLOG_STDOUT_LOG}" 2>&1
) &
QLOG_PID=$!
echo "[OK] QLog started (pid ${QLOG_PID}), log: ${QLOG_STDOUT_LOG}"
pause_step

# Step 6: run QCom test tool in its own project directory.
echo "[6/7] Starting QCom from ${QCOM_DIR}..."
pause_step
(
    cd "${QCOM_DIR}"
    ${SUDO} ./out/quectel-cm-test -q -c ./configs/qcm-5g.conf
) &
QCOM_PID=$!
echo "[OK] QCom started (pid ${QCOM_PID})"

# Step 7: verify data connectivity after QCom has had time to bring up data.
echo "[7/7] Waiting ${PING_START_DELAY_SEC}s, then testing connectivity with ping..."
sleep "${PING_START_DELAY_SEC}"

PING_LOG="${QLOG_SAVE_DIR}/ping_$(date +%Y%m%d_%H%M%S).log"
if ping -I "${PING_IFACE}" -c "${PING_COUNT}" -W 2 "${PING_TARGET}" >"${PING_LOG}" 2>&1; then
    PING_STATS_LINE="$(grep -E "packets transmitted|packet loss" "${PING_LOG}" | tail -n1 || true)"
    PING_RTT_LINE="$(grep -E "rtt min/avg/max|round-trip min/avg/max" "${PING_LOG}" | tail -n1 || true)"
    echo "[OK] Connectivity test PASSED on ${PING_IFACE} -> ${PING_TARGET}"
    [[ -n "${PING_STATS_LINE}" ]] && echo "[INFO] ${PING_STATS_LINE}"
    [[ -n "${PING_RTT_LINE}" ]] && echo "[INFO] ${PING_RTT_LINE}"
else
    PING_STATS_LINE="$(grep -E "packets transmitted|packet loss" "${PING_LOG}" | tail -n1 || true)"
    echo "[ERROR] Connectivity test FAILED on ${PING_IFACE} -> ${PING_TARGET}. See ${PING_LOG}"
    [[ -n "${PING_STATS_LINE}" ]] && echo "[INFO] ${PING_STATS_LINE}"
fi

wait "${QCOM_PID}"
