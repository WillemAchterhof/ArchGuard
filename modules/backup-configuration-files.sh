
#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Configuration Backup
# ==============================================================================
# /modules/backup-configuration-files.sh
#
# Responsibilities:
#   - Validate the commands required for configuration backup
#   - Load configured paths from configs/backup-configuration-files.sh
#   - Detect the AGBOOT filesystem and mount it when necessary
#   - Fall back to ~/Backup when AGBOOT is unavailable
#   - Replace the previous backup-configs directory with a fresh directory
#   - Copy configured files and directories while preserving attributes
#   - Verify copied files and directories against their sources
#   - Unmount AGBOOT only if this module mounted it
#
# Required globals:
#   DIR_MAIN
#
# Required functions:
#   msg  success  warn  fatal  require_command  packages_install  cleanup
#
# Result:
#   BACKUP_DIRECTORY -> location of the configuration backup
#
# Configuration:
#   configs/backup-configuration-files.sh
#   Must define BACKUP_PATHS using `declare -gA BACKUP_PATHS=(...)`.
#
# Backup destination:
#   AGBOOT: <AGBOOT mount point>/backup-configs
#   Fallback: ~/Backup/backup-configs
#
# Notes:
#   - Only the backup-configs directory is replaced.
#   - Missing configured paths are skipped with a warning.
#   - Copy or verification failures abort the backup.
#   - AGBOOT is unmounted only if this module mounted it.
#   - An EXIT trap closes module-mounted AGBOOT after unexpected failures.
# ==============================================================================

readonly BACKUP_CONFIG_NAME="backup-configs"
readonly BACKUP_CONFIG_FILE="$DIR_MAIN/configs/backup-configuration-files.sh"
readonly BACKUP_LOCAL_ROOT="$HOME/Backup"
readonly BACKUP_AGBOOT_LABEL="AGBOOT"
readonly BACKUP_AGBOOT_DEFAULT_MOUNT="/run/archguard/agboot"

BACKUP_DIRECTORY=""
BACKUP_ROOT=""
BACKUP_AGBOOT_MOUNT=""
BACKUP_AGBOOT_MOUNTED_BY_MODULE=0
BACKUP_SUDO=()
BACKUP_COPIED=()

# ==============================================================================
# Requirements
# ==============================================================================

install_backup_requirements() {
    packages_install \
        util-linux \
        gawk \
        coreutils \
        diffutils
}


check_backup_requirements() {
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
        awk \
        sudo
    do
        require_command "$command"
    done

    [[ -f "$BACKUP_CONFIG_FILE" ]] \
        || fatal "Backup configuration not found: $BACKUP_CONFIG_FILE"

    [[ -r "$BACKUP_CONFIG_FILE" ]] \
        || fatal "Backup configuration is not readable: $BACKUP_CONFIG_FILE"
}


# ==============================================================================
# Load and Validate Backup Configuration
# ==============================================================================

load_backup_configuration() {
    # shellcheck disable=SC1090
    source "$BACKUP_CONFIG_FILE"
}


