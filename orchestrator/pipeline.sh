#!/usr/bin/env bash

# ==============================================================================
# ArchGuard Installer — Main Pipeline
# ==============================================================================
# orchestrator/pipeline.sh

run_pipeline() {

    log_header "ARCHGUARD INSTALLER"

    msg "Select installation USB"
    run_module "$AG_DIR_MODULES/select-usb/launch-select-usb.sh"

    msg "Detect hardware"
    run_module "$AG_DIR_MODULES/hardware-detection/launch-hardware-detection.sh"

    msg "Prepare installation"
    run_module "$AG_DIR_MODULES/prepare-installation/launch-prepare-installation.sh"

    while true; do

        msg "Configure installation profile"
        run_module "$AG_DIR_MODULES/configure-profile/launch-configure-profile.sh"

        [[ "$AG_MENU_EXIT" == "1" ]] && {
            msg "Installer exited."
            exit 0
        }

        msg "Validate configuration"
        run_module "$AG_DIR_MODULES/validate-profile/launch-validate-profile.sh"

        [[ "$AG_MENU_PROCEED" == "1" ]] && break

    done

    msg "Install system"
    run_module "$AG_DIR_MODULES/installation/launch-installation.sh"

    msg "Prepare post-installation"
    run_module "$AG_DIR_MODULES/post-installation/launch-post-installation.sh"

    log_header "INSTALLATION COMPLETE"

    reboot_to_uefi
}
