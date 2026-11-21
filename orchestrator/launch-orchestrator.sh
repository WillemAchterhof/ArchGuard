#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
#  ArchGuard Orchestrator
# ==============================================================================
#  orchestrator/launch-orchestrator.sh
#
#  Prepares, validates, and runs the ArchGuard execution environment.
#
#  Responsibilities:
#    - Own the shell regime (options, traps)
#    - Verify and load orchestrator components
#    - Start the ArchGuard pipeline
# ==============================================================================

# ==============================================================================
# Initialization
# ==============================================================================

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly PROJECT_DIR

readonly LIB_DIR="$PROJECT_DIR/lib"
readonly ORCHESTRATOR_PATH="$PROJECT_DIR/orchestrator"

# ==============================================================================
# Load Libraries
# ==============================================================================

[[ -f "$LIB_DIR/launch-initialize.sh" &&
   -r "$LIB_DIR/launch-initialize.sh" ]] || {
    printf '[FATAL] Library missing or unreadable: %s\n' \
        "$LIB_DIR/launch-initialize.sh" >&2
    exit 1
}

# shellcheck source=lib/launch-initialize.sh
source "$LIB_DIR/launch-initialize.sh"

# ==============================================================================
# Preparation
# ==============================================================================

install_traps() {
    trap 'trap_err "$?" "$BASH_COMMAND" "$LINENO" "${BASH_LINENO[0]}"' ERR
    trap 'exit 130' INT
    trap 'exit 143' TERM

    msg "Initialized Error Handling."
}

orch_load_components() {
    lib_load_files "$ORCHESTRATOR_PATH" \
        "module-loader.sh" \
        "archguard-pipeline.sh"

    success "Orchestrator components loaded."
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    init_libraries
    msg "Libraries loaded."

    install_traps
    orch_load_components

    msg "Orchestrator ready."
    run_pipeline
}

main