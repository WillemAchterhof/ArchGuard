#!/usr/bin/env bash
# ArchGuard USB Builder - Base Configuration Validation
# /validate/validate-base.sh

validate_base_config() {
    local errors=0
    local value

    msg "Validating Base Configuration..."

    # Filesystem
    case "${BASE_ENV_FILESYSTEM:-}" in
        btrfs|ext4) ;;
        *)
            msg "Invalid filesystem: ${BASE_ENV_FILESYSTEM:-Empty}"
            ((errors++))
            ;;
    esac

    # EFI partition size
    if [[ ! "${BASE_ENV_EFI_SIZE:-}" =~ ^[1-9][0-9]*[KMG]$ ]]; then
        msg "Invalid EFI partition size."
        ((errors++))
    fi

    # LUKS
    if [[ "${BASE_ENV_LUKS:-}" != "true" ]]; then
        msg "LUKS must be enabled."
        ((errors++))
    fi

    # Swap
    case "${BASE_ENV_SWAP_ENABLED:-}" in
        half|full|disabled) ;;
        *)
            msg "Invalid swap configuration."
            ((errors++))
            ;;
    esac

    if [[ -n "${BASE_ENV_SWAP_SIZE:-}" ]] &&
       [[ ! "$BASE_ENV_SWAP_SIZE" =~ ^[1-9][0-9]*[KMG]$ ]]; then
        msg "Invalid swap size."
        ((errors++))
    fi

    # Hostname
    if [[ -z "${BASE_ENV_HOSTNAME:-}" ]] ||
       [[ ! "$BASE_ENV_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] ||
       (( ${#BASE_ENV_HOSTNAME} > 63 )); then
        msg "Invalid or empty hostname."
        ((errors++))
    fi

    # Username
    if [[ ! "${BASE_ENV_USERNAME:-}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] ||
       (( ${#BASE_ENV_USERNAME} > 32 )); then
        msg "Invalid or empty username."
        ((errors++))
    fi

    # Password must be entered separately.
    if [[ -n "${BASE_ENV_PASSWORD:-}" ]]; then
        msg "Password must not be stored in config-base.env."
        ((errors++))
    fi

    # Locale
    if [[ -z "${BASE_ENV_LOCALE:-}" ]] ||
       ! grep -Fqx "${BASE_ENV_LOCALE} UTF-8" /usr/share/i18n/SUPPORTED 2>/dev/null; then
        msg "Invalid or unavailable locale: ${BASE_ENV_LOCALE:-Empty}"
        ((errors++))
    fi

    # Timezone
    if [[ -z "${BASE_ENV_TIMEZONE:-}" ]] ||
       [[ ! -f "/usr/share/zoneinfo/${BASE_ENV_TIMEZONE}" ]]; then
        msg "Invalid or unavailable timezone: ${BASE_ENV_TIMEZONE:-Empty}"
        ((errors++))
    fi

    # Keyboard layout
    if [[ -z "${BASE_ENV_KEYBOARD:-}" ]] ||
       ! localectl list-keymaps 2>/dev/null | grep -Fxq -- "$BASE_ENV_KEYBOARD"; then
        msg "Invalid or unavailable keyboard layout: ${BASE_ENV_KEYBOARD:-Empty}"
        ((errors++))
    fi

    # Parallel package downloads
    if [[ ! "${BASE_ENV_PACMAN_PARALLEL:-}" =~ ^[1-9][0-9]*$ ]]; then
        msg "Parallel downloads must be a positive integer."
        ((errors++))
    fi

    if (( errors > 0 )); then
        msg "Base Configuration contains $errors error(s)."
        return 1
    fi

    success "Base Configuration is valid."
    return 0
}
