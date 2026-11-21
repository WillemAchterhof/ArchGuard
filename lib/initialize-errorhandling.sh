trap_err() {
    trap - ERR

    local exit_code=$1
    local failing_command=${2:-unknown}
    local line=${3:-unknown}
    local call_line=${4:-unknown}
    local file="${BASH_SOURCE[1]:-unknown}"
    local caller_file="${BASH_SOURCE[2]:-unknown}"
    local caller_func="${FUNCNAME[2]:-main}"
    local module="${AG_CURRENT_MODULE:-none}"

    local error_type=""

    if (( exit_code == 127 )); then
        error_type="'${failing_command%% *}' not found"
    elif (( exit_code == 126 )); then
        error_type="'${failing_command%% *}' not executable"
    fi

    local message="[FATAL] Error
    Module  : ${module}
    File    : ${file##*/}:${line}
    Command : ${error_type:-${failing_command}}
    Caller  : ${caller_func} - ${caller_file##*/}:${call_line}
    Exit    : ${exit_code}"

    { printf '%s\n' "$message" >> "$LOG_FILE"; } 2>/dev/null || true
    printf '%s\n' "$message" >&2

    exit "$exit_code"
}