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
# ==============================================================================

readonly AGKEYS_SIZE_MIB=64
readonly AGKEYS_LABEL="AGKEYS"
readonly AGKEYS_MAPPER="archguard-agkeys"
readonly AGKEYS_MOUNT="/run/archguard/agkeys"
readonly AGKEYS_KEY_SOURCE="/var/lib/sbctl"


check_key_storage_requirements(){
    local command

    for command in \
        sgdisk \
        cryptsetup \
        mkfs.ext4 \
        mount \
        umount \
        lsblk \
        partprobe \
        udevadm \
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


create_agkeys_partition(){
    local first_free
    local start

    [[ -z "${AG_AGKEYS_PART:-}" ]] \
        || fatal "AGKEYS partition is already assigned: $AG_AGKEYS_PART"

    msg "Creating ${AGKEYS_SIZE_MIB} MiB AGKEYS partition..."

    # Find the first sector after the existing ISO partitions.
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
    )

    [[ "$first_free" =~ ^[0-9]+$ ]] \
        || fatal "Failed to determine the first free sector."

    # Align the new partition to 1 MiB.
    start=$(( (first_free + 2047) / 2048 * 2048 ))

    printf 'start=%s, size=%sMiB, type=83\n' \
        "$start" \
        "$AGKEYS_SIZE_MIB" |
        sudo sfdisk --append "$AG_USB_DISK" >/dev/null \
        || fatal "Failed to create AGKEYS partition."

    sudo partprobe "$AG_USB_DISK" \
        || fatal "Failed to reload the partition table."

    sudo udevadm settle \
        || fatal "Failed waiting for the new partition."

    AG_AGKEYS_PART=$(
        lsblk -nrpo NAME,START "$AG_USB_DISK" |
            awk -v start="$start" '$2 == start { print $1 }'
    )

    [[ -b "$AG_AGKEYS_PART" ]] \
        || fatal "Failed to locate the new AGKEYS partition."

    success "AGKEYS partition created: $AG_AGKEYS_PART"
}


format_agkeys(){
    [[ -n "${AG_AGKEYS_PASSPHRASE:-}" ]] \
        || fatal "AGKEYS passphrase not available."

    [[ -b "${AG_AGKEYS_PART:-}" ]] \
        || fatal "AGKEYS partition not available: ${AG_AGKEYS_PART:-unset}"

    msg "Creating LUKS2 container on: $AG_AGKEYS_PART"

    printf '%s' "$AG_AGKEYS_PASSPHRASE" |
        sudo cryptsetup luksFormat \
            --type luks2 \
            --batch-mode \
            "$AG_AGKEYS_PART" \
            -d - \
        || fatal "Failed to create AGKEYS LUKS2 container."

    msg "Opening AGKEYS LUKS container"

    printf '%s' "$AG_AGKEYS_PASSPHRASE" |
        sudo cryptsetup open \
            "$AG_AGKEYS_PART" \
            "$AGKEYS_MAPPER" \
            -d - \
        || fatal "Failed to open AGKEYS LUKS container."

    [[ -b "/dev/mapper/$AGKEYS_MAPPER" ]] \
        || fatal "AGKEYS mapper was not created: /dev/mapper/$AGKEYS_MAPPER"

    success "AGKEYS LUKS2 container created and opened."
}

create_agkeys_filesystem(){
    msg "Creating AGKEYS filesystem..."

    sudo mkfs.ext4 \
        -L "$AGKEYS_LABEL" \
        "/dev/mapper/$AGKEYS_MAPPER" \
        >/dev/null \
        || fatal "Failed to create AGKEYS filesystem."

    success "AGKEYS filesystem created."
}


mount_agkeys(){
    msg "Mounting AGKEYS..."

    sudo mkdir -p "$AGKEYS_MOUNT" \
        || fatal "Failed to create AGKEYS mount point."

    sudo mount \
        "/dev/mapper/$AGKEYS_MAPPER" \
        "$AGKEYS_MOUNT" \
        || fatal "Failed to mount AGKEYS."

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
        || fatal "Failed to create AGKEYS directory structure."
}


copy_key_file(){
    local source="$1"
    local target="$2"

    [[ -f "$source" ]] \
        || fatal "Required Secure Boot key file not found: $source"

    sudo install -m 600 \
        "$source" \
        "$target" \
        || fatal "Failed to copy Secure Boot key file: $source"
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

    msg "Verifying Secure Boot key storage..."

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
            || fatal "AGKEYS verification failed: sbctl/$file"
    done

    success "AGKEYS key verification passed."
}


close_agkeys(){
    msg "Closing AGKEYS..."

    sudo umount "$AGKEYS_MOUNT" \
        || fatal "Failed to unmount AGKEYS."

    sudo cryptsetup luksClose "$AGKEYS_MAPPER" \
        || fatal "Failed to close AGKEYS."

    sudo rmdir "$AGKEYS_MOUNT" 2>/dev/null || true

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