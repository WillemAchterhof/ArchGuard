
#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Boot Storage
# ==============================================================================
# /modules/create-boot-storage.sh

# ==============================================================================
# Initialization
# ==============================================================================

readonly AGBOOT_SIZE_MIB=256
readonly AGBOOT_LABEL="AGBOOT"
readonly AGBOOT_MOUNT="/run/archguard/agboot"

# Bootstrap entry point expected by secure-boot.sh.
readonly AGBOOT_INSTALLER="archguard-install.sh"

# Local bootstrap source directory.
readonly AGBOOT_BOOTSTRAP_SOURCE="$DIR_MAIN/bootstrap"

AG_AGBOOT_PART=""


# ==============================================================================
# Requirements
# ==============================================================================

check_boot_storage_requirements(){

    local command

    for command in \
        xargs \
        sfdisk \
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
        cmp \
        cp \
        diff \
        chmod \
        mkdir \
        rmdir \
        bash
    do
        require_command "$command"
    done

    [[ -n "${AG_USB_DISK:-}" ]] \
        || fatal "No USB disk has been selected."

    [[ -b "$AG_USB_DISK" ]] \
        || fatal "Selected USB disk is no longer available: $AG_USB_DISK"

    [[ -z "${AG_AGBOOT_PART:-}" ]] \
        || fatal "AGBOOT partition is already assigned: $AG_AGBOOT_PART"

    [[ -d "$AGBOOT_BOOTSTRAP_SOURCE" ]] \
        || fatal "Bootstrap directory not found: $AGBOOT_BOOTSTRAP_SOURCE"

    [[ -f "$AGBOOT_BOOTSTRAP_SOURCE/$AGBOOT_INSTALLER" ]] \
        || fatal "Bootstrap entry point not found: $AGBOOT_INSTALLER"

    [[ -d "$AGBOOT_BOOTSTRAP_SOURCE/lib" ]] \
        || fatal "Bootstrap library directory not found."

    [[ -d "$AGBOOT_BOOTSTRAP_SOURCE/modules" ]] \
        || fatal "Bootstrap modules directory not found."

    bash -n "$AGBOOT_BOOTSTRAP_SOURCE/$AGBOOT_INSTALLER" \
        || fatal "Bootstrap entry point has invalid Bash syntax."
}


# ==============================================================================
# Cleanup
# ==============================================================================

# Unmount AGBOOT.
# Safe to call repeatedly, including from the EXIT trap.

agboot_close_devices(){

    if mountpoint -q "$AGBOOT_MOUNT" 2>/dev/null; then
        sudo umount "$AGBOOT_MOUNT" \
            || warn "Failed to unmount AGBOOT: $AGBOOT_MOUNT"
    fi

    sudo rmdir "$AGBOOT_MOUNT" 2>/dev/null || true
}


agboot_cleanup(){

    agboot_close_devices
    cleanup
}


agboot_fatal(){

    local message="$1"

    printf '[FATAL] %s\n' "$message" >&2

    trap - EXIT
    agboot_cleanup

    exit 1
}


# ==============================================================================
# AGBOOT Partition
# ==============================================================================

create_agboot_partition(){

    local first_free
    local start

    [[ -z "${AG_AGBOOT_PART:-}" ]] \
        || agboot_fatal "AGBOOT partition is already assigned: $AG_AGBOOT_PART"

    msg "Creating ${AGBOOT_SIZE_MIB} MiB AGBOOT partition..."

    first_free=$(
        sudo sfdisk -d "$AG_USB_DISK" |
            awk -F'[=, ]+' '
                /start=/ {
                    for (i = 1; i <= NF; i++) {
                        if ($i == "start") s = $(i + 1)
                        if ($i == "size")  z = $(i + 1)
                    }
                    if (s + z > m) m = s + z
                }
                END { print m }
            '
    ) || agboot_fatal "Failed to determine the first free sector."

    [[ "$first_free" =~ ^[0-9]+$ ]] \
        || agboot_fatal "Failed to determine the first free sector."

    # Leave a 1 MiB gap, then align the new partition to 1 MiB.
    start=$(( (first_free + 2048 + 2047) / 2048 * 2048 ))

    printf 'start=%s, size=%sMiB, type=83\n' \
        "$start" \
        "$AGBOOT_SIZE_MIB" |
        sudo sfdisk --append "$AG_USB_DISK" >/dev/null \
        || agboot_fatal "Failed to create AGBOOT partition."

    sudo partprobe "$AG_USB_DISK" \
        || agboot_fatal "Failed to reload the partition table."

    sudo udevadm settle \
        || agboot_fatal "Failed waiting for the new partition."

    AG_AGBOOT_PART=$(
        lsblk -nrpo NAME,START "$AG_USB_DISK" |
            awk -v start="$start" '$2 == start { print $1; exit }'
    ) || agboot_fatal "Failed to locate the new AGBOOT partition."

    [[ -b "$AG_AGBOOT_PART" ]] \
        || agboot_fatal "Failed to locate the new AGBOOT partition."

    success "AGBOOT partition created: $AG_AGBOOT_PART"
}


