#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Errors
# ==============================================================================
# /lib/errors.sh

fatal(){
    local message="$1"

    printf '[FATAL] %s\n' "$message"

    cleanup || true

    exit 1
}

trap_int(){
    # Ignore further signals while cleaning up.
    trap '' INT TERM

    # Ctrl+C during a silent prompt (read -s) can leave echo disabled.
    stty echo 2>/dev/null || true

    printf '\n'
    msg "Interrupted. Cleaning up..."

    cleanup || true

    exit 130
}

trap_err(){
    local exit_code=$?

    fatal "Command failed: $BASH_COMMAND (exit $exit_code)"
}