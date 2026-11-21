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

[[ -r "$LIB_DIR/launch-initialize.sh" ]] || {
    printf '[FATAL] Library missing or unreadable: %s\n' \
        "$LIB_DIR/launch-initialize.sh" >&2
    exit 1
}

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

orch_validate_file() {
    local file="$ORCHESTRATOR_PATH/$1"

    [[ -f "$file" ]] || fatal "Required file missing: $file"
    [[ -r "$file" ]] || fatal "Required file is not readable: $file"
    bash -n "$file" || fatal "Invalid Bash syntax: $file"
}

orch_load_file() {
    local file="$ORCHESTRATOR_PATH/$1"

    # shellcheck source=/dev/null
    source "$file" || fatal "Failed loading: $file"

    success "sourced: $file"
}

orch_load_components() {
    local file
    local -a files=(
        "module-runner.sh"
        "archguard-pipeline.sh"
    )

    for file in "${files[@]}"; do orch_validate_file "$file"; done
    for file in "${files[@]}"; do orch_load_file "$file"; done
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
    run_pipeline "$@"
}

main "$@"