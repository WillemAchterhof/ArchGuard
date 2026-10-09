readonly AGBOOT_INSTALLER_URL="https://raw.githubusercontent.com/WillemAchterhof/archguard-install/refs/heads/main/archguard_install.sh"
readonly AGBOOT_INSTALLER="archguard-install.sh"
readonly AGBOOT_LABEL="AGBOOT"
readonly AGBOOT_MOUNT="/run/archguard/agboot"

download_agboot_installer(){
    msg "Downloading ArchGuard installer from GitHub..."

    AGBOOT_DOWNLOAD="$(mktemp)" \
        || fatal "Failed to create temporary download file."

    curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --retry 3 \
        --connect-timeout 10 \
        --output "$AGBOOT_DOWNLOAD" \
        "$AGBOOT_INSTALLER_URL" \
        || fatal "Failed to download ArchGuard installer."

    [[ -s "$AGBOOT_DOWNLOAD" ]] \
        || fatal "Downloaded installer is empty."

    bash -n "$AGBOOT_DOWNLOAD" \
        || fatal "Downloaded installer has invalid Bash syntax."

    chmod 0755 "$AGBOOT_DOWNLOAD" \
        || fatal "Failed to set installer permissions."

    success "Installer downloaded and syntax checked."
}

populate_agboot_partition(){
    msg "Installing ArchGuard installer on AGBOOT..."

    mkdir -p "$AGBOOT_MOUNT" \
        || fatal "Failed to create AGBOOT mount point."

    mount "$AG_AGBOOT_PART" "$AGBOOT_MOUNT" \
        || fatal "Failed to mount AGBOOT."

    install \
        --owner=0 \
        --group=0 \
        --mode=0755 \
        "$AGBOOT_DOWNLOAD" \
        "$AGBOOT_MOUNT/$AGBOOT_INSTALLER" \
        || fatal "Failed to install installer on AGBOOT."

    success "Installer copied to AGBOOT."
}

verify_agboot_partition(){
    msg "Verifying AGBOOT..."

    [[ "$(lsblk -no LABEL "$AG_AGBOOT_PART" | xargs)" == "$AGBOOT_LABEL" ]] \
        || fatal "AGBOOT label verification failed."

    [[ -f "$AGBOOT_MOUNT/$AGBOOT_INSTALLER" ]] \
        || fatal "Installer is missing from AGBOOT."

    [[ -x "$AGBOOT_MOUNT/$AGBOOT_INSTALLER" ]] \
        || fatal "Installer is not executable."

    cmp -s \
        "$AGBOOT_DOWNLOAD" \
        "$AGBOOT_MOUNT/$AGBOOT_INSTALLER" \
        || fatal "Installer verification failed: files differ."

    success "AGBOOT verification passed."
}

close_agboot_partition(){
    msg "Unmounting AGBOOT..."

    if mountpoint -q "$AGBOOT_MOUNT"; then
        umount "$AGBOOT_MOUNT" \
            || fatal "Failed to unmount AGBOOT."
    fi

    rm -f -- "${AGBOOT_DOWNLOAD:-}"

    success "AGBOOT unmounted."
}