# ==============================================================================
# Confirmation
# ==============================================================================

confirm_usb_overwrite(){
    local passphrase
    local confirmation
    local size
    local model

    size=$(lsblk -dnro SIZE "$AG_USB_DISK")
    model=$(lsblk -dnro MODEL "$AG_USB_DISK" | xargs)

    clear

    printf '\n'
    printf '%s\n' '================================================'
    printf '%s\n' ' ArchGuard USB Builder - Destructive Operation'
    printf '%s\n' '================================================'
    printf '\n'

    printf 'Target disk : %s\n' "$AG_USB_DISK"
    printf 'Model       : %s\n' "${model:--}"
    printf 'Capacity    : %s\n' "$size"
    printf '\n'

    warn "ALL EXISTING DATA ON THIS DISK WILL BE DESTROYED."
    printf '\n'

    read -r -s -p \
        'Type a passphrase for the Secure Boot key storage and press ENTER: ' \
        passphrase
    printf '\n'

    [[ -n "$passphrase" ]] \
        || fatal "Passphrase cannot be empty."

    read -r -s -p \
        'Confirm passphrase and press ENTER to destroy all data on disk: ' \
        confirmation
    printf '\n'

    if [[ "$passphrase" != "$confirmation" ]]; then
        unset passphrase confirmation
        msg "Passphrases do not match. USB creation cancelled."
        return 1
    fi

    unset confirmation

    validate_disk_choice "$AG_USB_DISK" \
        || {
            unset passphrase
            return 1
        }

    AG_AGKEYS_PASSPHRASE="$passphrase"
    unset passphrase

    success "USB destruction confirmed."
}
