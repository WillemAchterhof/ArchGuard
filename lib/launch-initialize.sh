#!/usr/bin/env bash

# ==============================================================================
#  ArchGuard Library Initialization
# ==============================================================================
#  lib/launch-initialize.sh
#
#  Bootstraps the lib layer and hosts the raw file-loading primitives.
#
#  Responsibilities:
#    - Define the shared validate/source/load primitives (raw layer)
#    - Create the log file
#    - Load lib components
#
#  Constraints:
#    - Deepest layer: sources nothing.
#    - Uses only raw printf/return, plus fatal when it is already defined
#      (lib_fail prefers fatal once the logging lib is loaded).
#    - Higher layers (orchestrator, modules) call these primitives instead of
#      re-implementing check/source logic.
#    - Expects PROJECT_DIR and LIB_DIR to be set by the entry point before
#      this is sourced.
#    - init_libraries must run exactly once (LOG_FILE is a plain global).
# ==============================================================================

# ==============================================================================
# Raw Primitives — usable before any logger exists
# ==============================================================================

# lib_fail — report and stop. Delegates to fatal when the logging lib is
# loaded (single message, logged, no ERR-trap duplicate); falls back to a
# raw stderr line before that.
lib_fail() {
    if declare -F fatal >/dev/null; then
        fatal "$1"      # exits; never falls through
    fi
    printf '[FATAL] %s\n' "$1" >&2
    return 1
}

lib_check_file() {
    local file="$1"

    [[ -f "$file" ]] ||
        { lib_fail "Required file missing: $file"; return 1; }

    [[ -r "$file" ]] ||
        { lib_fail "Required file is not readable: $file"; return 1; }

    bash -n "$file" ||
        { lib_fail "Invalid Bash syntax: $file"; return 1; }
}

lib_source_file() {
    local file="$1"

    # shellcheck source=/dev/null
    source "$file" || {
        lib_fail "Failed loading: $file"
        return 1
    }
}

# lib_load_files DIR FILE...
# Validates every file first, then sources every file.
lib_load_files() {
    local dir="$1"
    shift

    local file

    # Validate all files before sourcing any.
    for file in "$@"; do
        lib_check_file "$dir/$file"
    done

    # Source files only after all validations pass.
    for file in "$@"; do
        lib_source_file "$dir/$file"
    done
}

# ==============================================================================
# Main
# ==============================================================================

init_libraries() {
    declare -g LOG_FILE="$PROJECT_DIR/ArchGuard.log"

    : > "$LOG_FILE" || {
        printf '[FATAL] Cannot create log file: %s\n' "$LOG_FILE" >&2
        return 1
    }

    lib_load_files "$LIB_DIR" \
        "initialize-logging.sh" \
        "initialize-errorhandling.sh"
}