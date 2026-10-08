#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Secure Boot
# ==============================================================================
# /modules/secure-boot.sh
#
# Responsibilities:
#   - Determine Secure Boot / UEFI Setup Mode
#   - Identify the ArchGuard USB that booted the ISO
#   - Unlock AGKEYS when in Setup Mode
#   - Enroll ArchGuard Secure Boot keys
#   - Reboot after enrollment
#   - Continue to AGBOOT when Secure Boot is enabled
#   - Provide UEFI instructions when Secure Boot is disabled or unexpected
#
# States (SetupMode:SecureBoot):
#   1:0  Setup Mode             -> enroll keys, reboot to UEFI
#   0:1  User Mode, enabled     -> launch installer
#   0:0  User Mode, disabled    -> stop, ask user to enable Secure Boot
#   else unexpected             -> stop, ask user to reset to Setup Mode
#
# Partitions are located by filesystem / LUKS label:
#   AGKEYS -> LUKS label
#   AGBOOT -> filesystem label
#
# AGKEYS layout:
#   sbctl/GUID
#   sbctl/keys/{PK,KEK,db}/{PK,KEK,db}.{key,pem}
#
# Only ArchGuard keys are enrolled (no Microsoft / OEM keys).
# ==============================================================================


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

    # --------------------------------------------------------------------------
    # Method 1: ArchISO boot mount
    # --------------------------------------------------------------------------

    if mountpoint -q "$SB_BOOT_MOUNT" 2>/dev/null; then
        source=$(findmnt -nro SOURCE "$SB_BOOT_MOUNT") || source=""
    fi

    # --------------------------------------------------------------------------
    # Method 2: ArchISO search UUID
    # --------------------------------------------------------------------------

    if [[ -z "$source" ]]; then
        value=$(cmdline_value "archisosearchuuid")

        if [[ -n "$value" ]]; then
            source=$(findfs "UUID=$value" 2>/dev/null) || source=""
        fi
    fi

    # --------------------------------------------------------------------------
    # Method 3: ArchISO filesystem label
    # --------------------------------------------------------------------------

    if [[ -z "$source" ]]; then
        value=$(cmdline_value "archisolabel")

        if [[ -n "$value" ]]; then
            source=$(findfs "LABEL=$value" 2>/dev/null) || source=""
        fi
    fi

    # --------------------------------------------------------------------------
    # Method 4: ArchISO device parameter
    # --------------------------------------------------------------------------

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
        || fatal "Could not determine the ArchISO boot source."

    [[ -b "$boot_source" ]] \
        || fatal "ArchISO boot source is not a block device: $boot_source"

    parent=$(lsblk -no PKNAME "$boot_source") \
        || fatal "Failed to determine the parent disk of $boot_source."

    [[ -n "$parent" ]] \
        || fatal "Failed to determine the parent disk of $boot_source."

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

    lsblk -lnpo NAME,LABEL "$disk" |
        awk -v label="$label" '$2 == label { print $1; exit }'
}

find_archguard_partitions(){
    AG_AGKEYS_PART=$(find_partition_by_label \
        "$AG_USB_DISK" \
        "$SB_AGKEYS_LABEL")

    AG_AGBOOT_PART=$(find_partition_by_label \
        "$AG_USB_DISK" \
        "$SB_AGBOOT_LABEL")

    [[ -b "$AG_AGKEYS_PART" ]] \
        || fatal \
            "AGKEYS partition not found on $AG_USB_DISK (label: $SB_AGKEYS_LABEL)"

    [[ -b "$AG_AGBOOT_PART" ]] \
        || fatal \
            "AGBOOT partition not found on $AG_USB_DISK (label: $SB_AGBOOT_LABEL)"

    success "AGKEYS: $AG_AGKEYS_PART"
    success "AGBOOT: $AG_AGBOOT_PART"
}


# ==============================================================================
# AGKEYS
# ==============================================================================

