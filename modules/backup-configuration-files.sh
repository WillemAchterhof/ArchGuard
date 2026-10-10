#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Configuration Backup
# ==============================================================================
# /modules/backup-configuration-files.sh
#
# Responsibilities:
#   - Validate the commands required for configuration backup
#   - Load the configured paths from configs/backup-configuration-files.sh
#   - Detect the AGBOOT filesystem and mount it when necessary
#   - Fall back to ~/Backup when AGBOOT is unavailable
#   - Replace the previous backup-configs directory with a fresh directory
#   - Copy configured files and directories while preserving attributes
#   - Verify the copied files and directories against the device
#   - Unmount AGBOOT only if this module mounted it
#
# Required globals:
#   DIR_MAIN
#
# Required functions:
#   msg  success  warn  fatal  require_command  cleanup
#
# Result:
#   BACKUP_DIRECTORY -> location of the configuration backup
#
# Configuration:
#   configs/backup-configuration-files.sh
#   It must define the associative array with `declare -gA BACKUP_PATHS=(...)`.
#   (-g is required: the file is sourced from inside a function, where a plain
#   `declare -A` would create a function-local array that is empty afterwards.)
#
# Backup destination:
#   AGBOOT: <AGBOOT mount point>/backup-configs   (written with sudo)
#   Fallback: ~/Backup/backup-configs
#
# Notes:
#   - Only the backup-configs directory is replaced.
#   - Missing configured paths are skipped with a warning.
#   - Copy or verification failures abort the backup.
#   - AGBOOT is unmounted only if this module mounted it.
#   - An EXIT trap unmounts AGBOOT if the operation fails while in progress.
# ==============================================================================

readonly BACKUP_CONFIG_NAME="backup-configs"
readonly BACKUP_CONFIG_FILE="$DIR_MAIN/configs/backup-file-paths.conf"
readonly BACKUP_LOCAL_ROOT="$HOME/Backup"
readonly BACKUP_AGBOOT_LABEL="AGBOOT"
readonly BACKUP_AGBOOT_DEFAULT_MOUNT="/run/archguard/agboot"

BACKUP_DIRECTORY=""
BACKUP_ROOT=""
BACKUP_AGBOOT_MOUNT=""
BACKUP_AGBOOT_MOUNTED_BY_MODULE=0
BACKUP_SUDO=()
BACKUP_COPIED=()


check_backup_requirements(){
    local command

    for command in \
        lsblk \
        findmnt \
        mount \
        umount \
        mountpoint \
        sync \
        cp \
        cmp \
        diff \
        mkdir \
        rm \
        awk
    do
        require_command "$command"
    done

    [[ -f "$BACKUP_CONFIG_FILE" ]] \
        || fatal "Backup path configuration not found: $BACKUP_CONFIG_FILE"

    [[ -r "$BACKUP_CONFIG_FILE" ]] \
        || fatal "Backup path configuration is not readable: $BACKUP_CONFIG_FILE"
}


load_backup_configuration(){
    # shellcheck disable=SC1090
    source "$BACKUP_CONFIG_FILE"
}


