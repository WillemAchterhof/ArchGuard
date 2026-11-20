#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
#  ArchGuard Orchestrator
# ==============================================================================
#  orchestrator/launch-orchestrator.sh
#
#  Prepares and validates the ArchGuard execution environment.
#
#  Responsibilities:
#    - Verify orchestrator components
#    - Load orchestrator components
#    - Start the ArchGuard pipeline
# ==============================================================================

# ==============================================================================
# Initialization
# ==============================================================================

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly PROJECT_DIR
readonly ORCHESTRATOR_PATH="$PROJECT_DIR/orchestrator"

# ==============================================================================
# Preparation
# ==============================================================================

validate_file() {
    local file="$ORCHESTRATOR_PATH/$1"

    [[ -f "$file" ]] || {
        printf '[FATAL] Required file missing: %s\n' "$file" >&2
        return 1
    }

    [[ -r "$file" ]] || {
        printf '[FATAL] Required file is not readable: %s\n' "$file" >&2
        return 1
    }

    bash -n "$file" || {
        printf '[FATAL] Invalid Bash syntax: %s\n' "$file" >&2
        return 1
    }
}

load_file() {
    local file="$ORCHESTRATOR_PATH/$1"

    # shellcheck source=/dev/null
    source "$file" || {
        printf '[FATAL] Failed loading: %s\n' "$file" >&2
        return 1
    }
}

prepare_environment() {
    local file
    local -a files=(
        "launch-module.sh"
        "archguard-pipeline.sh"
    )

    for file in "${files[@]}"; do validate_file "$file"; done
    for file in "${files[@]}"; do load_file "$file"; done
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    prepare_environment
    run_pipeline "$@"
}

main "$@"
