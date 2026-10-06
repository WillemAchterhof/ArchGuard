#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - ISO
# ==============================================================================
# /modules/create-iso.sh
#
# Responsibilities:
#   - Prepare the ArchISO releng profile
#   - Add packages required by the ArchGuard ISO
#   - Install the ArchGuard boot launcher
#   - Build the ISO
#   - Locate the resulting ISO
# ==============================================================================


# ==============================================================================
# Initialization
# ==============================================================================

init_iso(){
    readonly ISO_PROFILE_BASE="/usr/share/archiso/configs/releng"

    readonly ISO_DIR="$DIR_MAIN/build/iso"
    readonly ISO_PROFILE="$ISO_DIR/profile"
    readonly ISO_WORK="$ISO_DIR/work"
    readonly ISO_OUTPUT="$ISO_DIR/output"

    AG_ISO_FILE=""
}


# ==============================================================================
# Requirements
# ==============================================================================

check_iso_requirements(){
    require_command mkarchiso

    [[ -d "$ISO_PROFILE_BASE" ]] \
        || fatal "ArchISO releng profile not found: $ISO_PROFILE_BASE"
}


# ==============================================================================
# Profile Preparation
# ==============================================================================

prepare_iso_profile(){
    msg "Preparing ArchISO profile..."

    rm -rf -- "$ISO_PROFILE"

    mkdir -p "$ISO_DIR" \
        || fatal "Failed to create ISO directory."

    cp -a "$ISO_PROFILE_BASE" "$ISO_PROFILE" \
        || fatal "Failed to copy ArchISO releng profile."

    sed -i \
        's|^iso_name=.*|iso_name="archguard"|' \
        "$ISO_PROFILE/profiledef.sh"
}


# ==============================================================================
# ISO Packages
# ==============================================================================

configure_iso_packages(){
    local package

    for package in git curl; do
        grep -qxF "$package" "$ISO_PROFILE/packages.x86_64" \
            || printf '%s\n' "$package" >> "$ISO_PROFILE/packages.x86_64"
    done
}


# ==============================================================================
# ArchGuard Launcher
# ==============================================================================

create_iso_launcher(){
    msg "Installing ArchGuard ISO launcher..."

    install -Dm755 /dev/stdin \
        "$ISO_PROFILE/airootfs/root/archguard_launch.sh" <<'EOF'
#!/usr/bin/env bash

AG_LABEL="AGBOOT"
AG_MOUNT="/run/ag"
AG_ENTRY="archguard_install.sh"
AG_DEV="/dev/disk/by-label/$AG_LABEL"

echo " [*] Waiting for $AG_LABEL partition..."

udevadm settle

for _ in $(seq 1 30); do
    [[ -b "$AG_DEV" ]] && break
    sleep 1
done

[[ -b "$AG_DEV" ]] \
    || {
        echo " [FATAL] $AG_LABEL partition not found."
        exit 1
    }

mountpoint -q "$AG_MOUNT" ||
    mount "$AG_DEV" "$AG_MOUNT" --mkdir ||
    {
        echo " [FATAL] Failed to mount $AG_DEV."
        exit 1
    }

[[ -f "$AG_MOUNT/$AG_ENTRY" ]] ||
    {
        echo " [FATAL] $AG_ENTRY not found on $AG_LABEL."
        exit 1
    }

echo " [*] Starting $AG_ENTRY..."

exec "$AG_MOUNT/$AG_ENTRY"
EOF
}


# ==============================================================================
# Automatic Launcher
# ==============================================================================

configure_auto_launcher(){
    msg "Configuring automatic ArchGuard launcher..."

    cat >> "$ISO_PROFILE/airootfs/root/.zlogin" <<'EOF'

if [[ "$(tty)" == /dev/tty1 ]]; then
    /root/archguard_launch.sh
fi
EOF
}


# ==============================================================================
# ISO Build
# ==============================================================================

build_iso(){
    msg "Building ArchGuard ISO..."

    rm -rf -- "$ISO_WORK" "$ISO_OUTPUT"

    mkdir -p "$ISO_OUTPUT" \
        || fatal "Failed to create ISO output directory."

    mkarchiso \
        -v \
        -w "$ISO_WORK" \
        -o "$ISO_OUTPUT" \
        "$ISO_PROFILE" \
        || fatal "mkarchiso failed."
}


# ==============================================================================
# ISO Detection
# ==============================================================================

find_iso(){
    local iso

    iso=$(
        find "$ISO_OUTPUT" \
            -maxdepth 1 \
            -type f \
            -name 'archguard-*.iso' \
            -printf '%T@ %p\n' 2>/dev/null |
        sort -nr |
        head -n1 |
        cut -d' ' -f2-
    ) || true

    [[ -f "$iso" ]] \
        || fatal "No ArchGuard ISO found in: $ISO_OUTPUT"

    AG_ISO_FILE="$iso"

    success "ISO ready: $AG_ISO_FILE"
}


# ==============================================================================
# Module Entry Point
# ==============================================================================

run_iso(){
    init_iso
    check_iso_requirements
    prepare_iso_profile
    configure_iso_packages
    create_iso_launcher
    configure_auto_launcher
    build_iso
    find_iso
}