# Runs after load_backup_configuration has returned, so a function-local
# `declare -A` in the configuration file is detected (the array would be empty
# here).
check_backup_configuration(){
    declare -p BACKUP_PATHS &>/dev/null \
        || fatal "BACKUP_PATHS is not defined (the configuration file must use 'declare -gA')."

    [[ "$(declare -p BACKUP_PATHS 2>/dev/null)" == "declare -A"* ]] \
        || fatal "BACKUP_PATHS must be an associative array."

    (( ${#BACKUP_PATHS[@]} > 0 )) \
        || fatal "BACKUP_PATHS is empty (the configuration file must use 'declare -gA')."
}


# Unmount AGBOOT, but only if this module mounted it.
# Safe to call repeatedly, including from the EXIT trap.
backup_close_devices(){
    if (( BACKUP_AGBOOT_MOUNTED_BY_MODULE == 1 )); then
        if mountpoint -q "$BACKUP_AGBOOT_MOUNT" 2>/dev/null; then
            sudo sync \
                || warn "Failed to flush AGBOOT filesystem changes."

            sudo umount "$BACKUP_AGBOOT_MOUNT" \
                || warn "Failed to unmount AGBOOT: $BACKUP_AGBOOT_MOUNT"
        fi

        sudo rmdir "$BACKUP_AGBOOT_MOUNT" 2>/dev/null || true

        BACKUP_AGBOOT_MOUNTED_BY_MODULE=0
    fi
}


backup_cleanup(){
    backup_close_devices
    cleanup
}


backup_fatal(){
    local message="$1"

    printf '[FATAL] %s\n' "$message"

    trap - EXIT
    backup_cleanup

    exit 1
}



find_backup_destination() {
    local device
    local mountpoint
    local mountpoint_output=""
    local existing_mountpoint
    local -a devices=()
    local -a mountpoints=()
    local -a unique_mountpoints=()

    BACKUP_ROOT=""
    BACKUP_AGBOOT_MOUNT=""
    BACKUP_AGBOOT_MOUNTED_BY_MODULE=0
    BACKUP_SUDO=()

    mapfile -t devices < <(
        lsblk -rpn -o NAME,LABEL,TYPE |
            awk -v label="$BACKUP_AGBOOT_LABEL" \
                '$2 == label && $3 == "part" { print $1 }'
    )

    if (( ${#devices[@]} == 0 )); then
        warn "AGBOOT filesystem not found; using local backup destination."
        BACKUP_ROOT="$BACKUP_LOCAL_ROOT"
        return 0
    fi

    (( ${#devices[@]} == 1 )) \
        || backup_fatal "Multiple partitions labelled AGBOOT found."

    device="${devices[0]}"

    # A filesystem may have multiple mount points.
    # Handle no matches without triggering the project's error handler.
    if mountpoint_output=$(findmnt -rn -S "$device" -o TARGET 2>/dev/null); then
        mapfile -t mountpoints <<< "$mountpoint_output"
    else
        mountpoints=()
    fi

    # Deduplicate mount points using Bash, not an awk pipeline.
    for mountpoint in "${mountpoints[@]}"; do
        [[ -n "$mountpoint" ]] || continue

        existing_mountpoint=0
        for existing in "${unique_mountpoints[@]}"; do
            if [[ "$existing" == "$mountpoint" ]]; then
                existing_mountpoint=1
                break
            fi
        done

        if (( existing_mountpoint == 0 )); then
            unique_mountpoints+=("$mountpoint")
        fi
    done

    mountpoints=("${unique_mountpoints[@]}")

    if (( ${#mountpoints[@]} > 0 )); then
        for mountpoint in "${mountpoints[@]}"; do
            if [[ "$mountpoint" == "$BACKUP_AGBOOT_DEFAULT_MOUNT" ]]; then
                BACKUP_AGBOOT_MOUNT="$mountpoint"
                break
            fi
        done

        if [[ -z "$BACKUP_AGBOOT_MOUNT" ]]; then
            BACKUP_AGBOOT_MOUNT="${mountpoints[0]}"
        fi

        if (( ${#mountpoints[@]} > 1 )); then
            warn "AGBOOT has multiple mount points: ${mountpoints[*]}"
            warn "Using existing mount point: $BACKUP_AGBOOT_MOUNT"
        else
            msg "AGBOOT is already mounted at: $BACKUP_AGBOOT_MOUNT"
        fi
    else
        msg "AGBOOT found but is not mounted."

        if mountpoint -q "$BACKUP_AGBOOT_DEFAULT_MOUNT"; then
            backup_fatal "The default AGBOOT mount point is already in use."
        fi

        sudo mkdir -p -- "$BACKUP_AGBOOT_DEFAULT_MOUNT" \
            || backup_fatal "Failed to create AGBOOT mount point."

        sudo mount "$device" "$BACKUP_AGBOOT_DEFAULT_MOUNT" \
            || backup_fatal "Failed to mount AGBOOT."

        BACKUP_AGBOOT_MOUNT="$BACKUP_AGBOOT_DEFAULT_MOUNT"
        BACKUP_AGBOOT_MOUNTED_BY_MODULE=1

        trap 'backup_close_devices' EXIT
        success "AGBOOT mounted."
    fi

    [[ "$BACKUP_AGBOOT_MOUNT" != "/" ]] \
        || backup_fatal "Refusing to use the system root as the AGBOOT mount point."

    BACKUP_ROOT="$BACKUP_AGBOOT_MOUNT"
    BACKUP_SUDO=(sudo)
}


prepare_backup_directory(){
    BACKUP_DIRECTORY="$BACKUP_ROOT/$BACKUP_CONFIG_NAME"

    # Refuse unexpected destination paths before removing existing data.
    [[ "$BACKUP_DIRECTORY" == "$BACKUP_LOCAL_ROOT/$BACKUP_CONFIG_NAME" ||
       ( -n "$BACKUP_AGBOOT_MOUNT" &&
         "$BACKUP_DIRECTORY" == "$BACKUP_AGBOOT_MOUNT/$BACKUP_CONFIG_NAME" ) ]] \
        || backup_fatal "Refusing unexpected backup destination: $BACKUP_DIRECTORY"

    if [[ -e "$BACKUP_DIRECTORY" || -L "$BACKUP_DIRECTORY" ]]; then
        msg "Removing previous backup: $BACKUP_DIRECTORY"

        "${BACKUP_SUDO[@]}" rm -rf -- "$BACKUP_DIRECTORY" \
            || backup_fatal "Failed to remove previous backup directory."
    fi

    msg "Creating backup directory: $BACKUP_DIRECTORY"

    "${BACKUP_SUDO[@]}" mkdir -p -- "$BACKUP_DIRECTORY" \
        || backup_fatal "Failed to create backup directory: $BACKUP_DIRECTORY"

    [[ -d "$BACKUP_DIRECTORY" && ! -L "$BACKUP_DIRECTORY" ]] \
        || backup_fatal "Backup destination is not a valid directory."

    success "Backup directory prepared: $BACKUP_DIRECTORY"
}


copy_backup_path(){
    local name="$1"
    local source="$2"
    local target="$3"
    local -a priv=("${BACKUP_SUDO[@]}")

    # Protected sources need root as well.
    if [[ ! -r "$source" ]] || { [[ -d "$source" ]] && [[ ! -x "$source" ]]; }; then
        priv=(sudo)
    fi

    "${priv[@]}" mkdir -p -- "$target" \
        || backup_fatal "Failed to create backup target: $target"

    if [[ -d "$source" ]]; then
        "${priv[@]}" cp -a -- "$source/." "$target/" \
            || backup_fatal "Failed to copy directory: $source"

        success "Directory backed up: $name"
    else
        "${priv[@]}" cp -a -- "$source" "$target/" \
            || backup_fatal "Failed to copy file: $source"

        success "File backed up: $name"
    fi
}


copy_configuration_files(){
    local name
    local source
    local target

    BACKUP_COPIED=()

    msg "Starting configuration backup."

    for name in "${!BACKUP_PATHS[@]}"; do
        source="${BACKUP_PATHS[$name]}"
        target="$BACKUP_DIRECTORY/$name"

        if [[ ! -e "$source" ]]; then
            warn "Configuration path not found; skipping: $source"
            continue
        fi

        msg "Backing up: $source"

        copy_backup_path "$name" "$source" "$target"

        BACKUP_COPIED+=("$name")
    done

    (( ${#BACKUP_COPIED[@]} > 0 )) \
        || warn "No configuration paths were backed up."
}


verify_backup_path(){
    local source="$1"
    local target="$2"

    if [[ -d "$source" ]]; then
        [[ -d "$target" ]] \
            || backup_fatal "Backup directory verification failed: $target"

        sudo diff -qr --no-dereference "$source" "$target" >/dev/null \
            || backup_fatal "Backup directory contents differ: $source"
    else
        [[ -f "$target/$(basename "$source")" ]] \
            || backup_fatal "Backup file verification failed: $target"

        sudo cmp -s -- "$source" "$target/$(basename "$source")" \
            || backup_fatal "Backup file contents differ: $source"
    fi
}


verify_configuration_backup(){
    local name

    (( ${#BACKUP_COPIED[@]} > 0 )) || return 0

    msg "Verifying configuration backup..."

    # Flush and drop caches so the comparison reads the copies back from the
    # device instead of from memory.
    sync

    sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' \
        || backup_fatal "Failed to drop caches before verification."

    for name in "${BACKUP_COPIED[@]}"; do
        verify_backup_path \
            "${BACKUP_PATHS[$name]}" \
            "$BACKUP_DIRECTORY/$name"

        success "Backup verified: $name"
    done
}


close_backup_destination(){
    msg "Closing backup destination..."

    backup_close_devices

    # Resources were closed successfully; disable the EXIT trap.
    trap - EXIT

    BACKUP_AGBOOT_MOUNT=""

    success "Backup destination closed."
}


backup_configuration_files(){
    check_backup_requirements
    load_backup_configuration
    check_backup_configuration

    find_backup_destination
    prepare_backup_directory
    copy_configuration_files
    verify_configuration_backup
    close_backup_destination

    success "Configuration backup completed."
    msg "Backup location: $BACKUP_DIRECTORY"
}