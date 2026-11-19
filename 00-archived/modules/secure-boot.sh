#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Secure Boot
# ==============================================================================
# /modules/secure-boot.sh

# ==============================================================================
# Logging / Errors
# ==============================================================================

msg(){
    printf '[*] %s\n' "$1"
}

success(){
    printf '[+] %s\n' "$1"
}

warn(){
    printf '[!] %s\n' "$1"
}

fatal(){
    local message="$1"

    printf '[FATAL] %s\n' "$message"

    cleanup_agkeys || true

    exit 1
}


# ==============================================================================
# Initialization
# ==============================================================================

init_secure_boot(){
    readonly SB_EFIVARS="/sys/firmware/efi/efivars"

    readonly SB_BOOT_MOUNT="/run/archiso/bootmnt"
    readonly SB_CMDLINE="/proc/cmdline"

    readonly SB_AGKEYS_LABEL="AGKEYS"
    readonly SB_AGBOOT_LABEL="AGBOOT"

    readonly SB_AGKEYS_MOUNT="/run/archguard/agkeys"
    readonly SB_AGBOOT_MOUNT="/run/archguard/agboot"

    readonly SB_AGKEYS_MAPPER="archguard-agkeys"

    readonly SB_SBCTL_DIR="/var/lib/sbctl"
    readonly SB_AGKEYS_SBCTL="$SB_AGKEYS_MOUNT/sbctl"

    readonly SB_INSTALLER="archguard-install.sh"

    readonly SB_STATE_SETUP=10
    readonly SB_STATE_ENABLED=20
    readonly SB_STATE_DISABLED=30

    AG_USB_DISK=""
    AG_AGKEYS_PART=""
    AG_AGBOOT_PART=""
}


# ==============================================================================
# Secure Boot State
# ==============================================================================

read_efi_variable(){
    local variable="$1"
    local file="$SB_EFIVARS/$variable-8be4df61-93ca-11d2-aa0d-00e098032b8c"

    [[ -f "$file" ]] \
        || fatal "UEFI variable not found: $variable"

    od -An -t u1 -j4 -N1 "$file" |
        tr -d ' '
}

check_secure_boot(){
    local secure_boot
    local setup_mode

    [[ -d "$SB_EFIVARS" ]] \
        || fatal "UEFI efivars are not available."

    secure_boot=$(read_efi_variable "SecureBoot") \
        || fatal "Failed to read SecureBoot state."

    setup_mode=$(read_efi_variable "SetupMode") \
        || fatal "Failed to read SetupMode state."

    case "$setup_mode:$secure_boot" in
        1:0)
            msg "Secure Boot state: Setup Mode"
            return "$SB_STATE_SETUP"
            ;;

        0:1)
            msg "Secure Boot state: Secure Boot enabled"
            return "$SB_STATE_ENABLED"
            ;;

        0:0)
            msg "Secure Boot state: User Mode, Secure Boot disabled"
            return "$SB_STATE_DISABLED"
            ;;

        *)
            warn \
                "Unexpected Secure Boot state: SetupMode=$setup_mode SecureBoot=$secure_boot"
            return
            ;;
    esac
}


# ==============================================================================
# ArchISO Boot Source Discovery
# ==============================================================================

cmdline_value(){
    local parameter="$1"

    sed -nE \
        "s/(^|.*[[:space:]])${parameter}=([^[:space:]]*).*/\2/p" \
        "$SB_CMDLINE"
}

find_boot_source(){
    local source=""
    local value=""

    if mountpoint -q "$SB_BOOT_MOUNT" 2>/dev/null; then
        source=$(findmnt -nro SOURCE "$SB_BOOT_MOUNT") || source=""
    fi

    if [[ -z "$source" ]]; then
        value=$(cmdline_value "archisosearchuuid")

        if [[ -n "$value" ]]; then
            source=$(findfs "UUID=$value" 2>/dev/null) || source=""
        fi
    fi

    if [[ -z "$source" ]]; then
        value=$(cmdline_value "archisolabel")

        if [[ -n "$value" ]]; then
            source=$(findfs "LABEL=$value" 2>/dev/null) || source=""
        fi
    fi

    if [[ -z "$source" ]]; then
        source=$(cmdline_value "archisodevice")
    fi

    printf '%s\n' "$source"
}


# ==============================================================================
# ArchGuard USB Discovery
# ==============================================================================

find_archguard_usb(){
    local boot_source
    local parent
    local disk

    boot_source=$(find_boot_source)

    [[ -n "$boot_source" ]] \
        || fatal \
            "Could not determine the ArchISO boot source."

    [[ -b "$boot_source" ]] \
        || fatal \
            "ArchISO boot source is not a block device: $boot_source"

    parent=$(lsblk -no PKNAME "$boot_source") \
        || fatal \
            "Failed to determine the parent disk of $boot_source."

    [[ -n "$parent" ]] \
        || fatal \
            "Failed to determine the parent disk of $boot_source."

    disk="/dev/$parent"

    lsblk -dnro TRAN,TYPE "$disk" |
        awk '
            $1 == "usb" && $2 == "disk" {
                found = 1
            }

            END {
                exit !found
            }
        ' \
        || fatal \
            "ArchGuard boot device is not detected as a USB disk: $disk"

    AG_USB_DISK="$disk"

    success "ArchGuard USB: $AG_USB_DISK"
}


