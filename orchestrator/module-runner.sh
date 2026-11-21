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

load_module() {
    local module_name="$1"
    local module_dir="$PROJECT_DIR/modules/$module_name"
    local module_file="$module_dir/launch-$module_name.sh"

    [[ -d "$module_dir" ]] || {
        fatal "Module directory missing: $module_dir" 
        return 1
    }

    [[ -f "$module_file" ]] || {
         fatal "Module launcher missing: $module_file" 
        return 1
    }

    [[ -r "$module_file" ]] || {
         fatal "Module launcher not readable: $module_file" 
        return 1
    }

    bash -n "$module_file" || {
         fatal "Invalid Bash syntax: $module_file" 
        return 1
    }

    # shellcheck source=/dev/null
    source "$module_file" || {
         fatal "Failed loading module: $module_name" 
        return 1
    }

    success "sourced: $module_file"
}

run_module() {
    local module_name="$1"
    local entry="run_$module_name"

    declare -F "$entry" >/dev/null &&
        fatal "Module entry name already in use: $entry"

    load_module "$module_name"

    declare -F "$entry" >/dev/null ||
        fatal "Module entry function missing: $entry"

    msg "Starting $module_name"
    "$entry"
    success "Finished $module_name"
}