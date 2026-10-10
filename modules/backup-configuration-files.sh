
#!/usr/bin/env bash

# ==============================================================================
# AGBOOT USB Check
# ==============================================================================

check_agboot_usb() {
    # Detect AGBOOT and return its mount point.
}

# ==============================================================================
# Backup Destination
# ==============================================================================

get_backup_destination() {
    # Select USB or local fallback.
}

# ==============================================================================
# Prepare Backup Directory
# ==============================================================================

prepare_backup_directory() {
    # Remove the previous backup directory and create an empty one.
}

# ==============================================================================
# Copy Configuration Files
# ==============================================================================

copy_configuration_files() {
    # Copy the selected configuration files.
}

# ==============================================================================
# Main Backup Function
# ==============================================================================

backup_configuration_files() {
    local destination

    destination="$(get_backup_destination)"
    prepare_backup_directory "$destination"
    copy_configuration_files "$destination"
}
