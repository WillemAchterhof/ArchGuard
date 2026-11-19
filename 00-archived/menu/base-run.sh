#!/usr/bin/env bash
# ArchGuard USB Builder - Base Configuration Menu
# /menu/base-run.sh

readonly BASE_CONFIG_DIR="config-files"
readonly BASE_CONFIG_FILE="config-base.env"
readonly BASE_BTRFS_FILE="config-btrfs.env"

base_configuration_menu() {
    local choice

    # Mount AGBOOT before accessing its configuration files.
    if ! base_mount_agboot; then
        msg "Unable to access AGBOOT configuration storage."
        return 1
    fi

    while true; do
        # Load the current configuration from AGBOOT.
        if ! base_load_config; then
            msg "Unable to load Base Configuration."
            base_unmount_agboot
            return 1
        fi

        clear
        echo "========================================"
        echo "          Base Configuration"
        echo "========================================"
        echo
        echo " STORAGE"
        echo "----------------------------------------"
        echo "Filesystem:          ${BASE_ENV_FILESYSTEM:-Not configured}"
        echo "EFI partition:       ${BASE_ENV_EFI_SIZE:-Not configured}"
        echo "LUKS:                ${BASE_ENV_LUKS:-Not configured}"
        echo "Swap:                ${BASE_ENV_SWAP_ENABLED:-Not configured}"
        echo
        echo " SYSTEM"
        echo "----------------------------------------"
        echo "Hostname:            ${BASE_ENV_HOSTNAME:-Not configured}"
        echo "Username:            ${BASE_ENV_USERNAME:-Not configured}"
        echo "Locale:              ${BASE_ENV_LOCALE:-Not configured}"
        echo "Timezone:            ${BASE_ENV_TIMEZONE:-Not configured}"
        echo "Keyboard:            ${BASE_ENV_KEYBOARD:-Not configured}"
        echo
        echo " NETWORK / PACMAN"
        echo "----------------------------------------"
        echo "Mirror countries:    ${BASE_ENV_MIRROR_COUNTRIES:-Not configured}"
        echo "Parallel downloads:  ${BASE_ENV_PACMAN_PARALLEL:-Not configured}"
        echo
        echo "========================================"
        echo "  1) Change Base Settings"

        if [[ "${BASE_ENV_FILESYSTEM:-}" == "btrfs" ]]; then
            echo "  2) Btrfs Configuration"
        fi

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
                base_edit_config "$BASE_CONFIG_FILE"
                ;;
            2)
                if [[ "${BASE_ENV_FILESYSTEM:-}" == "btrfs" ]]; then
                    base_edit_config "$BASE_BTRFS_FILE"
                fi
                ;;
            s|S)
                if base_save_config; then
                    msg "Base Configuration saved successfully."
                fi
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
