#!/usr/bin/env bash

# ==============================================================================
#  ArchGuard Module Runner
# ==============================================================================
#  orchestrator/module-loader.sh
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

load_module() {
    [[ $# -eq 1 ]] || fatal "load_module expects exactly one argument"

    local module_name="$1"
    local module_dir="$PROJECT_DIR/modules/$module_name"
    local module_file="$module_dir/launch-$module_name.sh"

    [[ "$module_name" =~ ^[a-zA-Z0-9_-]+$ ]] ||
        fatal "Invalid module name: $module_name"

    [[ -d "$module_dir" ]] ||
        fatal "Module directory missing: $module_dir"

    if declare -F "run_${module_name}" >/dev/null; then
        fatal "Module entry name already in use: run_${module_name}"
    fi

    lib_check_file "$module_file"
    lib_source_file "$module_file"

    declare -F "run_${module_name}" >/dev/null ||
        fatal "Module entry function missing after loading: run_${module_name}"

    success "Sourced: $module_file"
}