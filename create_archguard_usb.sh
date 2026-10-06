#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
#  ArchGuard USB Builder Bootstrap
# ==============================================================================
# /create_archguard_usb.sh

# ==============================================================================
# Initialization
# ==============================================================================

check_sudo(){
    command -v sudo >/dev/null 2>&1 \
        || fatal "sudo is required."

    sudo -v \
        || fatal "Failed to authenticate with sudo."
}

init_variables(){
    readonly GIT_URL="https://github.com/WillemAchterhof/archguard-usb-builder.git"
    readonly GIT_BRANCH="v0.1"

    readonly DIR_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    readonly DIR_PROJECT="$DIR_BASE/archguard-usb-builder"
}

# ==============================================================================
# Logging
# ==============================================================================

msg(){
    printf "[*] %s\n" "$1"
}

fatal(){
    printf "[FATAL] %s\n" "$1"

    if [[ -d "${DIR_PROJECT:-}" ]]; then
        sudo rm -rf -- "$DIR_PROJECT" || true
    fi

    exit 1
}

# ==============================================================================
# Error Handling
# ==============================================================================

trap_err(){
    local exit_code=$?

    fatal "Command failed: $BASH_COMMAND (exit $exit_code)"
}

trap 'trap_err' ERR

# ==============================================================================
# Internet
# ==============================================================================

check_internet(){
    msg "Checking Internet connection..."

    curl -fsSI --max-time 5 https://github.com/ >/dev/null 2>&1 \
        || fatal "No Internet connection."
}

# ==============================================================================
# Project
# ==============================================================================

project_copy(){
    local file="$DIR_PROJECT/create_archguard_usb.sh"

    [[ -f "$file" ]] \
        || fatal "USB creator script not found: $file"

    install -m 0755 "$file" "$DIR_BASE/create_archguard_usb.sh" \
        || fatal "Failed to copy USB creator script."
}

project_remove(){
    if [[ -d "$DIR_PROJECT" ]]; then
        msg "Removing previous USB Builder project..."

        sudo rm -rf -- "$DIR_PROJECT" \
            || fatal "Failed to remove previous project."
    fi
}

project_clone(){
    msg "Downloading ArchGuard USB Builder..."

    git clone \
        --branch "$GIT_BRANCH" \
        --depth 1 \
        "$GIT_URL" \
        "$DIR_PROJECT" \
        || fatal "Failed to clone USB Builder project."

    project_copy
}

# ==============================================================================
# Handoff
# ==============================================================================

handoff(){
    local orchestrator="$DIR_PROJECT/orchestrator.sh"

    [[ -f "$orchestrator" ]] \
        || fatal "USB Builder orchestrator not found: $orchestrator"

    chmod 0755 "$orchestrator" \
        || fatal "Failed to make orchestrator executable."

    msg "Starting ArchGuard USB Builder..."

    export DIR_PROJECT
    exec "$orchestrator"
}

# ==============================================================================
# MAIN
# ==============================================================================

main(){
    check_sudo
    init_variables
    check_internet
    project_remove
    project_clone
    handoff
}

main "$@"