# ==============================================================================
# ArchGuard Partition Discovery
# ==============================================================================

find_partition_by_label(){
    local disk="$1"
    local label="$2"

    lsblk -lnpo NAME,LABEL,TYPE "$disk" |
        awk -v label="$label" '$2 == label && $3 == "part" { print $1; exit }'
}

find_agkeys_partition(){
    AG_AGKEYS_PART=$(find_partition_by_label \
        "$AG_USB_DISK" \
        "$SB_AGKEYS_LABEL")

    [[ -b "$AG_AGKEYS_PART" ]] \
        || fatal \
            "AGKEYS partition not found on $AG_USB_DISK (label: $SB_AGKEYS_LABEL)"

    success "AGKEYS: $AG_AGKEYS_PART"
}

find_agboot_partition(){
    AG_AGBOOT_PART=$(find_partition_by_label \
        "$AG_USB_DISK" \
        "$SB_AGBOOT_LABEL")

    [[ -b "$AG_AGBOOT_PART" ]] \
        || fatal \
            "AGBOOT partition not found on $AG_USB_DISK (label: $SB_AGBOOT_LABEL)"

    success "AGBOOT: $AG_AGBOOT_PART"
}


# ==============================================================================
# AGKEYS
# ==============================================================================

cleanup_agkeys(){
    unlink_sbctl_keys || true

    mountpoint -q "$SB_AGKEYS_MOUNT" 2>/dev/null \
        && umount "$SB_AGKEYS_MOUNT" 2>/dev/null || true

    cryptsetup status "$SB_AGKEYS_MAPPER" >/dev/null 2>&1 \
        && cryptsetup close "$SB_AGKEYS_MAPPER" 2>/dev/null || true
}

unlock_agkeys(){
    msg "Unlocking AGKEYS..."

    mkdir -p "$SB_AGKEYS_MOUNT" \
        || fatal "Failed to create AGKEYS mount point."

    cryptsetup luksOpen \
        "$AG_AGKEYS_PART" \
        "$SB_AGKEYS_MAPPER" \
        || fatal "Failed to unlock AGKEYS."

    trap 'cleanup_agkeys' EXIT

    mount \
        "/dev/mapper/$SB_AGKEYS_MAPPER" \
        "$SB_AGKEYS_MOUNT" \
        || fatal "Failed to mount AGKEYS."

    success "AGKEYS unlocked."
}

close_agkeys(){
    unlink_sbctl_keys

    if mountpoint -q "$SB_AGKEYS_MOUNT"; then
        umount "$SB_AGKEYS_MOUNT" \
            || fatal "Failed to unmount AGKEYS."
    fi

    if cryptsetup status "$SB_AGKEYS_MAPPER" >/dev/null 2>&1; then
        cryptsetup close "$SB_AGKEYS_MAPPER" \
            || fatal "Failed to close AGKEYS."
    fi

    trap - EXIT
}

link_sbctl_keys(){
    local file

    for file in \
        GUID \
        keys/PK/PK.key   keys/PK/PK.pem \
        keys/KEK/KEK.key keys/KEK/KEK.pem \
        keys/db/db.key   keys/db/db.pem
    do
        [[ -f "$SB_AGKEYS_SBCTL/$file" ]] \
            || fatal "Missing in AGKEYS: sbctl/$file"
    done

    msg "Removing existing sbctl directory: $SB_SBCTL_DIR"

    rm -rf -- "$SB_SBCTL_DIR" \
        || fatal "Failed to remove existing $SB_SBCTL_DIR"

    if [[ -e "$SB_SBCTL_DIR" && ! -L "$SB_SBCTL_DIR" ]]; then
        fatal "$SB_SBCTL_DIR already exists and is not a symlink."
    fi

    msg "Linking $SB_SBCTL_DIR -> $SB_AGKEYS_SBCTL"

    mkdir -p "$(dirname "$SB_SBCTL_DIR")" \
        || fatal "Failed to create $(dirname "$SB_SBCTL_DIR")"

    ln -sfn "$SB_AGKEYS_SBCTL" "$SB_SBCTL_DIR" \
        || fatal "Failed to link $SB_SBCTL_DIR"
}

unlink_sbctl_keys(){
    if [[ -L "$SB_SBCTL_DIR" ]]; then
        rm -f -- "$SB_SBCTL_DIR"
    fi
}


# ==============================================================================
# Secure Boot Enrollment
# ==============================================================================

enroll_secure_boot(){
    link_sbctl_keys

    msg "Checking Secure Boot status..."

    sbctl status

    msg "Enrolling ArchGuard Secure Boot keys..."

    sbctl enroll-keys \
        --yes-this-might-brick-my-machine \
        || fatal "sbctl enroll-keys failed."

    unlink_sbctl_keys

    msg "Enrolled keys:"

    sbctl list-enrolled-keys \
        || fatal "Failed to list enrolled Secure Boot keys."
}

