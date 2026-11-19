#!/usr/bin/env bash
# ArchGuard USB Builder - Software Configuration Menu
# /menu/software-run.sh

readonly SOFTWARE_CONFIG_FILE="config-software.env"

software_configuration_menu() {
    local choice

    if ! base_mount_agboot; then
        msg "Unable to access AGBOOT configuration storage."
        return 1
    fi

    while true; do
        if ! software_load_config; then
            msg "Unable to load Software Configuration."
            base_unmount_agboot
            return 1
        fi

        clear
        echo "========================================"
        echo "        Software Configuration"
        echo "========================================"
        echo
        echo " PACKAGE GROUPS"
        echo "----------------------------------------"
        echo "ArchGuard Base:      ${#ARCHGUARD_BASE[@]} packages"
        echo "System Support:      ${#SYSTEM_SUPPORT[@]} packages"
        echo "KDE Plasma:          ${#PLASMA[@]} packages"
        echo "KVM / QEMU:          ${#KVM_PACKAGES[@]} packages"
        echo "Extra Applications:  ${#EXTRA_PACKAGES[@]} packages"
        echo
        echo "========================================"
        echo "  1) Change Software Settings"
        echo
        echo "  s) Save Configuration"
        echo "  q) Return to Main Menu"
        echo "========================================"
        echo

        if ! IFS= read -r -p "Select an option: " choice; then
            base_unmount_agboot
            return 0
        fi

        case "$choice" in
            1)
                software_edit_config
                ;;
            s|S)
                software_save_config
                read -r -p "Press Enter to continue..." _
                ;;
            q|Q)
                base_unmount_agboot
                return 0
                ;;
            *)
                continue
                ;;
        esac
    done
}
