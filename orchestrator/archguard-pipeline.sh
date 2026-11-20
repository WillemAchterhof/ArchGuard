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

readonly ORCH_PIPELINE_MODULES=(
    "core"
    # ... install sequence grows here
)

orch_prepare_pipeline() {
    local module_name
    for module_name in "${ORCH_PIPELINE_MODULES[@]}"; do
        orch_source_module "$module_name"
        declare -F "run_${module_name}" >/dev/null ||
            printf '[FATAL] Module entry function missing: run_%s\n' "$module_name" >&2
            return 1
    done
}

run_pipeline() {
    local module_name
    for module_name in "${ORCH_PIPELINE_MODULES[@]}"; do
        msg "Running module: $module_name"
        "run_${module_name}"
    done
}