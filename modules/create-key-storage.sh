#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - AGKEYS Creation
# ==============================================================================
# /modules/create-key-storage.sh
#
# Responsibilities:
#   - Create the AGKEYS partition
#   - Format it as LUKS2
#   - Open the encrypted container
#   - Create the filesystem
#   - Copy the ArchGuard Secure Boot key storage
#   - Verify the copied key material
#   - Unmount and close the encrypted container
#
# Required globals:
#   AG_USB_DISK
#   AG_AGKEYS_PASSPHRASE
#
# Key source:
#   /var/lib/sbctl
#
# Result:
#   AG_AGKEYS_PART -> partition containing the encrypted AGKEYS storage
#
# Notes:
#   - The partition is added to the ISO's MBR table (the ISO's hybrid MBR/GPT
#     is left untouched). MBR partitions have no GPT name, so AGKEYS is found
#     by its LUKS label (lsblk LABEL column).
#   - An EXIT trap closes AGKEYS if anything fails while it is unlocked.
# ==============================================================================

readonly AGKEYS_SIZE_MIB=64
readonly AGKEYS_LABEL="AGKEYS"
readonly AGKEYS_MAPPER="archguard-agkeys"
readonly AGKEYS_MOUNT="/run/archguard/agkeys"
readonly AGKEYS_KEY_SOURCE="/var/lib/sbctl"


check_key_storage_requirements(){
    local command

    for command in \
        sfdisk \
        cryptsetup \
        mkfs.ext4 \
        mount \
        umount \
        mountpoint \
        lsblk \
        partprobe \
        udevadm \
        install \
        sync \
        awk \
        cmp
    do
        require_command "$command"
    done

    [[ -n "${AG_USB_DISK:-}" ]] \
        || fatal "No USB disk has been selected."

    [[ -b "$AG_USB_DISK" ]] \
        || fatal "Selected USB disk is no longer available: $AG_USB_DISK"

    [[ -n "${AG_AGKEYS_PASSPHRASE:-}" ]] \
        || fatal "AGKEYS passphrase is not available."

    [[ -d "$AGKEYS_KEY_SOURCE" ]] \
        || fatal "Secure Boot key storage not found: $AGKEYS_KEY_SOURCE"
}


# Unmount and close AGKEYS. Safe to call at any time (used by the EXIT trap).
agkeys_close_devices(){
    if mountpoint -q "$AGKEYS_MOUNT" 2>/dev/null; then
        sudo umount "$AGKEYS_MOUNT" \
            || warn "Failed to unmount AGKEYS: $AGKEYS_MOUNT"
    fi

    if sudo cryptsetup status "$AGKEYS_MAPPER" >/dev/null 2>&1; then
        msg "Closing AGKEYS..."

        sudo cryptsetup luksClose "$AGKEYS_MAPPER" \
            || warn "Failed to close AGKEYS: $AGKEYS_MAPPER"
    fi

    sudo rmdir "$AGKEYS_MOUNT" 2>/dev/null || true
}


agkeys_cleanup(){
    agkeys_close_devices

    cleanup
}


agkeys_fatal(){
    local message="$1"

    printf '[FATAL] %s\n' "$message"

    trap - EXIT
    agkeys_cleanup

    exit 1
}


create_agkeys_partition(){
    local first_free
    local start

    [[ -z "${AG_AGKEYS_PART:-}" ]] \
        || agkeys_fatal "AGKEYS partition is already assigned: $AG_AGKEYS_PART"

    msg "Creating ${AGKEYS_SIZE_MIB} MiB AGKEYS partition..."

    first_free=$(
        sudo sfdisk -d "$AG_USB_DISK" |
            awk -F'[=, ]+' '/start=/ {
                for (i = 1; i <= NF; i++) {
                    if ($i == "start") s = $(i + 1)
                    if ($i == "size")  z = $(i + 1)
                }
                if (s + z > m) m = s + z
            }
            END { print m }'
    ) || agkeys_fatal "Failed to determine the first free sector."

    [[ "$first_free" =~ ^[0-9]+$ ]] \
        || agkeys_fatal "Failed to determine the first free sector."

    # Leave a 1 MiB gap (the ISO's backup GPT sits right after its last
    # partition), then align the partition to 1 MiB.
    start=$(( (first_free + 2048 + 2047) / 2048 * 2048 ))

    printf 'start=%s, size=%sMiB, type=83\n' \
        "$start" \
        "$AGKEYS_SIZE_MIB" |
        sudo sfdisk --append "$AG_USB_DISK" >/dev/null \
        || agkeys_fatal "Failed to create AGKEYS partition."

    sudo partprobe "$AG_USB_DISK" \
        || agkeys_fatal "Failed to reload the partition table."

    sudo udevadm settle \
        || agkeys_fatal "Failed waiting for the new partition."

    AG_AGKEYS_PART=$(
        lsblk -nrpo NAME,START "$AG_USB_DISK" |
            awk -v start="$start" '$2 == start { print $1 }'
    ) || agkeys_fatal "Failed to locate the new AGKEYS partition."

    [[ -b "$AG_AGKEYS_PART" ]] \
        || agkeys_fatal "Failed to locate the new AGKEYS partition."

    success "AGKEYS partition created: $AG_AGKEYS_PART"
}