cleanup_agkeys(){
    if mountpoint -q "$SB_AGKEYS_MOUNT" 2>/dev/null; then
        umount "$SB_AGKEYS_MOUNT" 2>/dev/null || true
    fi

    if cryptsetup status "$SB_AGKEYS_MAPPER" >/dev/null 2>&1; then
        cryptsetup close "$SB_AGKEYS_MAPPER" 2>/dev/null || true
    fi
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
    if mountpoint -q "$SB_AGKEYS_MOUNT"; then
        umount "$SB_AGKEYS_MOUNT" \
            || fatal "Failed to unmount AGKEYS."
    fi

    if [[ -e "/dev/mapper/$SB_AGKEYS_MAPPER" ]]; then
        cryptsetup close "$SB_AGKEYS_MAPPER" \
            || fatal "Failed to close AGKEYS."
    fi

    trap - EXIT

    success "AGKEYS closed."
}


# ==============================================================================
# sbctl Storage
# ==============================================================================

prepare_sbctl_storage(){
    msg "Linking AGKEYS Secure Boot keys..."

    rm -rf -- /var/lib/sbctl

    ln -s "$SB_AGKEYS_SBCTL" /var/lib/ \
        || fatal "Failed to link AGKEYS sbctl storage."

    success "sbctl is using AGKEYS key storage."
}

# ==============================================================================
# Secure Boot Enrollment
# ==============================================================================

enroll_secure_boot(){
    prepare_sbctl_storage

    msg "Checking Secure Boot status..."

    sbctl status \
        || fatal "Failed to query sbctl status."

    # Custom keys only:
    #   - no Microsoft keys
    #   - no OEM keys
    #
    # --yes-this-might-brick-my-machine only acknowledges sbctl's warning.
    msg "Enrolling ArchGuard Secure Boot keys..."

    sbctl enroll-keys \
        --yes-this-might-brick-my-machine \
        || fatal "sbctl enroll-keys failed."

    msg "Enrolled keys:"

    sbctl list-enrolled-keys \
        || fatal "Failed to list enrolled Secure Boot keys."

    success "ArchGuard Secure Boot keys enrolled."
}

verify_enrollment(){
    local setup_mode
    local secure_boot

    setup_mode=$(read_efi_variable "SetupMode") \
        || fatal "Failed to read SetupMode state."

    secure_boot=$(read_efi_variable "SecureBoot") \
        || fatal "Failed to read SecureBoot state."

    [[ "$setup_mode" == "0" ]] \
        || fatal "Enrollment failed: firmware is still in Setup Mode."

    success "ArchGuard Secure Boot keys enrolled."

    if [[ "$secure_boot" == "1" ]]; then
        success "Secure Boot is enabled."
    else
        msg "Secure Boot is currently disabled; it must be enabled in UEFI."
    fi
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

    [[ -f "$SB_AGBOOT_MOUNT/$SB_INSTALLER" ]] \
        || fatal \
            "Installer not found: $SB_AGBOOT_MOUNT/$SB_INSTALLER"

    success "AGBOOT mounted."
}

launch_installer(){
    msg "Launching ArchGuard installer..."

    exec bash "$SB_AGBOOT_MOUNT/$SB_INSTALLER"
}


# ==============================================================================
# Firmware Interaction
# ==============================================================================

reboot_to_firmware(){
    if [[ ! -t 0 ]]; then
        fatal "No interactive terminal is available to reboot into UEFI Setup."
    fi

    read -r -p 'Press ENTER to reboot to UEFI Setup... ' _ \
        || fatal "Failed to read confirmation from terminal."

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
            find_archguard_partitions

            unlock_agkeys
            enroll_secure_boot
            verify_enrollment
            close_agkeys

            secure_boot_reboot
            ;;

        "$SB_STATE_ENABLED")
            find_archguard_usb
            find_archguard_partitions

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