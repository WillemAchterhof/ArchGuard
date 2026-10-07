#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Disk Selection
# ==============================================================================
# /modules/select-disk.sh


# ==============================================================================
# Disk Discovery
# ==============================================================================

find_usb_disks(){
    lsblk -dpno NAME,TRAN,TYPE |
        awk '$2 == "usb" && $3 == "disk" { print $1 }'
}


# ==============================================================================
# Menu Display
# ==============================================================================

display_disk_menu(){
    local disks=("$@")
    local index
    local disk
    local size
    local model

    clear
    
    printf '\n'
    printf '%s\n' '================================================'
    printf '%s\n' ' ArchGuard USB Builder - Disk Selection'
    printf '%s\n' '================================================'
    printf '\n'
    printf '%s\n' 'Select the USB disk to use for ArchGuard.'
    printf '%s\n' 'WARNING: The selected disk will be overwritten.'
    printf '\n'

    if (( ${#disks[@]} == 0 )); then
        warn "No USB disks found."
        printf '\n'
        printf '%s\n' 'Connect the target USB disk and try again.'
    else
        for index in "${!disks[@]}"; do
            disk="${disks[$index]}"
            size=$(lsblk -dnro SIZE "$disk")
            model=$(lsblk -dnro MODEL "$disk" | xargs)

            printf ' [%d] %-15s %-10s %s\n' \
                "$((index + 1))" \
                "$disk" \
                "$size" \
                "${model:--}"
        done
    fi

    printf '\n'
    printf '%s\n' '[r] Refresh   [q] Quit'
    printf '\n'
}

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

# ==============================================================================
# User Input
# ==============================================================================

read_disk_choice(){
    local count="$1"
    local choice

    read -r -p 'Selection: ' choice || return 1

    case "$choice" in
        q|Q)
            msg "Disk selection cancelled."
            return 1
            ;;
        r|R)
            return 2
            ;;
    esac

    if [[ ! "$choice" =~ ^[0-9]+$ ]] ||
       (( choice < 1 || choice > count )); then
        warn "Invalid selection."
        return 2
    fi

    printf '%s\n' "$choice"
}


# ==============================================================================
# Selection Validation
# ==============================================================================

validate_disk_choice(){
    local disk="$1"

    if [[ ! -b "$disk" ]]; then
        warn "Selected device is no longer available."
        return 1
    fi

    if ! lsblk -dnro TRAN,TYPE "$disk" |
        awk '$1 == "usb" && $2 == "disk" { found = 1 }
             END { exit !found }'; then
        warn "Selected device is no longer detected as a USB disk."
        return 1
    fi

    return 0
}


# ==============================================================================
# Selection Commit
# ==============================================================================

select_disk(){
    local disk="$1"

    AG_USB_DISK="$disk"

    success "Selected USB disk: $AG_USB_DISK"
}


# ==============================================================================
# Module Entry Point
# ==============================================================================

run_selectdisk(){
    local -a disks=()
    local choice
    local disk
    local result

    command -v lsblk >/dev/null 2>&1 \
        || fatal "Required command not found: lsblk"

    while true; do
        mapfile -t disks < <(find_usb_disks)

        display_disk_menu "${disks[@]}"

        if choice=$(read_disk_choice "${#disks[@]}"); then
            :
        else
            result=$?

            case "$result" in
                1)
                    return 1
                    ;;
                2)
                    continue
                    ;;
            esac
        fi

        disk="${disks[$((choice - 1))]}"

        if ! validate_disk_choice "$disk"; then
            continue
        fi

        select_disk "$disk"
        
        confirm_usb_overwrite \
        || return 1

        return 0
    done
}