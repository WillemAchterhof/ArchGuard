#!/usr/bin/env bash

# ==============================================================================
#  ArchGuard Logging
# ==============================================================================
#  lib/initialize-logging.sh
#
#  Message output — to screen and to $LOG_FILE.
#
#  Constraints:
#    - Sourced lib: defines only; no set/trap/source-time side effects.
#    - msg/success → stdout; warn/fatal → stderr. Everything → $LOG_FILE.
# ==============================================================================

_log_emit() {
    local stream=$1
    local message=$2

    printf '%s\n' "$message" >&"$stream"
    { printf '%s\n' "$message" >> "$LOG_FILE"; } 2>/dev/null || true
}

msg()     { _log_emit 1 "[*] $*"; }
success() { _log_emit 1 "[+] $*"; }
warn()    { _log_emit 2 "[!] $*"; }
log_only() { { printf '%s\n' "$1" >> "$LOG_FILE"; } 2>/dev/null || true; }

fatal() {
    _log_emit 2 "[FATAL] $*"
    exit 1
}