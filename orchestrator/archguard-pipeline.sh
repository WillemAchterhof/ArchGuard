#!/usr/bin/env bash

# ==============================================================================
#  ArchGuard Pipeline
# ==============================================================================
#  orchestrator/archguard-pipeline.sh
#
#  Defines the execution sequence of the ArchGuard installer.
#
#  Responsibilities:
#    - Define the execution order of installer modules
#    - Control progression through the installation stages
# ==============================================================================

# ==============================================================================
# Pipeline
# ==============================================================================

readonly PIPELINE_MODULES=(
    "test"
    # ... install sequence grows here
)

load_pipeline_modules() {
    local module_name
    
    for module_name in "${PIPELINE_MODULES[@]}"; do
        load_module "$module_name"

        declare -F "run_${module_name}" >/dev/null ||
            fatal "Module entry function missing: run_${module_name}"
    done
}

run_pipeline_modules() {
    local module_name

    for module_name in "${PIPELINE_MODULES[@]}"; do
        AG_CURRENT_MODULE="$module_name"

        msg "Running module: $module_name"
        "run_${module_name}"
        success "Finished module: $module_name"
    done

    unset AG_CURRENT_MODULE
}

run_pipeline() {
    load_pipeline_modules
    run_pipeline_modules
}