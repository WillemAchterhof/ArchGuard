#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - ISO
# ==============================================================================
# /modules/create-iso.sh
#
# Responsibilities:
#   - Prepare the ArchISO releng profile (stock, only renamed)
#   - Build the ISO
#   - Locate the resulting ISO
#   - Sign the boot chain (boot loader, kernel, UEFI shell) with the ArchGuard
#     db key and repack the ISO so it boots with Secure Boot enabled
#
# Signing key (override with environment variables):
#   ISO_SB_KEY   default: /var/lib/sbctl/keys/db/db.key
#   ISO_SB_CERT  default: /var/lib/sbctl/keys/db/db.pem
#
# Host requirements:
#   archiso  libisoburn  mtools  sbsigntools
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
    readonly ISO_SIGN="$ISO_DIR/sign"

    readonly ISO_SB_KEY="${ISO_SB_KEY:-/var/lib/sbctl/keys/db/db.key}"
    readonly ISO_SB_CERT="${ISO_SB_CERT:-/var/lib/sbctl/keys/db/db.pem}"
    readonly ISO_SB_CERT_LOCAL="$ISO_SIGN/db.crt"

    # Paths inside the ISO (and inside the El Torito UEFI boot image)
    readonly ISO_PATH_KERNEL="/arch/boot/x86_64/vmlinuz-linux"
    readonly ISO_PATH_LOADER="/EFI/BOOT/BOOTx64.EFI"
    readonly ISO_PATH_SHELL="/shellx64.efi"

    readonly ISO_SIGN_ESP="$ISO_SIGN/eltorito_img2_uefi.img"

    AG_ISO_FILE=""
}


# ==============================================================================
# Helpers
# ==============================================================================

# mkarchiso runs unprivileged, so its work dir may not be removable with a
# plain rm. Fall back to a user namespace (ArchWiki: archiso).
remove_dir(){
    local dir="$1"

    [[ -e "$dir" ]] || return 0

    rm -rf -- "$dir" 2>/dev/null && return 0

    unshare --map-auto --map-root-user -- rm -rf -- "$dir" \
        || fatal "Failed to remove: $dir"
}


# The sbctl key directory is root-only. Fall back to sudo when needed.
can_read(){
    [[ -r "$1" ]] || sudo test -r "$1" 2>/dev/null
}


# ==============================================================================
# Requirements
# ==============================================================================

install_iso_requirements(){
    packages_install \
        archiso \
        libisoburn \
        mtools \
        sbsigntools \
        archinstall \
        grub
}

check_iso_requirements(){
    local command

    for command in mkarchiso osirrox xorriso mcopy sbsign sbverify; do
        require_command "$command"
    done

    [[ -d "$ISO_PROFILE_BASE" ]] \
        || fatal "ArchISO releng profile not found: $ISO_PROFILE_BASE"

    # Fail now instead of after a long build.
    can_read "$ISO_SB_KEY" \
        || fatal "Signing key not found/readable: $ISO_SB_KEY (set ISO_SB_KEY)"

    can_read "$ISO_SB_CERT" \
        || fatal "Signing certificate not found/readable: $ISO_SB_CERT (set ISO_SB_CERT)"
}


# ==============================================================================
# Profile Preparation
# ==============================================================================

prepare_iso_profile(){
    msg "Preparing ArchISO profile..."

    remove_dir "$ISO_PROFILE"

    mkdir -p "$ISO_DIR" \
        || fatal "Failed to create ISO directory."

    cp -a "$ISO_PROFILE_BASE" "$ISO_PROFILE" \
        || fatal "Failed to copy ArchISO releng profile."

    sed -i \
        's|^iso_name=.*|iso_name="archguard"|' \
        "$ISO_PROFILE/profiledef.sh"

    cat >> "$ISO_PROFILE/profiledef.sh" <<'EOF'

# ArchGuard Secure Boot bootstrap
file_permissions["/usr/local/bin/archguard-secure-boot.sh"]="0:0:755"
EOF

    # ArchGuard Secure Boot tooling required inside the live ISO.
    grep -qx 'sbctl' "$ISO_PROFILE/packages.x86_64" \
        || printf 'sbctl\n' >> "$ISO_PROFILE/packages.x86_64"
}


