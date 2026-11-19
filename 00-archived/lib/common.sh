
#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Common
# ==============================================================================
# /lib/common.sh

PACKAGES_ADDED=()

start_sudo_keepalive(){
    (
        while sleep 60; do
            sudo -n -v || {
                msg "Sudo keepalive failed."
                exit 1
            }
        done
    ) &

    SUDO_KEEPALIVE_PID=$!
}

require_command(){
    command -v "$1" >/dev/null 2>&1 \
        || fatal "Required command not found: $1"
}

packages_install(){
    local package
    local -a missing=()

    for package in "$@"; do
        if ! pacman -Q "$package" >/dev/null 2>&1; then
            missing+=("$package")
        fi
    done

    # Nothing to install.
    (( ${#missing[@]} > 0 )) || return 0

    # Install only packages that were missing.
    sudo pacman -S --noconfirm "${missing[@]}" \
        || fatal "Failed to install packages: ${missing[*]}"

    # Track packages only after successful installation.
    PACKAGES_ADDED+=("${missing[@]}")
}

cleanup(){
    # Prevent recursive or repeated cleanup.
    [[ "${CLEANUP_RUNNING:-0}" == 1 ]] && return 0
    CLEANUP_RUNNING=1

    # Prevent signals from triggering cleanup recursively.
    trap '' INT TERM

    if (( ${NEW_CERT:-0} == 1 )); then
        msg "Temporary certificates are active. Restoring original certificates..."

        if ! restore_original_custom_certificate; then
            warn "AUTOMATIC CERTIFICATE RESTORATION FAILED."
            warn "Do not delete either certificate path."
            warn "Inspect: /var/lib/sbctl"
            warn "Inspect: /var/lib/sbctl.old"
        fi
    fi

    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        # Kill direct children, including a pending sleep 60.
        pkill -P "$SUDO_KEEPALIVE_PID" 2>/dev/null || true

        # Stop and reap the keepalive subshell.
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true

        SUDO_KEEPALIVE_PID=""
    fi

    if (( ${#PACKAGES_ADDED[@]} > 0 )); then
        msg "Removing packages: ${PACKAGES_ADDED[*]}"

        sudo pacman -Rns --noconfirm \
            "${PACKAGES_ADDED[@]}" \
            2>/dev/null || true

        PACKAGES_ADDED=()
    fi

    if [[ -n "${DIR_MAIN:-}" &&
          "$DIR_MAIN" != "/" &&
          -d "$DIR_MAIN" ]]; then
    
        msg "Removing project: $DIR_MAIN"
        sudo rm -rf -- "$DIR_MAIN" || true
    fi

    sudo -K || true
}
