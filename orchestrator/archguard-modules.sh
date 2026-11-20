#!/usr/bin/env bash

# ==============================================================================
#  ArchGuard Modules
# ==============================================================================
#  orchestrator/archguard-modules.sh
#
#  Defines the entry points for ArchGuard modules.
#
#  Responsibilities:
#    - Load individual modules through run_module
#    - Call the corresponding module entry functions
# ==============================================================================

# ==============================================================================
# Module Entry Points
# ==============================================================================

module_test() {
    run_module "test"
    run_test
}
