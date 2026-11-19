#!/usr/bin/env bash

# ==============================================================================
# ArchGuard Installer — Module Runner
# ==============================================================================
# orchestrator/run-module.sh

run_module() {
    local module_launcher="$1"
    local module_name

    [[ -f "$module_launcher" ]] \
        || fatal "Module launcher not found: $module_launcher"

    module_name="$(basename "$(dirname "$module_launcher")")"

    log_header "MODULE START: $module_name"

    AG_CURRENT_MODULE="$module_name"
    export AG_CURRENT_MODULE

    source "$module_launcher"

    log_header "MODULE COMPLETE: $module_name"
}
