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

trap_err(){
    local exit_code=$?

    fatal "Command failed: $BASH_COMMAND (exit $exit_code)"
}