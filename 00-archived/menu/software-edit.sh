#!/usr/bin/env bash
# ArchGuard USB Builder - Software Configuration Editor
# /menu/software-edit.sh

software_load_config() {
    local config_path

    if [[ -z "${BASE_AGBOOT_ROOT:-}" ]]; then
        msg "AGBOOT is not mounted."
        return 1
    fi

    config_path="$BASE_AGBOOT_ROOT/$BASE_CONFIG_DIR/$SOFTWARE_CONFIG_FILE"

    if [[ ! -f "$config_path" ]]; then
        msg "Software Configuration file not found: $config_path"
        return 1
    fi

    unset ARCHGUARD_BASE
    unset SYSTEM_SUPPORT
    unset PLASMA
    unset KVM_PACKAGES
    unset EXTRA_PACKAGES

    if ! source "$config_path"; then
        msg "Failed to load Software Configuration."
        return 1
    fi

    return 0
}

software_edit_config() {
    local config_path

    if [[ -z "${BASE_AGBOOT_ROOT:-}" ]]; then
        msg "AGBOOT is not mounted."
        return 1
    fi

    config_path="$BASE_AGBOOT_ROOT/$BASE_CONFIG_DIR/$SOFTWARE_CONFIG_FILE"

    if [[ ! -f "$config_path" ]]; then
        msg "Software Configuration file not found: $config_path"
        return 1
    fi

    if ! command -v sudoedit >/dev/null 2>&1; then
        msg "sudoedit is not available."
        return 1
    fi

    sudoedit -- "$config_path"
}

software_save_config() {
    if [[ -z "${BASE_AGBOOT_ROOT:-}" ]]; then
        msg "AGBOOT is not mounted."
        return 1
    fi

    if [[ ! -f "$BASE_AGBOOT_ROOT/$BASE_CONFIG_DIR/$SOFTWARE_CONFIG_FILE" ]]; then
        msg "Software Configuration file not found."
        return 1
    fi

    if ! software_load_config; then
        msg "Configuration could not be reloaded. Check the file for errors."
        return 1
    fi

    if ! validate_software; then
        msg "Software Configuration contains invalid packages. Please correct them."
        return 1
    fi

    if ! sync; then
        msg "Unable to synchronize configuration changes."
        return 1
    fi

    success "Software Configuration saved and validated."
    return 0
}
