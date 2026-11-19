#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - USB Validation
# ==============================================================================
# /lib/check-usb.sh

check_archguard_usb(){
    local disk="${AG_USB_DISK:-}"
    local disk_info
    local partition_info

    # A disk must have been selected.
    [[ -n "$disk" ]] || return 1

    # The selected device must still exist.
    [[ -b "$disk" ]] || return 1

    # It must still be detected as a USB disk.
    disk_info=$(lsblk -dnro TRAN,TYPE "$disk" 2>/dev/null) \
        || return 1

    awk '$1 == "usb" && $2 == "disk" { found = 1 }
         END { exit !found }' <<< "$disk_info" \
        || return 1

    # Read the partitions belonging to this disk.
    partition_info=$(lsblk -nrpo LABEL,TYPE,FSTYPE "$disk" 2>/dev/null) \
        || return 1

    # A complete ArchGuard USB must contain both expected partitions.
    awk '
        $1 == "AGBOOT" && $2 == "part" && $3 == "ext4" {
            boot = 1
        }

        $1 == "AGKEYS" && $2 == "part" && $3 == "crypto_LUKS" {
            keys = 1
        }

        END {
            exit !(boot && keys)
        }
    ' <<< "$partition_info"
}


require_archguard_usb(){
    if ! check_archguard_usb; then
        warn "No valid ArchGuard USB found on the selected device."
        warn "Do you need to create an ArchGuard USB first?"
        return 1
    fi

    return 0
}
