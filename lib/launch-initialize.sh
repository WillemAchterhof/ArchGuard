#!/usr/bin/env bash

# ==============================================================================
#  ArchGuard Library Initialization
# ==============================================================================
#  lib/launch-initialize.sh
#
#  Bootstraps the lib layer.
#
#  Responsibilities:
#    - Verify lib components
#    - Load lib components
#
#  Constraints:
#    - Deepest layer: sources nothing, may rely on nothing.
#    - May use only raw printf/return — msg/fatal do not exist here yet.
#    - No side effects at source time; everything happens in run_initialization.
# ==============================================================================

# ==============================================================================
# Preparation
# ==============================================================================

init_validate_file() {
    local file="$LIB_DIR/$1"

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

init_load_file() {
    local file="$LIB_DIR/$1"

    # shellcheck source=/dev/null
    source "$file" || {
        printf '[FATAL] Failed loading: %s\n' "$file" >&2
        return 1
    }
}

# ==============================================================================
# Main
# ==============================================================================

init_libraries() {
    LOG_FILE="$PROJECT_DIR/ArchGuard.log"
    readonly LOG_FILE

    : > "$LOG_FILE" || {
        printf '[FATAL] Cannot create log file: %s\n' "$LOG_FILE" >&2
        return 1
    }

    local file
    local -a files=(
        "initialize-logging.sh"
        "initialize-errorhandling.sh"
    )

    for file in "${files[@]}"; do init_validate_file "$file"; done
    for file in "${files[@]}"; do init_load_file "$file"; done
}