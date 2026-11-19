
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
# User Input
# ==============================================================================

read_disk_choice() {
    local count="$1"
    local input
    local number

    DISK_CHOICE=""

    # Ctrl+D (EOF) is treated like quit.
    if ! IFS= read -r -p 'Selection: ' input; then
        return 1
    fi

    case "$input" in
        q|Q)
            return 1
            ;;
        r|R)
            return 2
            ;;
    esac

    # Invalid input: redraw the menu silently.
    if [[ ! "$input" =~ ^[0-9]+$ ]]; then
        return 2
    fi

    # No valid selection exists when there are no disks.
    if (( count == 0 )); then
        return 2
    fi

    # Reject excessively long numbers before arithmetic evaluation.
    if (( ${#input} > 9 )); then
        return 2
    fi

    number=$((10#$input))

    if (( number < 1 || number > count )); then
        return 2
    fi

    DISK_CHOICE="$number"
    return 0
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

run_selectdisk() {
    local -a disks=()
    local disk
    local result

    command -v lsblk >/dev/null 2>&1 \
        || fatal "Required command not found: lsblk"

    while true; do
        # Discover disks on every iteration, including refreshes.
        mapfile -t disks < <(find_usb_disks)

        display_disk_menu "${disks[@]}"

        read_disk_choice "${#disks[@]}"
        result=$?

        case "$result" in
            0)
                # A valid selection was entered.
                ;;
            2)
                # Refresh or invalid input: redraw menu.
                continue
                ;;
            *)
                # q, Ctrl+D, or EOF.
                msg "Disk selection cancelled."
                return 1
                ;;
        esac

        disk="${disks[$((DISK_CHOICE - 1))]}"

        if ! validate_disk_choice "$disk"; then
            # Keep the warning visible before the menu is cleared.
            sleep 1
            continue
        fi

        select_disk "$disk"
        return 0
    done
}