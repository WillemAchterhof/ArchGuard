#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Boot Storage
# ==============================================================================
# /modules/create-boot-storage.sh
#
# Responsibilities:
#   - Validate the selected USB disk and required commands
#   - Download the ArchGuard installer from GitHub
#   - Create the AGBOOT partition
#   - Format AGBOOT as ext4 and apply the AGBOOT label
#   - Install archguard-install.sh with root ownership and executable permissions
#   - Verify the partition label and installed installer contents
#   - Unmount AGBOOT and remove temporary files
#
# Required globals:
#   AG_USB_DISK
#
# Result:
#   AG_AGBOOT_PART -> partition containing the ArchGuard installer
#
# Installer source:
#   https://raw.githubusercontent.com/WillemAchterhof/archguard-install/refs/heads/main/archguard_install.sh
#
# Partition:
#   Label: AGBOOT
#   Filesystem: ext4
#   Type: MBR Linux partition (83)
#   Size: 256 MiB
#
# Installer destination:
#   /archguard-install.sh (root of AGBOOT)
#
# File permissions:
#   root:root 0755
#
# Host requirements:
#   util-linux  e2fsprogs  curl  bash  coreutils  gawk
#
# Notes:
#   - The partition is appended to the ISO's MBR table, leaving the hybrid
#     GPT layout untouched.
#   - The partition starts on a 1 MiB boundary, leaving a 1 MiB gap after
#     the last existing partition to avoid the backup GPT area.
#   - An EXIT trap unmounts AGBOOT and removes the temporary download if
#     the operation fails while in progress.
# ==============================================================================

readonly AGBOOT_SIZE_MIB=256
readonly AGBOOT_LABEL="AGBOOT"
readonly AGBOOT_MOUNT="/run/archguard/agboot"
readonly AGBOOT_INSTALLER="archguard-install.sh"
readonly AGBOOT_INSTALLER_URL="https://raw.githubusercontent.com/WillemAchterhof/archguard-install/refs/heads/main/archguard_install.sh"

AG_AGBOOT_PART=""
AGBOOT_DOWNLOAD=""


check_boot_storage_requirements(){
    local command

    for command in \
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
        curl \
        mktemp \
        rm \
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
}


# Unmount AGBOOT and remove temporary resources.
# Safe to call repeatedly, including from the EXIT trap.
agboot_close_devices(){
    if mountpoint -q "$AGBOOT_MOUNT" 2>/dev/null; then
        sudo umount "$AGBOOT_MOUNT" \
            || warn "Failed to unmount AGBOOT: $AGBOOT_MOUNT"
    fi

    sudo rmdir "$AGBOOT_MOUNT" 2>/dev/null || true

    if [[ -n "${AGBOOT_DOWNLOAD:-}" ]]; then
        rm -f -- "$AGBOOT_DOWNLOAD" \
            || warn "Failed to remove temporary installer download."
        AGBOOT_DOWNLOAD=""
    fi
}


agboot_cleanup(){
    agboot_close_devices
    cleanup
}


agboot_fatal(){
    local message="$1"

    printf '[FATAL] %s\n' "$message"

    trap - EXIT
    agboot_cleanup

    exit 1
}


download_agboot_installer(){
    msg "Downloading ArchGuard installer from GitHub..."

    AGBOOT_DOWNLOAD=$(mktemp) \
        || agboot_fatal "Failed to create temporary download file."

    # Clean up the temporary download if a later command fails unexpectedly.
    trap 'agboot_close_devices' EXIT

    curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --retry 3 \
        --connect-timeout 10 \
        --output "$AGBOOT_DOWNLOAD" \
        "$AGBOOT_INSTALLER_URL" \
        || agboot_fatal "Failed to download ArchGuard installer."

    [[ -s "$AGBOOT_DOWNLOAD" ]] \
        || agboot_fatal "Downloaded installer is empty."

    bash -n "$AGBOOT_DOWNLOAD" \
        || agboot_fatal "Downloaded installer has invalid Bash syntax."

    success "ArchGuard installer downloaded and syntax checked."
}


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


populate_agboot_partition(){
    msg "Installing ArchGuard installer on AGBOOT..."

    sudo install \
        --owner=0 \
        --group=0 \
        --mode=0755 \
        "$AGBOOT_DOWNLOAD" \
        "$AGBOOT_MOUNT/$AGBOOT_INSTALLER" \
        || agboot_fatal "Failed to install ArchGuard installer on AGBOOT."

    success "ArchGuard installer installed."
}


verify_agboot_partition(){
    local label
    local installer="$AGBOOT_MOUNT/$AGBOOT_INSTALLER"

    msg "Verifying AGBOOT..."

    label=$(lsblk -no LABEL "$AG_AGBOOT_PART" | xargs) \
        || agboot_fatal "Failed to read AGBOOT partition label."

    [[ "$label" == "$AGBOOT_LABEL" ]] \
        || agboot_fatal "AGBOOT label verification failed."

    [[ -f "$installer" ]] \
        || agboot_fatal "Installer is missing from AGBOOT."

    [[ -x "$installer" ]] \
        || agboot_fatal "Installer is not executable."

    cmp -s "$AGBOOT_DOWNLOAD" "$installer" \
        || agboot_fatal "Installer verification failed: files differ."

    success "AGBOOT label, permissions, and installer contents verified."
}


close_agboot_partition(){
    msg "Closing AGBOOT..."

    if mountpoint -q "$AGBOOT_MOUNT"; then
        sudo sync \
            || agboot_fatal "Failed to flush filesystem changes."

        sudo umount "$AGBOOT_MOUNT" \
            || agboot_fatal "Failed to unmount AGBOOT."
    fi

    sudo rmdir "$AGBOOT_MOUNT" 2>/dev/null || true

    rm -f -- "$AGBOOT_DOWNLOAD" \
        || agboot_fatal "Failed to remove temporary installer download."

    AGBOOT_DOWNLOAD=""

    # Resources were closed successfully; disable the EXIT trap.
    trap - EXIT

    success "AGBOOT closed."
}


create_boot_storage(){
    check_boot_storage_requirements

    download_agboot_installer
    create_agboot_partition
    format_agboot_partition
    mount_agboot_partition
    populate_agboot_partition
    verify_agboot_partition
    close_agboot_partition

    success "AGBOOT successfully created and verified."
}