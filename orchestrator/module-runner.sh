#!/usr/bin/env bash

# ==============================================================================
#  ArchGuard Module Runner
# ==============================================================================
#  orchestrator/module-runner.sh
#
#  Loads an individual ArchGuard module.
#
#  Responsibilities:
#    - Locate the requested module
#    - Verify its launcher exists and is readable
#    - Validate its Bash syntax
#    - Source the module launcher
#    - Run the module launcher
# ==============================================================================

# ==============================================================================
# Module Loader
# ==============================================================================

source_module() {
    local module_name="$1"
    local module_dir="$PROJECT_DIR/modules/$module_name"
    local module_file="$module_dir/launch-$module_name.sh"

    [[ -d "$module_dir" ]] || {
        printf '[FATAL] Module directory missing: %s\n' "$module_dir" >&2
        return 1
    }

    [[ -f "$module_file" ]] || {
        printf '[FATAL] Module launcher missing: %s\n' "$module_file" >&2
        return 1
    }

    [[ -r "$module_file" ]] || {
        printf '[FATAL] Module launcher not readable: %s\n' "$module_file" >&2
        return 1
    }

    bash -n "$module_file" || {
        printf '[FATAL] Invalid Bash syntax: %s\n' "$module_file" >&2
        return 1
    }

    # shellcheck source=/dev/null
    source "$module_file" || {
        printf '[FATAL] Failed loading module: %s\n' "$module_name" >&2
        return 1
    }
}

run_module() {
    local module_name="$1"
    local entry="run_$module_name"

    if declare -F "$entry" >/dev/null; then
        printf '[FATAL] Module entry name already in use: %s\n' "$entry" >&2
        return 1
    fi

    source_module "$module_name" || return 1

    declare -F "$entry" >/dev/null || {
        printf '[FATAL] Module entry function missing: %s\n' "$entry" >&2
        return 1
    }

    "$entry"
}