format_agboot_partition(){

    [[ -b "${AG_AGBOOT_PART:-}" ]] \
        || agboot_fatal "AGBOOT partition is not available."

    msg "Formatting AGBOOT as ext4..."

    sudo mkfs.ext4 \
        -F \
        -L "$AGBOOT_LABEL" \
        "$AG_AGBOOT_PART" \
        >/dev/null \
        || agboot_fatal "Failed to format AGBOOT."

    success "AGBOOT filesystem created."
}


mount_agboot_partition(){

    msg "Mounting AGBOOT..."

    sudo mkdir -p "$AGBOOT_MOUNT" \
        || agboot_fatal "Failed to create AGBOOT mount point."

    sudo mount "$AG_AGBOOT_PART" "$AGBOOT_MOUNT" \
        || agboot_fatal "Failed to mount AGBOOT."

    success "AGBOOT mounted."
}


# ==============================================================================
# Bootstrap Installation
# ==============================================================================

copy_bootstrap(){

    local destination="$AGBOOT_MOUNT"

    msg "Installing ArchGuard bootstrap on AGBOOT..."

    mountpoint -q "$AGBOOT_MOUNT" \
        || agboot_fatal "AGBOOT is not mounted."

    [[ -d "$AGBOOT_BOOTSTRAP_SOURCE" ]] \
        || agboot_fatal "Bootstrap source directory is missing."

    # Copy the complete bootstrap contents into the AGBOOT root.
    # This preserves the directory structure and file permissions.
    sudo cp -a \
        "$AGBOOT_BOOTSTRAP_SOURCE/." \
        "$destination/" \
        || agboot_fatal "Failed to copy ArchGuard bootstrap."

    # Ensure the Secure Boot entry point is executable.
    sudo chmod 0755 "$destination/$AGBOOT_INSTALLER" \
        || agboot_fatal "Failed to set bootstrap entry point permissions."

    success "ArchGuard bootstrap installed."
}


verify_agboot_partition(){

    local label
    local installer="$AGBOOT_MOUNT/$AGBOOT_INSTALLER"

    msg "Verifying AGBOOT..."

    label=$(lsblk -no LABEL "$AG_AGBOOT_PART") \
        || agboot_fatal "Failed to read AGBOOT partition label."

    [[ "$label" == "$AGBOOT_LABEL" ]] \
        || agboot_fatal "AGBOOT label verification failed."

    [[ -f "$installer" ]] \
        || agboot_fatal "Bootstrap entry point is missing."

    [[ -x "$installer" ]] \
        || agboot_fatal "Bootstrap entry point is not executable."

    # Compare the complete bootstrap directory.
    # lost+found is created automatically by ext4.
    sudo diff -qr \
        --exclude=lost+found \
        "$AGBOOT_BOOTSTRAP_SOURCE" \
        "$AGBOOT_MOUNT" \
        >/dev/null \
        || agboot_fatal "Bootstrap verification failed: files differ."

    success "AGBOOT label, bootstrap files and permissions verified."
}


# ==============================================================================
# Configuration Files
# ==============================================================================

copy_configs(){

    local source_dir="$DIR_MAIN/configs"
    local destination_dir="$AGBOOT_MOUNT/config-files"
    local file
    local name
    local copied=0

    msg "Copying configuration files to AGBOOT..."

    [[ -d "$source_dir" ]] \
        || agboot_fatal "Configuration source directory not found: $source_dir"

    mountpoint -q "$AGBOOT_MOUNT" \
        || agboot_fatal "AGBOOT is not mounted."

    sudo mkdir -p "$destination_dir" \
        || agboot_fatal "Failed to create AGBOOT configuration directory."

    for file in "$source_dir"/*; do

        [[ -f "$file" ]] || continue

        name="${file##*/}"

        sudo install \
            --owner=0 \
            --group=0 \
            --mode=0644 \
            "$file" \
            "$destination_dir/$name" \
            || agboot_fatal "Failed to copy $name to AGBOOT."

        sudo cmp -s "$file" "$destination_dir/$name" \
            || agboot_fatal "Verification failed for $name on AGBOOT."

        copied=$((copied + 1))
    done

    if (( copied == 0 )); then
        warn "No configuration files found in: $source_dir"
    fi

    success "Configuration files copied to AGBOOT."
}


# ==============================================================================
# Close AGBOOT
# ==============================================================================

close_agboot_partition(){

    msg "Closing AGBOOT..."

    if mountpoint -q "$AGBOOT_MOUNT"; then

        sudo sync \
            || agboot_fatal "Failed to flush filesystem changes."

        sudo umount "$AGBOOT_MOUNT" \
            || agboot_fatal "Failed to unmount AGBOOT."
    fi

    sudo rmdir "$AGBOOT_MOUNT" 2>/dev/null || true

    # Resources were closed successfully; disable the EXIT trap.
    trap - EXIT

    success "AGBOOT closed."
}


# ==============================================================================
# Main
# ==============================================================================

create_boot_storage(){

    check_boot_storage_requirements

    # Ensure AGBOOT is closed if an unexpected failure occurs.
    trap 'agboot_close_devices' EXIT

    create_agboot_partition
    format_agboot_partition
    mount_agboot_partition

    copy_bootstrap
    verify_agboot_partition
    copy_configs

    close_agboot_partition

    success "AGBOOT successfully created and verified."
}
