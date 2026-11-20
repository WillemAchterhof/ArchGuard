
#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# ArchGuard Orchestrator
# ==============================================================================
# /orchestrator/launch-orchestrator.sh
#
# Responsible for launching modules in the required execution order.
# Modules manage their own dependencies, initialization and cleanup.
# ==============================================================================

# ==============================================================================
# Initialization
# ==============================================================================

init_variables() {
    readonly DIR_PROJECT="${DIR_PROJECT:?DIR_PROJECT is not set}"
    readonly DIR_MODULES="$DIR_PROJECT/modules"
}

# ==============================================================================
# Module Execution
# ==============================================================================

run_module() {
    local module_launcher=$1
    local launcher_path="$DIR_PROJECT/$module_launcher"

    [[ -f "$launcher_path" ]] ||
        {
            printf '[FATAL] Module launcher not found: %s\n' \
                "$launcher_path" >&2
            return 1
        }

    bash "$launcher_path"
}

# ==============================================================================
# Pipeline
# ==============================================================================

main() {
    init_variables

    run_module "modules/storage/launch-select-storage.sh"
}

main "$@"
