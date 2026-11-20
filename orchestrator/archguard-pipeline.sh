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

run_pipeline() {
    run_module "test"
    run_module "broken"
}
