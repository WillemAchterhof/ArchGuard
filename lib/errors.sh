
#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Errors
# ==============================================================================
# /lib/errors.sh

# ==============================================================================
# FATAL ERROR
# ==============================================================================

fatal()
{
    local message="${1:-Unknown error}"

    trap - ERR

    printf '[FATAL] %s\n' "$message" >&2

    exit 1
}

# ==============================================================================
# ERROR TRAP
# ==============================================================================

trap_err()
{
    local exit_code=$?

    trap - ERR

    printf '[FATAL] Command failed (exit %s).\n' \
        "$exit_code" >&2

    exit "$exit_code"
}

# ==============================================================================
# INTERRUPT TRAP
# ==============================================================================

trap_int()
{
    local signal="${1:-INT}"

    trap - INT TERM

    case "$signal" in
        TERM)
            printf '\n[!] Installation terminated.\n' >&2
            exit 143
            ;;
        *)
            printf '\n[!] Installation interrupted.\n' >&2
            exit 130
            ;;
    esac
}