verify_enrollment(){
    local setup_mode

    setup_mode=$(read_efi_variable "SetupMode") \
        || fatal "Failed to read SetupMode state."

    [[ "$setup_mode" == "0" ]] \
        || fatal "Enrollment failed: firmware is still in Setup Mode."

    success "ArchGuard Secure Boot keys enrolled."
}


# ==============================================================================
# AGBOOT
# ==============================================================================

mount_agboot(){
    msg "Mounting AGBOOT..."

    mkdir -p "$SB_AGBOOT_MOUNT" \
        || fatal "Failed to create AGBOOT mount point."

    mount \
        "$AG_AGBOOT_PART" \
        "$SB_AGBOOT_MOUNT" \
        || fatal "Failed to mount AGBOOT."

    local mounted_source
    mounted_source=$(findmnt -nro SOURCE --target "$SB_AGBOOT_MOUNT") \
        || fatal "Failed to verify AGBOOT mount."

    [[ "$(readlink -f "$mounted_source")" == "$(readlink -f "$AG_AGBOOT_PART")" ]] \
        || fatal "AGBOOT mount source does not match the expected partition."

    [[ -f "$SB_AGBOOT_MOUNT/$SB_INSTALLER" ]] \
        || fatal "Installer not found: $SB_AGBOOT_MOUNT/$SB_INSTALLER"

    success "AGBOOT mounted and verified."
}

launch_installer(){
    msg "Launching ArchGuard installer..."

    exec bash "$SB_AGBOOT_MOUNT/$SB_INSTALLER"
}


# ==============================================================================
# Firmware Interaction
# ==============================================================================

reboot_to_firmware(){
    read -r -p 'Press ENTER to reboot to UEFI Setup... ' _ \
        || fatal "No terminal available to continue."

    systemctl reboot --firmware-setup 2>/dev/null \
        || systemctl reboot \
        || fatal "Failed to reboot."
}

secure_boot_reboot(){
    printf '\n'
    printf '%s\n' '================================================'
    printf '%s\n' ' Secure Boot configuration required'
    printf '%s\n' '================================================'
    printf '\n'

    printf '%s\n' \
        'ArchGuard Secure Boot keys have been enrolled.'
    printf '\n'

    printf '%s\n' \
        'The system will now reboot into UEFI firmware.'
    printf '\n'

    printf '%s\n' \
        'Please check/configure:'
    printf '\n'

    printf '%s\n' \
        '  - USB Boot: Enabled' \
        '  - Secure Boot: Enabled' \
        '  - Administrator password: Set' \
        '  - Boot order: Set your main / OS disk as the default' \
        '  - Other required firmware settings'
    printf '\n'

    printf '%s\n' \
        'After saving the changes, boot from the ArchGuard USB again.'
    printf '\n'

    printf '%s\n' '================================================'

    reboot_to_firmware
}

secure_boot_disabled(){
    printf '\n'
    printf '%s\n' '================================================'
    printf '%s\n' ' ArchGuard - Secure Boot is disabled'
    printf '%s\n' '================================================'
    printf '\n'

    printf '%s\n' \
        'ArchGuard cannot continue while Secure Boot is disabled.'
    printf '\n'

    printf '%s\n' \
        'Enter UEFI Setup, enable Secure Boot, save the' \
        'changes, and boot the ArchGuard USB again.'
    printf '\n'

    printf '%s\n' \
        'If Secure Boot cannot be enabled, or this USB is' \
        'refused afterwards, remove the existing Secure Boot' \
        'keys to return to Setup Mode and boot the USB again.'
    printf '\n'

    reboot_to_firmware
}

secure_boot_recovery(){
    printf '\n'
    printf '%s\n' '================================================'
    printf '%s\n' ' ArchGuard - Secure Boot Configuration Error'
    printf '%s\n' '================================================'
    printf '\n'

    printf '%s\n' \
        'ArchGuard cannot continue because the current' \
        'UEFI Secure Boot configuration is unexpected.'
    printf '\n'

    printf '%s\n' \
        'Enter UEFI Setup and remove the existing' \
        'Secure Boot keys/certificates.'
    printf '\n'

    printf '%s\n' \
        'Leave Secure Boot in Setup Mode, save the' \
        'changes, and boot the ArchGuard USB again.'
    printf '\n'

    reboot_to_firmware
}


# ==============================================================================
# Main
# ==============================================================================

run_secure_boot(){
    init_secure_boot

    local state=0

    check_secure_boot || state=$?

    case "$state" in

        "$SB_STATE_SETUP")
            find_archguard_usb
            find_agkeys_partition

            unlock_agkeys
            enroll_secure_boot
            verify_enrollment
            close_agkeys

            secure_boot_reboot
            ;;

        "$SB_STATE_ENABLED")
            find_archguard_usb
            find_agboot_partition

            mount_agboot
            launch_installer
            ;;

        "$SB_STATE_DISABLED")
            secure_boot_disabled
            ;;

        *)
            secure_boot_recovery
            ;;

    esac
}


# ==============================================================================
# Entry Point
# ==============================================================================

run_secure_boot