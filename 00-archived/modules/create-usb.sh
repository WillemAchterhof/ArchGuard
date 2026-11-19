#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - USB Creation
# ==============================================================================
# /modules/create-usb.sh

# ==============================================================================
# Validation
# ==============================================================================

check_usb_requirements(){
    local command

    for command in dd cmp blockdev stat wipefs partprobe udevadm; do
        require_command "$command"
    done

    [[ -n "${AG_USB_DISK:-}" ]] \
        || fatal "No USB disk has been selected."

    [[ -n "${AG_ISO_FILE:-}" && -f "$AG_ISO_FILE" && -r "$AG_ISO_FILE" ]] \
        || fatal "ArchGuard ISO is missing or unreadable: ${AG_ISO_FILE:-unset}"

    [[ "$(stat -c '%s' "$AG_ISO_FILE")" -gt 0 ]] \
        || fatal "ArchGuard ISO is empty."

    [[ -b "$AG_USB_DISK" ]] \
        || fatal "Selected USB disk is no longer available: $AG_USB_DISK"
}

# ==============================================================================
# Disk Wipe
# ==============================================================================

wipe_usb_disk(){
    local sectors
    local part

    msg "Wiping $AG_USB_DISK..."

    # Make sure nothing on the disk is mounted before touching it.
    while read -r part; do
        sudo umount "$part" 2>/dev/null || true
    done < <(lsblk -nrpo NAME "$AG_USB_DISK" | tail -n 2)

    # Remove filesystem, LUKS and partition-table signatures.
    sudo wipefs --all --force "$AG_USB_DISK" \
        || fatal "Failed to wipe signatures on $AG_USB_DISK."

    sectors=$(sudo blockdev --getsz "$AG_USB_DISK") \
        || fatal "Failed to read the size of $AG_USB_DISK."

    # Zero the first 16 MiB and the last 16 MiB (old backup GPT lives there).
    sudo dd if=/dev/zero of="$AG_USB_DISK" bs=1M count=16 conv=fsync status=none \
        || fatal "Failed to clear the start of $AG_USB_DISK."

    if (( sectors > 65536 )); then
        sudo dd if=/dev/zero of="$AG_USB_DISK" bs=512 \
            seek=$(( sectors - 32768 )) count=32768 conv=fsync status=none \
            || fatal "Failed to clear the end of $AG_USB_DISK."
    fi

    sudo partprobe "$AG_USB_DISK" || true
    sudo udevadm settle || true

    success "Disk wiped."
}


# ==============================================================================
# ISO Writing
# ==============================================================================

write_iso_to_usb(){
    msg "Writing ArchGuard ISO to $AG_USB_DISK..."
    msg "This may take several minutes."

    sudo dd \
        if="$AG_ISO_FILE" \
        of="$AG_USB_DISK" \
        bs=4M \
        iflag=fullblock \
        status=progress \
        conv=fsync \
        || fatal "Failed to write ArchGuard ISO to USB."

    sudo blockdev --flushbufs "$AG_USB_DISK" \
        || fatal "Failed to flush the USB disk."

    success "ISO write completed."
}


# ==============================================================================
# Verification
# ==============================================================================

verify_usb_iso(){
    local iso_size

    iso_size=$(stat -c '%s' "$AG_ISO_FILE")

    msg "Verifying the written ISO data..."

    sudo cmp \
        -n "$iso_size" \
        "$AG_ISO_FILE" \
        "$AG_USB_DISK" \
        || fatal "USB verification failed. The written data does not match the ISO."

    success "USB verification passed."
}


# ==============================================================================
# Module Entry Point
# ==============================================================================

run_create_usb(){
    check_usb_requirements
    wipe_usb_disk
    write_iso_to_usb
    verify_usb_iso

    success "ArchGuard ISO successfully written and verified."
}