format_agkeys(){
    [[ -n "${AG_AGKEYS_PASSPHRASE:-}" ]] \
        || agkeys_fatal "AGKEYS passphrase not available."

    [[ -b "${AG_AGKEYS_PART:-}" ]] \
        || agkeys_fatal \
            "AGKEYS partition not available: ${AG_AGKEYS_PART:-unset}"

    msg "Creating LUKS2 container on: $AG_AGKEYS_PART"

    printf '%s' "$AG_AGKEYS_PASSPHRASE" |
        sudo cryptsetup luksFormat \
            --type luks2 \
            --label "$AGKEYS_LABEL" \
            --batch-mode \
            "$AG_AGKEYS_PART" \
            -d - \
        || agkeys_fatal "Failed to create AGKEYS LUKS2 container."

    # From here on, never leave AGKEYS unlocked if the run is interrupted
    # or fails outside agkeys_fatal.
    trap 'agkeys_close_devices' EXIT

    msg "Opening AGKEYS LUKS container..."

    printf '%s' "$AG_AGKEYS_PASSPHRASE" |
        sudo cryptsetup open \
            "$AG_AGKEYS_PART" \
            "$AGKEYS_MAPPER" \
            -d - \
        || agkeys_fatal "Failed to open AGKEYS LUKS container."

    [[ -b "/dev/mapper/$AGKEYS_MAPPER" ]] \
        || agkeys_fatal \
            "AGKEYS mapper was not created: /dev/mapper/$AGKEYS_MAPPER"

    success "AGKEYS LUKS2 container created and opened."
}


create_agkeys_filesystem(){
    msg "Creating AGKEYS filesystem..."

    sudo mkfs.ext4 \
        -L "$AGKEYS_LABEL" \
        "/dev/mapper/$AGKEYS_MAPPER" \
        >/dev/null \
        || agkeys_fatal "Failed to create AGKEYS filesystem."

    success "AGKEYS filesystem created."
}


mount_agkeys(){
    msg "Mounting AGKEYS..."

    sudo mkdir -p "$AGKEYS_MOUNT" \
        || agkeys_fatal "Failed to create AGKEYS mount point."

    sudo mount \
        "/dev/mapper/$AGKEYS_MAPPER" \
        "$AGKEYS_MOUNT" \
        || agkeys_fatal "Failed to mount AGKEYS."

    success "AGKEYS mounted."
}


prepare_agkeys_tree(){
    msg "Preparing Secure Boot key storage..."

    sudo install -d -m 700 \
        "$AGKEYS_MOUNT/sbctl" \
        "$AGKEYS_MOUNT/sbctl/keys" \
        "$AGKEYS_MOUNT/sbctl/keys/PK" \
        "$AGKEYS_MOUNT/sbctl/keys/KEK" \
        "$AGKEYS_MOUNT/sbctl/keys/db" \
        || agkeys_fatal "Failed to create AGKEYS directory structure."
}


copy_key_file(){
    local source="$1"
    local target="$2"

    [[ -f "$source" ]] \
        || agkeys_fatal "Required Secure Boot key file not found: $source"

    sudo install -m 600 \
        "$source" \
        "$target" \
        || agkeys_fatal "Failed to copy Secure Boot key file: $source"
}


copy_secure_boot_keys(){
    local source="$AGKEYS_KEY_SOURCE"
    local target="$AGKEYS_MOUNT/sbctl"

    msg "Copying Secure Boot keys to AGKEYS..."

    copy_key_file \
        "$source/GUID" \
        "$target/GUID"

    copy_key_file \
        "$source/keys/PK/PK.key" \
        "$target/keys/PK/PK.key"

    copy_key_file \
        "$source/keys/PK/PK.pem" \
        "$target/keys/PK/PK.pem"

    copy_key_file \
        "$source/keys/KEK/KEK.key" \
        "$target/keys/KEK/KEK.key"

    copy_key_file \
        "$source/keys/KEK/KEK.pem" \
        "$target/keys/KEK/KEK.pem"

    copy_key_file \
        "$source/keys/db/db.key" \
        "$target/keys/db/db.key"

    copy_key_file \
        "$source/keys/db/db.pem" \
        "$target/keys/db/db.pem"

    success "Secure Boot keys copied to AGKEYS."
}


verify_secure_boot_keys(){
    local source="$AGKEYS_KEY_SOURCE"
    local target="$AGKEYS_MOUNT/sbctl"
    local file

    msg "Verifying Secure Boot key storage..."

    # Flush and drop caches so cmp reads the files back from the device
    # instead of comparing against what was just written to memory.
    sync

    sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' \
        || agkeys_fatal "Failed to drop caches before verification."

    for file in \
        GUID \
        keys/PK/PK.key \
        keys/PK/PK.pem \
        keys/KEK/KEK.key \
        keys/KEK/KEK.pem \
        keys/db/db.key \
        keys/db/db.pem
    do
        sudo cmp \
            "$source/$file" \
            "$target/$file" \
            || agkeys_fatal "AGKEYS verification failed: sbctl/$file"
    done

    success "AGKEYS key verification passed."
}


close_agkeys(){
    msg "Closing AGKEYS..."

    sudo umount "$AGKEYS_MOUNT" \
        || agkeys_fatal "Failed to unmount AGKEYS."

    sudo cryptsetup luksClose "$AGKEYS_MAPPER" \
        || agkeys_fatal "Failed to close AGKEYS."

    sudo rmdir "$AGKEYS_MOUNT" 2>/dev/null || true

    # Closed cleanly: the EXIT trap is no longer needed.
    trap - EXIT

    success "AGKEYS closed."
}


create_key_storage(){
    check_key_storage_requirements

    create_agkeys_partition
    format_agkeys
    create_agkeys_filesystem
    mount_agkeys
    prepare_agkeys_tree
    copy_secure_boot_keys
    verify_secure_boot_keys
    close_agkeys

    unset AG_AGKEYS_PASSPHRASE

    success "AGKEYS successfully created and secured."
}
