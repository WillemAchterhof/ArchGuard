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

    for package in "$@"; do
        if ! pacman -Q "$package" >/dev/null 2>&1; then
            PACKAGES_ADDED+=("$package")
        fi
    done
    
    sudo pacman -S --noconfirm "$@"
}

cleanup(){
    (( ${AG_CLEANUP:-0} )) || return 0

    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi

    if (( ${#PACKAGES_ADDED[@]} > 0 )); then
        msg "Removing packages: ${PACKAGES_ADDED[*]}"

        sudo pacman -Rns --noconfirm \
            "${PACKAGES_ADDED[@]}" \
            2>/dev/null || true
    fi

    if [[ -d "${DIR_PROJECT:-}" ]]; then
        msg "Removing project: $DIR_PROJECT"

        sudo rm -rf -- "$DIR_PROJECT" || true
    fi

    sudo -K || true
}