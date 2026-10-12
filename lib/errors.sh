
#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Errors
# ==============================================================================
# /lib/errors.sh

fatal() {
    local message="${1:-Unknown error}"

    trap - ERR

    printf '[FATAL] %s\n' "$message" >&2

    cleanup || true
    exit 1
}

trap_err() {
    local exit_code=$?

    trap - ERR

    printf '[FATAL] Command failed (exit %s).\n' "$exit_code" >&2

    cleanup || true
    exit "$exit_code"
}
