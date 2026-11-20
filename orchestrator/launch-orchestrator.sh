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
# Validation
# ==============================================================================

validate_file() {
    local file="$1"

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

validate_environment() {
    validate_file "$ORCHESTRATOR_PATH/run-module.sh"
    validate_file "$ORCHESTRATOR_PATH/archguard-modules.sh"
    validate_file "$ORCHESTRATOR_PATH/archguard-pipeline.sh"
}

# ==============================================================================
# Load Orchestrator
# ==============================================================================

load_file() {
    local file="$1"

    # shellcheck source=/dev/null
    source "$ORCHESTRATOR_PATH/$file" || {
        printf '[FATAL] Failed loading %s\n' "$file" >&2
        return 1
    }
}

load_orchestrator() {
    load_file "run-module.sh"
    load_file "archguard-modules.sh"
    load_file "archguard-pipeline.sh"
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    validate_environment
    load_orchestrator
    run_pipeline "$@"
}

main "$@"
