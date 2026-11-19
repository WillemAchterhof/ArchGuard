#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# ArchGuard Installer — Main Orchestrator
# ==============================================================================
# orchestrator/orchestrator-launch.sh

# ==============================================================================
# Initialization
# ==============================================================================

readonly AG_DIR_MAIN="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly AG_DIR_ORCHESTRATOR="$AG_DIR_MAIN/orchestrator"

# ==============================================================================
# Core
# ==============================================================================

init_core() {
    source "$AG_DIR_MAIN/install/lib/core/variables/module.sh" \
        || { printf '[FATAL] Failed loading core variables.\n' >&2; exit 1; }

    source "$AG_DIR_LOGGING/module.sh" \
        || { printf '[FATAL] Failed loading logging.\n' >&2; exit 1; }

    source "$AG_DIR_ERRORS/module.sh" \
        || { printf '[FATAL] Failed loading error handling.\n' >&2; exit 1; }

    init_logging
}

# ==============================================================================
# Orchestrator
# ==============================================================================

init_orchestrator() {
    source "$AG_DIR_ORCHESTRATOR/run-module.sh" \
        || fatal "Failed loading module runner."

    source "$AG_DIR_ORCHESTRATOR/pipeline.sh" \
        || fatal "Failed loading installation pipeline."
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    init_core

    trap 'trap_err "$LINENO"' ERR

    init_orchestrator

    run_pipeline "$@"
}

main "$@"
