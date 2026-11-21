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

prepare_module() {
    local module_name
    
    for module_name in "${PIPELINE_MODULES[@]}"; do
        AG_CURRENT_MODULE="$module_name"
        source_module "$module_name"

        declare -F "run_${module_name}" >/dev/null ||
            fatal "Module entry function missing: run_${module_name}"
    done
}

run_module() {
    local module_name

    for module_name in "${PIPELINE_MODULES[@]}"; do
        msg "Running module: $module_name"
        "run_${module_name}"
    done
}

run_pipeline() {
    prepare_module
    run_module
}