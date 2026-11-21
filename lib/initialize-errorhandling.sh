#!/usr/bin/env bash

# ==============================================================================
#  ArchGuard Error Handling
# ==============================================================================
#  lib/initialize-errorhandling.sh
#
#  ERR trap handler — reports the failing command, file, and module.
#
#  Constraints:
#    - Defines trap_err; does NOT install it. The entry point installs traps.
#    - AG_CURRENT_MODULE protocol: run_pipeline sets it before each module
#      invocation and clears it after, so error reports name the module.
# ==============================================================================

trap_err() {
    local exit_code=$?
    local failing_command="${BASH_COMMAND:-unknown}"
    local line="${BASH_LINENO[0]:-unknown}"
    local caller_line="${1:-unknown}"
    local file="${BASH_SOURCE[1]:-unknown}"
    local module="${AG_CURRENT_MODULE:-none}"

    local error_type=""

    if (( exit_code == 127 )); then
        error_type="Command : '${failing_command%% *}' not found"
    elif (( exit_code == 126 )); then
        error_type="Command : '${failing_command%% *}' not executable"
    fi

    local message="[FATAL] Error
    Module  : ${module}
    File    : ${file##*/}: ${line}:${caller_line}
    ${error_type:-Command: ${failing_command}}
    Exit    : ${exit_code}"

    printf '%s\n' "$message" >> "$LOG_FILE"
    printf '%s\n' "$message" >&2

    exit "$exit_code"
}