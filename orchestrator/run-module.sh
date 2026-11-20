#!/usr/bin/env bash

# ==============================================================================
#  ArchGuard Module Runner
# ==============================================================================
#  orchestrator/run-module.sh
#
#  Loads an individual ArchGuard module.
#
#  Responsibilities:
#    - Locate the requested module
#    - Verify its launcher exists and is readable
#    - Validate its Bash syntax
#    - Source the module launcher
# ==============================================================================

# ==============================================================================
# Module Loader
# ==============================================================================

run_module() {
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
