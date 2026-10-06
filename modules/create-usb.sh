#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - USB Creation
# ==============================================================================
# /modules/create-usb.sh
#
# Responsibilities:
#   - Validate the selected USB disk and ArchGuard ISO
#   - Confirm the destructive operation
#   - Write the ISO to the USB disk using dd
#   - Flush and verify the written ISO data
#
# Required globals:
#   AG_USB_DISK
#   AG_ISO_FILE
# ==============================================================================


# ==============================================================================
# Validation
# ==============================================================================

check_usb_requirements(){
    local command

    for command in dd cmp blockdev stat; do
        command -v "$command" >/dev/null 2>&1 \
            || fatal "Required command not found: $command"
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
    write_iso_to_usb
    verify_usb_iso

    success "ArchGuard ISO successfully written and verified."
}