check_backup_configuration() {
    local declaration

    declaration="$(declare -p BACKUP_PATHS 2>/dev/null)" \
        || fatal "BACKUP_PATHS is not defined in the configuration file."

    [[ "$declaration" == "declare -A"* ]] \
        || fatal "BACKUP_PATHS must be an associative array."

    (( ${#BACKUP_PATHS[@]} > 0 )) \
        || fatal "BACKUP_PATHS is empty."
}


# ==============================================================================
# AGBOOT Cleanup
# ==============================================================================

# Unmount AGBOOT only when this module mounted it.
# Safe to call repeatedly, including from the EXIT trap.
backup_close_devices() {
    if (( BACKUP_AGBOOT_MOUNTED_BY_MODULE == 1 )); then
        if mountpoint -q "$BACKUP_AGBOOT_MOUNT" 2>/dev/null; then
            sudo sync \
                || warn "Failed to flush AGBOOT filesystem changes."

            sudo umount "$BACKUP_AGBOOT_MOUNT" \
                || warn "Failed to unmount AGBOOT: $BACKUP_AGBOOT_MOUNT"
        fi

        if ! mountpoint -q "$BACKUP_AGBOOT_MOUNT" 2>/dev/null; then
            sudo rmdir "$BACKUP_AGBOOT_MOUNT" 2>/dev/null || true
            BACKUP_AGBOOT_MOUNTED_BY_MODULE=0
        else
            warn "AGBOOT remains mounted: $BACKUP_AGBOOT_MOUNT"
        fi
    fi
}


backup_cleanup() {
    backup_close_devices
    cleanup
}


backup_fatal() {
    local message="$1"

    printf '[FATAL] %s\n' "$message" >&2

    trap - EXIT
    backup_cleanup

    exit 1
}


# ==============================================================================
# Find Backup Destination
# ==============================================================================

find_backup_destination() {
    local device
    local -a devices=()
    local -a mountpoints=()

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
        || backup_fatal "Multiple filesystems labelled AGBOOT found."

    device="${devices[0]}"

    mapfile -t mountpoints < <(
        findmnt -rn -S "$device" -o TARGET
    )

    (( ${#mountpoints[@]} <= 1 )) \
        || backup_fatal "AGBOOT filesystem has multiple mount points."

    if (( ${#mountpoints[@]} == 1 )); then
        BACKUP_AGBOOT_MOUNT="${mountpoints[0]}"

        [[ "$BACKUP_AGBOOT_MOUNT" != "/" ]] \
            || backup_fatal "Refusing to use the system root as the AGBOOT mount point."

        msg "AGBOOT is already mounted at: $BACKUP_AGBOOT_MOUNT"
    else
        BACKUP_AGBOOT_MOUNT="$BACKUP_AGBOOT_DEFAULT_MOUNT"

        msg "AGBOOT found but is not mounted."
        msg "Mounting AGBOOT at: $BACKUP_AGBOOT_MOUNT"

        sudo mkdir -p -- "$BACKUP_AGBOOT_MOUNT" \
            || backup_fatal "Failed to create AGBOOT mount point."

        sudo mount "$device" "$BACKUP_AGBOOT_MOUNT" \
            || backup_fatal "Failed to mount AGBOOT."

        BACKUP_AGBOOT_MOUNTED_BY_MODULE=1

        # Close AGBOOT if an unexpected exit occurs.
        trap 'backup_close_devices' EXIT

        success "AGBOOT mounted successfully."
    fi

    # AGBOOT may be root-owned, so destination operations use sudo.
    BACKUP_ROOT="$BACKUP_AGBOOT_MOUNT"
    BACKUP_SUDO=(sudo)
}


# ==============================================================================
# Prepare Backup Directory
# ==============================================================================

prepare_backup_directory() {
    BACKUP_DIRECTORY="$BACKUP_ROOT/$BACKUP_CONFIG_NAME"

    # Refuse unexpected destinations before removing existing data.
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
        || backup_fatal "Failed to create backup directory."

    [[ -d "$BACKUP_DIRECTORY" && ! -L "$BACKUP_DIRECTORY" ]] \
        || backup_fatal "Backup destination is not a valid directory."

    success "Backup directory prepared: $BACKUP_DIRECTORY"
}


# ==============================================================================
# Copy Configuration Paths
# ==============================================================================

copy_backup_path() {
    local name="$1"
    local source="$2"
    local target="$3"
    local -a copy_priv=("${BACKUP_SUDO[@]}")

    # Escalate only when the source requires elevated read permissions.
    if [[ ! -r "$source" ]] ||
       { [[ -d "$source" ]] && [[ ! -x "$source" ]]; }; then
        copy_priv=(sudo)
    fi

    # Keep local destination directories owned by the user when possible.
    "${BACKUP_SUDO[@]}" mkdir -p -- "$target" \
        || backup_fatal "Failed to create backup target: $target"

    if [[ -d "$source" ]]; then
        "${copy_priv[@]}" cp -a -- "$source/." "$target/" \
            || backup_fatal "Failed to copy directory: $source"

        success "Directory backed up: $name"
    else
        "${copy_priv[@]}" cp -a -- "$source" "$target/" \
            || backup_fatal "Failed to copy file: $source"

        success "File backed up: $name"
    fi
}


copy_configuration_files() {
    local name
    local source
    local target

    BACKUP_COPIED=()

    msg "Starting configuration backup."

    for name in "${!BACKUP_PATHS[@]}"; do
        source="${BACKUP_PATHS[$name]}"
        target="$BACKUP_DIRECTORY/$name"

        if [[ ! -e "$source" && ! -L "$source" ]]; then
            warn "Configuration path not found; skipping: $source"
            continue
        fi

        msg "Backing up: $source"

        copy_backup_path "$name" "$source" "$target"

        BACKUP_COPIED+=("$name")
    done

    if (( ${#BACKUP_COPIED[@]} == 0 )); then
        warn "No configuration paths were backed up."
    fi
}


# ==============================================================================
# Verify Backup
# ==============================================================================

verify_backup_path() {
    local source="$1"
    local target="$2"
    local -a verify_priv=("${BACKUP_SUDO[@]}")

    # Protected source paths may need elevated read permissions.
    if [[ ! -r "$source" ]] ||
       { [[ -d "$source" ]] && [[ ! -x "$source" ]]; }; then
        verify_priv=(sudo)
    fi

    if [[ -d "$source" ]]; then
        [[ -d "$target" ]] \
            || backup_fatal "Backup directory verification failed: $target"

        "${verify_priv[@]}" diff -qr -- "$source" "$target" >/dev/null \
            || backup_fatal "Backup directory contents differ: $source"
    elif [[ -L "$source" ]]; then
        [[ -L "$target/$(basename "$source")" ]] \
            || backup_fatal "Backup symlink verification failed: $source"

        [[ "$(readlink -- "$source")" == \
           "$(readlink -- "$target/$(basename "$source")")" ]] \
            || backup_fatal "Backup symlink target differs: $source"
    else
        [[ -f "$target/$(basename "$source")" ]] \
            || backup_fatal "Backup file verification failed: $target"

        "${verify_priv[@]}" cmp -s -- \
            "$source" "$target/$(basename "$source")" \
            || backup_fatal "Backup file contents differ: $source"
    fi
}


verify_configuration_backup() {
    local name

    (( ${#BACKUP_COPIED[@]} > 0 )) || return 0

    msg "Flushing filesystem changes before verification."

    sync || backup_fatal "Failed to flush filesystem changes."

    msg "Verifying configuration backup."

    for name in "${BACKUP_COPIED[@]}"; do
        verify_backup_path \
            "${BACKUP_PATHS[$name]}" \
            "$BACKUP_DIRECTORY/$name"

        success "Backup verified: $name"
    done
}


# ==============================================================================
# Close Backup Destination
# ==============================================================================

close_backup_destination() {
    msg "Closing backup destination."

    backup_close_devices

    if (( BACKUP_AGBOOT_MOUNTED_BY_MODULE == 1 )); then
        backup_fatal "Unable to safely close AGBOOT."
    fi

    trap - EXIT

    BACKUP_AGBOOT_MOUNT=""
    success "Backup destination closed."
}


# ==============================================================================
# Main Backup Function
# ==============================================================================

backup_configuration_files() {
    check_backup_requirements
    install_backup_requirements

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
