
#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# ArchGuard USB Builder - Orchestrator
# ==============================================================================
# /orchestrator.sh

# ==============================================================================
# Initialization
# ==============================================================================

DIR_MAIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DIR_LIB="$DIR_MAIN/lib"
DIR_MODULES="$DIR_MAIN/modules"

# Global state
AG_P_DISK=""

# ==============================================================================
# Global Libraries
# ==============================================================================

source "$DIR_LIB/logging.sh"
source "$DIR_LIB/common.sh"
source "$DIR_LIB/storage-detection.sh"
source "$DIR_LIB/errors.sh"

# ==============================================================================
# Error Handling
# ==============================================================================

trap 'trap_err' ERR
trap 'trap_int INT' INT
trap 'trap_int TERM' TERM
trap 'cleanup' EXIT

# ==============================================================================
# Modules
# ==============================================================================

source "$DIR_MODULES/select-disk.sh"

# ==============================================================================
# Main
# ==============================================================================


main()
{
    # Detect available storage devices.
    if ! detect_storage; then
        fatal "Storage detection failed. Cannot safely continue."
    fi

    # Select installation disk.
    if ! run_disk; then
        printf "\n Installation cancelled. Returning to Arch live environment.\n"
        return 0
    fi

    msg "Installation target: $AG_P_DISK"

    # Continue installation...
}

main "$@"
