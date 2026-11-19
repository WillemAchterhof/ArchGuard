
#!/usr/bin/env bash
# ArchGuard USB Builder - Base Configuration Device
# /menu/base-device.sh

readonly BASE_AGBOOT_LABEL="AGBOOT"
readonly BASE_AGBOOT_DEFAULT_MOUNT="/run/archguard/agboot"

BASE_AGBOOT_MOUNT=""
BASE_AGBOOT_ROOT=""
BASE_AGBOOT_MOUNTED_BY_MODULE=0
BASE_AGBOOT_MOUNTPOINT_CREATED=0

base_mount_agboot() {
    local -a devices=()
    local -a mountpoints=()
    local device
    local mountpoint

    # A USB disk must be selected.
    if [[ -z "${AG_USB_DISK:-}" || ! -b "$AG_USB_DISK" ]]; then
        msg "No valid USB disk selected."
        return 1
    fi

    # Find AGBOOT only on the selected USB disk.
    mapfile -t devices < <(
        lsblk -nrpo NAME,LABEL,TYPE,FSTYPE "$AG_USB_DISK" |
            awk -v label="$BASE_AGBOOT_LABEL" \
                '$2 == label && $3 == "part" && $4 == "ext4" { print $1 }'
    )

    if (( ${#devices[@]} == 0 )); then
        msg "No AGBOOT partition found on selected USB disk."
        return 1
    fi

    if (( ${#devices[@]} > 1 )); then
        msg "Multiple AGBOOT partitions found on selected USB disk."
        return 1
    fi

    device="${devices[0]}"

    if (( ${#devices[@]} == 0 )); then
        msg "No AGBOOT partition found."
        return 1
    fi

    if (( ${#devices[@]} > 1 )); then
        msg "Multiple AGBOOT partitions found. Cannot determine which one to use."
        return 1
    fi

    device="${devices[0]}"

    # Check whether AGBOOT is already mounted.
    mapfile -t mountpoints < <(
        findmnt -rn -S "$device" -o TARGET | sort -u
    )

    if (( ${#mountpoints[@]} > 0 )); then
        mountpoint="$BASE_AGBOOT_DEFAULT_MOUNT"

        # Prefer the default mount point when it is already in use.
        if [[ ! " ${mountpoints[*]} " =~ " $mountpoint " ]]; then
            mountpoint="${mountpoints[0]}"
        fi

        BASE_AGBOOT_MOUNT="$mountpoint"
        BASE_AGBOOT_ROOT="$mountpoint"
        BASE_AGBOOT_MOUNTED_BY_MODULE=0

        msg "Using existing AGBOOT mount: $mountpoint"
        return 0
    fi

    # Prepare the default mount point.
    mountpoint="$BASE_AGBOOT_DEFAULT_MOUNT"

    if [[ ! -d "$mountpoint" ]]; then
        if ! sudo mkdir -p "$mountpoint"; then
            msg "Unable to create AGBOOT mount point: $mountpoint"
            return 1
        fi
        BASE_AGBOOT_MOUNTPOINT_CREATED=1
    elif [[ -n "$(find "$mountpoint" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        msg "AGBOOT mount point is not empty: $mountpoint"
        return 1
    fi

    # Mount AGBOOT.
    if ! sudo mount "$device" "$mountpoint"; then
        msg "Unable to mount AGBOOT partition: $device"

        if (( BASE_AGBOOT_MOUNTPOINT_CREATED == 1 )); then
            sudo rmdir "$mountpoint" 2>/dev/null || true
            BASE_AGBOOT_MOUNTPOINT_CREATED=0
        fi

        return 1
    fi

    BASE_AGBOOT_MOUNT="$mountpoint"
    BASE_AGBOOT_ROOT="$mountpoint"
    BASE_AGBOOT_MOUNTED_BY_MODULE=1

    msg "Mounted AGBOOT at: $mountpoint"
    return 0
}

base_unmount_agboot() {
    if (( BASE_AGBOOT_MOUNTED_BY_MODULE == 0 )); then
        BASE_AGBOOT_MOUNT=""
        BASE_AGBOOT_ROOT=""
        return 0
    fi

    msg "Unmounting AGBOOT..."

    if ! sync; then
        msg "Unable to synchronize pending filesystem changes."
        return 1
    fi

    if ! sudo umount "$BASE_AGBOOT_MOUNT"; then
        msg "Unable to unmount AGBOOT: $BASE_AGBOOT_MOUNT"
        return 1
    fi

    if (( BASE_AGBOOT_MOUNTPOINT_CREATED == 1 )); then
        sudo rmdir "$BASE_AGBOOT_MOUNT" 2>/dev/null || true
    fi

    msg "AGBOOT unmounted."

    BASE_AGBOOT_MOUNT=""
    BASE_AGBOOT_ROOT=""
    BASE_AGBOOT_MOUNTED_BY_MODULE=0
    BASE_AGBOOT_MOUNTPOINT_CREATED=0

    return 0
}