# ==============================================================================
# ArchGuard Boot
# ==============================================================================

prepare_archguard_boot(){
    msg "Preparing ArchGuard Secure Boot bootstrap..."

    local source="$DIR_MAIN/modules/secure-boot.sh"
    local target="$ISO_PROFILE/airootfs/usr/local/bin/archguard-secure-boot.sh"

    [[ -f "$source" ]] \
        || fatal "Secure Boot module not found: $source"

    mkdir -p "$(dirname "$target")" \
        || fatal "Failed to create ArchGuard boot directory."

    cp -- "$source" "$target" \
        || fatal "Failed to copy Secure Boot module."
}


prepare_archguard_boot_service(){
    local service="$ISO_PROFILE/airootfs/etc/systemd/system/archguard-secure-boot.service"
    local wants="$ISO_PROFILE/airootfs/etc/systemd/system/multi-user.target.wants"

    mkdir -p "$wants" \
        || fatal "Failed to create systemd service directory."

    cat > "$service" <<'EOF'

[Unit]
Description=ArchGuard Secure Boot Bootstrap
After=archiso.target
Wants=archiso.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/archguard-secure-boot.sh
StandardInput=tty
StandardOutput=journal+console
StandardError=journal+console
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

    ln -sf \
        "../archguard-secure-boot.service" \
        "$wants/archguard-secure-boot.service"
}


# ==============================================================================
# ISO Build
# ==============================================================================

build_iso(){
    msg "Building ArchGuard ISO..."

    remove_dir "$ISO_WORK"
    remove_dir "$ISO_OUTPUT"

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

    success "ISO built: $AG_ISO_FILE"
}


# ==============================================================================
# ISO Signing
# ==============================================================================

extract_iso_boot(){
    msg "Extracting boot files..."

    remove_dir "$ISO_SIGN"

    mkdir -p "$ISO_SIGN" \
        || fatal "Failed to create signing directory."

    osirrox \
        -indev "$AG_ISO_FILE" \
        -extract_boot_images "$ISO_SIGN/" \
        -cpx \
            "$ISO_PATH_KERNEL" \
            "$ISO_PATH_LOADER" \
            "$ISO_PATH_SHELL" \
            "$ISO_SIGN/" \
        || fatal "Failed to extract boot files from ISO."

    [[ -f "$ISO_SIGN_ESP" ]] \
        || fatal "UEFI boot image not found: $ISO_SIGN_ESP"

    # Files extracted from the ISO are read-only.
    chmod -R u+w "$ISO_SIGN" \
        || fatal "Failed to make extracted files writable."
}


# ==============================================================================
# Profile Preparation
# ==============================================================================

prepare_signing_cert(){
    # Public certificate only: keep a local copy so sbsign/sbverify can use it
    # without privileges. The private key is never copied.
    if [[ -r "$ISO_SB_CERT" ]]; then
        cp -- "$ISO_SB_CERT" "$ISO_SB_CERT_LOCAL" \
            || fatal "Failed to copy signing certificate."
    else
        sudo cat -- "$ISO_SB_CERT" > "$ISO_SB_CERT_LOCAL" \
            || fatal "Failed to read signing certificate."
    fi
}

