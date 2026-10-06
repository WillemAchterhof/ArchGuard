#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
#  ArchGuard USB Builder - Orchestrator
# ==============================================================================
# /orchestrator.sh

# ==============================================================================
# Initialization
# ==============================================================================

DIR_MAIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Global Libraries
# ==============================================================================

source "$DIR_MAIN/lib/logging.sh"
source "$DIR_MAIN/lib/common.sh"
source "$DIR_MAIN/lib/errors.sh"

trap 'trap_err' ERR

# ==============================================================================
# Modules
# ==============================================================================

source "$DIR_MAIN/modules/selectdisk.sh"
# source "$DIR_MAIN/modules/iso/run.sh"
# source "$DIR_MAIN/modules/installer/run.sh"
# source "$DIR_MAIN/modules/agboot/run.sh"
# source "$DIR_MAIN/modules/agkeys/run.sh"
# source "$DIR_MAIN/modules/usb/run.sh"
# source "$DIR_MAIN/modules/verify/run.sh"

# ==============================================================================
# Main
# ==============================================================================

main(){
    run_selectdisk || fatal "USB disk selection failed."

    # build_iso
    # fetch_installer
    # prepare_agboot
    # prepare_agkeys
    # create_usb
    # verify_usb

    cleanup
}

main "$@"