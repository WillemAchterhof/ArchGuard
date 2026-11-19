#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# Initialization
# ==============================================================================
# /bootstrap/archguard-install.sh

DIR_BOOTSTRAP="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

DIR_LIB="$DIR_BOOTSTRAP/lib"
DIR_MODULES="$DIR_BOOTSTRAP/modules"

# ==============================================================================
# Libraries
# ==============================================================================

source "$DIR_LIB/bootstrap-logging.sh"
source "$DIR_LIB/bootstrap-common.sh"
source "$DIR_LIB/bootstrap-errors.sh"

# ==============================================================================
# Error Handling
# ==============================================================================

trap 'bootstrap_trap_err' ERR
trap 'bootstrap_trap_int' INT TERM

# ==============================================================================
# Modules
# ==============================================================================

source "$DIR_MODULES/bootstrap-init.sh"
source "$DIR_MODULES/bootstrap-network.sh"
source "$DIR_MODULES/bootstrap-wifi.sh"
source "$DIR_MODULES/bootstrap-packages.sh"
source "$DIR_MODULES/bootstrap-repository.sh"
source "$DIR_MODULES/bootstrap-authentication.sh"
source "$DIR_MODULES/bootstrap-handoff.sh"

# ==============================================================================
# Main
# ==============================================================================

main() {
    printf "[Success] The bootstrap ArchGuard Installe loaded succesfully."
}

main "$@"