sign_iso_boot(){
    msg "Signing boot loader, kernel and UEFI shell..."

    local file
    local -a priv=()

    # Key not readable as this user: run only sbsign with sudo.
    [[ -r "$ISO_SB_KEY" ]] || priv=(sudo)

    for file in vmlinuz-linux BOOTx64.EFI shellx64.efi; do
        "${priv[@]}" sbsign \
            --key "$ISO_SB_KEY" \
            --cert "$ISO_SB_CERT_LOCAL" \
            --output "$ISO_SIGN/$file" \
            "$ISO_SIGN/$file" \
            || fatal "Failed to sign: $file"

        if (( ${#priv[@]} > 0 )); then
            sudo chown "$(id -u):$(id -g)" "$ISO_SIGN/$file" \
                || fatal "Failed to restore ownership: $file"
        fi

        sbverify --cert "$ISO_SB_CERT_LOCAL" "$ISO_SIGN/$file" >/dev/null \
            || fatal "Signature check failed: $file"
    done
}

update_iso_esp(){
    msg "Updating UEFI boot image..."

    mcopy -D oO -i "$ISO_SIGN_ESP" \
        "$ISO_SIGN/vmlinuz-linux" "::$ISO_PATH_KERNEL" \
        || fatal "Failed to copy kernel into UEFI boot image."

    mcopy -D oO -i "$ISO_SIGN_ESP" \
        "$ISO_SIGN/BOOTx64.EFI" "::$ISO_PATH_LOADER" \
        || fatal "Failed to copy boot loader into UEFI boot image."

    mcopy -D oO -i "$ISO_SIGN_ESP" \
        "$ISO_SIGN/shellx64.efi" "::$ISO_PATH_SHELL" \
        || fatal "Failed to copy UEFI shell into UEFI boot image."
}

verify_iso_esp(){
    local path
    local check="$ISO_SIGN/check.efi"

    for path in "$ISO_PATH_KERNEL" "$ISO_PATH_LOADER" "$ISO_PATH_SHELL"; do
        rm -f -- "$check"

        mcopy -n -i "$ISO_SIGN_ESP" "::$path" "$check" \
            || fatal "Failed to read back from UEFI boot image: $path"

        sbverify --cert "$ISO_SB_CERT_LOCAL" "$check" >/dev/null \
            || fatal "Not signed inside UEFI boot image: $path"
    done

    rm -f -- "$check"
}

repack_iso(){
    msg "Repacking ISO..."

    local signed="$ISO_SIGN/signed.iso"

    # -overwrite on: replace the unsigned files already present in the image.
    xorriso \
        -indev "$AG_ISO_FILE" \
        -outdev "$signed" \
        -overwrite on \
        -map "$ISO_SIGN/vmlinuz-linux" "$ISO_PATH_KERNEL" \
        -map "$ISO_SIGN/BOOTx64.EFI"   "$ISO_PATH_LOADER" \
        -map "$ISO_SIGN/shellx64.efi"  "$ISO_PATH_SHELL" \
        -boot_image any replay \
        -append_partition 2 0xef "$ISO_SIGN_ESP" \
        || fatal "xorriso repack failed."

    mv -f -- "$signed" "$AG_ISO_FILE" \
        || fatal "Failed to replace ISO with signed ISO."
}

verify_iso(){
    msg "Verifying signed ISO..."

    local check="$ISO_SIGN/verify"
    local path

    remove_dir "$check"
    mkdir -p "$check"

    osirrox \
        -indev "$AG_ISO_FILE" \
        -cpx "$ISO_PATH_KERNEL" "$ISO_PATH_LOADER" "$ISO_PATH_SHELL" "$check/" \
        || fatal "Failed to read files back from signed ISO."

    for path in vmlinuz-linux BOOTx64.EFI shellx64.efi; do
        sbverify --cert "$ISO_SB_CERT_LOCAL" "$check/$path" >/dev/null \
            || fatal "Not signed inside ISO: $path"
    done
}

sign_iso(){
    extract_iso_boot
    prepare_signing_cert
    sign_iso_boot
    update_iso_esp
    verify_iso_esp
    repack_iso
    verify_iso

    success "ISO signed: $AG_ISO_FILE"
}


# ==============================================================================
# Module Entry Point
# ==============================================================================

run_build_iso(){
    init_iso
    install_iso_requirements
    check_iso_requirements
    prepare_iso_profile
    prepare_archguard_boot
    prepare_archguard_boot_service
    build_iso
    find_iso
    sign_iso
}