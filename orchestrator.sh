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

source "$DIR_MAIN/modules/select-disk.sh"
source "$DIR_MAIN/modules/create-iso.sh"
source "$DIR_MAIN/modules/create-usb.sh"
source "$DIR_MAIN/modules/create-key-storage.sh"
# source "$DIR_MAIN/modules/agkeys/run.sh"
# source "$DIR_MAIN/modules/usb/run.sh"
# source "$DIR_MAIN/modules/verify/run.sh"

# ==============================================================================
# Main
# ==============================================================================

main(){
    start_sudo_keepalive
    run_selectdisk || fatal "USB disk selection cancled or failed."
    run_build_iso
    run_create_usb || fatal "USB creation failed."
    create_key_storage
    # fetch_installer
    # prepare_agboot
    # prepare_agkeys
    # create_usb
    # verify_usb

    cleanup
}

main "$@"
