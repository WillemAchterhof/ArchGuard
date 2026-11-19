#!/usr/bin/env bash
# ArchGuard USB Builder - Base Configuration Editor
# /menu/base-edit.sh

base_load_config() {
    local config_path

    if [[ -z "${BASE_AGBOOT_ROOT:-}" ]]; then
        msg "AGBOOT is not mounted."
        return 1
    fi

    config_path="$BASE_AGBOOT_ROOT/$BASE_CONFIG_DIR/$BASE_CONFIG_FILE"

    if [[ ! -f "$config_path" ]]; then
        msg "Base Configuration file not found: $config_path"
        return 1
    fi

    # Clear previous values before loading the current file.
    unset BASE_ENV_FILESYSTEM
    unset BASE_ENV_EFI_SIZE
    unset BASE_ENV_LUKS
    unset BASE_ENV_SWAP_ENABLED
    unset BASE_ENV_SWAP_SIZE
    unset BASE_ENV_HOSTNAME
    unset BASE_ENV_USERNAME
    unset BASE_ENV_LOCALE
    unset BASE_ENV_TIMEZONE
    unset BASE_ENV_KEYBOARD
    unset BASE_ENV_MIRROR_COUNTRIES
    unset BASE_ENV_PACMAN_PARALLEL

    if ! source "$config_path"; then
        msg "Failed to load Base Configuration."
        return 1
    fi

    return 0
}

base_edit_config() {
    local config_file="$1"
    local config_path

    if [[ -z "${BASE_AGBOOT_ROOT:-}" ]]; then
        msg "AGBOOT is not mounted."
        return 1
    fi

    # Only allow known configuration files to be edited.
    case "$config_file" in
        "$BASE_CONFIG_FILE"|"$BASE_BTRFS_FILE")
            ;;
        *)
            msg "Unknown configuration file: $config_file"
            return 1
            ;;
    esac

    config_path="$BASE_AGBOOT_ROOT/$BASE_CONFIG_DIR/$config_file"

    if [[ ! -f "$config_path" ]]; then
        msg "Configuration file not found: $config_path"
        return 1
    fi

    if ! command -v sudoedit >/dev/null 2>&1; then
        msg "sudoedit is not available."
        return 1
    fi

    sudoedit -- "$config_path"
}

base_save_config() {
    if [[ -z "${BASE_AGBOOT_ROOT:-}" ]]; then
        msg "AGBOOT is not mounted."
        return 1
    fi

    if [[ ! -f "$BASE_AGBOOT_ROOT/$BASE_CONFIG_DIR/$BASE_CONFIG_FILE" ]]; then
        msg "Base Configuration file not found."
        return 1
    fi

    if ! sync; then
        msg "Unable to synchronize configuration changes."
        return 1
    fi

    if ! base_load_config; then
        msg "Configuration could not be reloaded. Check the file for errors."
        return 1
    fi

    if ! validate_base_config; then
        msg "Base Configuration contains invalid settings. Please correct them."
        return 1
    fi

    success "Base Configuration saved and validated."
    return 0
}
