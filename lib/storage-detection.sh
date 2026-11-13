
#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Storage Detection
# ==============================================================================
# /lib/storage-detection.sh
#
# Responsibilities:
#   - Detect available physical disks
#   - Detect the Arch installer USB
#
# Populates:
#   - AG_HW_DISKS
#   - AG_HW_USB_DEVICE
#
# Does NOT:
#   - Select installation disks
#   - Partition or format disks
#   - Mount filesystems
# ==============================================================================

# ------------------------------------------------------------------------------
# Disk discovery
# ------------------------------------------------------------------------------

detect_disks()
{
    local disks=()
    local disk

    while IFS= read -r disk; do
        [[ -n "$disk" ]] || continue
        disks+=("$disk")
    done < <(
        lsblk -dnpo NAME,TYPE |
            awk '$2 == "disk" { print $1 }'
    )

    AG_HW_DISKS="$(IFS=,; printf '%s' "${disks[*]:-none}")"
}

# ------------------------------------------------------------------------------
# Installer USB detection
# ------------------------------------------------------------------------------

detect_usb_device()
{
    local dev
    local label
    local type
    local parent

    AG_HW_USB_DEVICE=""

    while read -r dev label type; do

        [[ "$label" == ARCH* ]] || continue
        [[ "$type" == "iso9660" ]] || continue

        parent="$(get_parent_disk "$dev" 2>/dev/null || true)"

        if [[ -z "$parent" ]]; then
            warn "Unable to resolve installer USB: $dev"
            return 1
        fi

        AG_HW_USB_DEVICE="$parent"

        success "Installer USB detected: $AG_HW_USB_DEVICE"

        return 0

    done < <(
        blkid -o export 2>/dev/null |
            awk '
                /^$/ {
                    dev=""
                    label=""
                    type=""
                }

                /^DEVNAME=/ {
                    dev=$0
                    sub("DEVNAME=", "", dev)
                }

                /^LABEL=/ {
                    label=$0
                    sub("LABEL=", "", label)
                }

                /^TYPE=/ {
                    type=$0
                    sub("TYPE=", "", type)
                    print dev, label, type
                }
            '
    )

    warn "Arch installer USB could not be identified."

    return 1
}

# ------------------------------------------------------------------------------
# Storage detection controller
# ------------------------------------------------------------------------------

detect_storage()
{
    require_command lsblk
    require_command blkid

    detect_disks
    detect_usb_device
}
