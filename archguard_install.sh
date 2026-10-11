#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# ArchGuard Installer Bootstrap
# ==============================================================================
# /archguard_install.sh
#
# Responsibilities:
#   - Make sure an internet connection is available (Wi-Fi setup if needed)
#   - Make sure git is available
#   - Download the installer repository next to this script (install/)
#   - Hand control to the installer orchestrator
#
# Layout (relative to this script, normally the AGBOOT mount point):
#   archguard-install.sh   this script
#   install/               the cloned installer repository (replaced each run)
#   backup-configs/        configuration backup (never touched here)
# ==============================================================================

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

msg() {
    printf '[*] %s\n' "$*"
}

success() {
    printf '[+] %s\n' "$*"
}

warn() {
    printf '[!] %s\n' "$*" >&2
}

fatal() {
    local message="${1:-Unknown error}"
    local source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local line="${BASH_LINENO[0]:-${LINENO}}"

    printf '[FATAL] %s:%s: %s\n' "$source" "$line" "$message" >&2
    exit 1
}

# Export shared functions so the Bash orchestrator can reuse them.
export -f msg success warn fatal

# ------------------------------------------------------------------------------
# Cleanup and error handling
# ------------------------------------------------------------------------------

CLEANUP_DONE=0
TEMP_DIR=""
OLD_INSTALL_MOVED=0

cleanup() {
    if (( CLEANUP_DONE == 1 )); then
        return 0
    fi

    # Restore the previous installation if promotion failed.
    if (( OLD_INSTALL_MOVED == 1 )) &&
       [[ -n "${TEMP_DIR:-}" ]] &&
       [[ -d "$TEMP_DIR/previous-install" ]] &&
       [[ ! -e "${DIR_INSTALL:-}" ]]; then

        if mv -- "$TEMP_DIR/previous-install" "$DIR_INSTALL"; then
            warn "Restored the previous installation."
            OLD_INSTALL_MOVED=0
        else
            warn "Could not restore the previous installation."
            warn "Preserving temporary files at: $TEMP_DIR"
            TEMP_DIR=""
            CLEANUP_DONE=1
            return 1
        fi
    fi

    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        if ! rm -rf -- "$TEMP_DIR"; then
            warn "Could not remove temporary directory: $TEMP_DIR"
            CLEANUP_DONE=1
            return 1
        fi
    fi

    TEMP_DIR=""
    CLEANUP_DONE=1
    return 0
}

on_error() {
    local status=$?
    local source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local line="${BASH_LINENO[0]:-${LINENO}}"

    trap - ERR INT

    # Do not print the failed command: it could contain sensitive data.
    printf '[FATAL] %s:%s: Command failed (exit %s).\n' \
        "$source" "$line" "$status" >&2

    cleanup || true
    exit "$status"
}

on_interrupt() {
    trap - ERR INT

    printf '\n[!] Bootstrap interrupted by user (Ctrl+C).\n' >&2

    cleanup || true
    exit 130
}

trap 'on_error' ERR
trap 'on_interrupt' INT

# Covers every exit path, including fatal(). cleanup() is idempotent, and the
# exec in handoff() bypasses this trap (the temporary directory is already gone).
trap 'cleanup || true' EXIT

# ------------------------------------------------------------------------------
# Initialization
# ------------------------------------------------------------------------------

init_variables() {
    readonly REPO_URL="https://github.com/WillemAchterhof/archguard-install.git"
    readonly REPO_BRANCH="main"

    # Entry point inside the cloned repository.
    readonly ORCHESTRATOR_NAME="orchestrator.sh"

    readonly DIR_BASE="$(
        cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
        pwd -P
    )"

    readonly DIR_INSTALL="$DIR_BASE/install"
    readonly DIR_BACKUP="$DIR_BASE/backup-configs"

    # Wi-Fi credentials remain in memory.
    WIFI_DEVICE=""
    WIFI_SSID=""
    AGS_WIFI_PASSWORD=""

    # The orchestrator can read this path, but the bootstrap never modifies it.
    export DIR_BACKUP
}

# ------------------------------------------------------------------------------
# Network
# ------------------------------------------------------------------------------

check_internet() {
    timeout 5 ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1
}

wifi_connect() {
    command -v iwctl >/dev/null 2>&1 ||
        fatal "iwctl is not available."

    # iwctl colours its output; strip the escape codes before parsing.
    WIFI_DEVICE="$(
        iwctl device list |
        sed 's/\x1b\[[0-9;]*m//g' |
        awk '$NF == "station" { print $1; exit }'
    )"

    [[ -n "$WIFI_DEVICE" ]] ||
        fatal "No wireless station was found. Check the adapter."

    while ! check_internet; do
        msg "Scanning for wireless networks..."

        iwctl station "$WIFI_DEVICE" scan ||
            warn "Wireless scan failed; continuing."

        sleep 2

        iwctl station "$WIFI_DEVICE" get-networks ||
            warn "Could not retrieve the wireless network list."

        printf '\n'
        printf 'Wi-Fi SSID: '
        read -r WIFI_SSID

        [[ -n "$WIFI_SSID" ]] || {
            warn "SSID cannot be empty."
            continue
        }

        printf 'Wi-Fi password: '
        read -rs AGS_WIFI_PASSWORD
        printf '\n'

        msg "Attempting to connect..."

        # iwctl accepts --passphrase as a command-line option.
        # Note that command-line arguments can be visible to privileged
        # local processes while the connection command is running.
        if iwctl --passphrase "$AGS_WIFI_PASSWORD" \
            station "$WIFI_DEVICE" connect "$WIFI_SSID"; then
            sleep 3
        else
            warn "Wi-Fi connection command failed."
        fi

        if ! check_internet; then
            warn "Connection or internet check failed. Try again."
        fi
    done

    success "Internet connection established."
}

network_connection() {
    if check_internet; then
        success "Internet connection already available."
        return 0
    fi

    msg "No internet connection detected. Starting Wi-Fi setup..."
    wifi_connect
}

# ------------------------------------------------------------------------------
# Package preparation
# ------------------------------------------------------------------------------

prepare_pacman_keyring() {
    msg "Preparing the pacman keyring..."

    pacman-key --init ||
        fatal "Failed to initialize the pacman keyring."

    pacman-key --populate archlinux ||
        fatal "Failed to populate the Arch Linux keyring."

    pacman -Sy --needed --noconfirm archlinux-keyring ||
        fatal "Failed to update the Arch Linux keyring."
}

# git is normally already on the ISO; only touch pacman when it is missing.

packages_check() {
    if command -v git >/dev/null 2>&1; then
        success "Git is already available."
        return 0
    fi

    prepare_pacman_keyring

    msg "Installing Git and updating the system..."

    pacman -Sy --needed --noconfirm git ||
        fatal "Failed to update the system or install git."

    command -v git >/dev/null 2>&1 ||
        fatal "Git is still unavailable."

    success "Git is available."
}

# ------------------------------------------------------------------------------
# Download and install the orchestrator
# ------------------------------------------------------------------------------

repository_sync() {
    local repository_dir
    local previous_install

    TEMP_DIR="$(mktemp -d "$DIR_BASE/.archguard.XXXXXX")"

    repository_dir="$TEMP_DIR/repository"
    previous_install="$TEMP_DIR/previous-install"

    msg "Downloading ArchGuard installer..."

    git clone \
        --depth 1 \
        --branch "$REPO_BRANCH" \
        "$REPO_URL" \
        "$repository_dir" ||
        fatal "Failed to download the installer repository."

    [[ -f "$repository_dir/$ORCHESTRATOR_NAME" ]] ||
        fatal "The repository does not contain $ORCHESTRATOR_NAME."

    [[ -x "$repository_dir/$ORCHESTRATOR_NAME" ]] ||
        chmod +x "$repository_dir/$ORCHESTRATOR_NAME" ||
        fatal "Could not make $ORCHESTRATOR_NAME executable."

    # Keep the existing installation until the new clone is validated.
    if [[ -e "$DIR_INSTALL" ]]; then
        msg "Preserving the current installation temporarily..."

        mv -- "$DIR_INSTALL" "$previous_install" ||
            fatal "Could not move the existing installation."

        OLD_INSTALL_MOVED=1
    fi

    # Promote the validated repository into the managed install directory.
    if ! mv -- "$repository_dir" "$DIR_INSTALL"; then
        warn "Could not activate the new installation."

        if (( OLD_INSTALL_MOVED == 1 )); then
            if mv -- "$previous_install" "$DIR_INSTALL"; then
                OLD_INSTALL_MOVED=0
                fatal "The previous installation was restored."
            else
                warn "Automatic restoration failed."
                warn "The previous installation remains at: $previous_install"

                # Preserve the previous installation rather than deleting it.
                TEMP_DIR=""
                fatal "Installation failed; manual recovery is required."
            fi
        fi

        fatal "Could not activate the new installation."
    fi

    OLD_INSTALL_MOVED=0

    # The new installation is in place; remove temporary files.
    rm -rf -- "$TEMP_DIR" ||
        warn "Could not remove temporary files: $TEMP_DIR"

    TEMP_DIR=""

    success "Installer repository is ready."
}

# ------------------------------------------------------------------------------
# Handoff
# ------------------------------------------------------------------------------

handoff() {
    local orchestrator="$DIR_INSTALL/$ORCHESTRATOR_NAME"

    [[ -f "$orchestrator" ]] ||
        fatal "Orchestrator not found: $orchestrator"

    # Pass credentials through the environment, not through a config file.
    export WIFI_SSID
    export AGS_WIFI_PASSWORD

    success "Starting ArchGuard orchestrator..."

    # The orchestrator should define its own traps and cleanup routine.
    exec bash "$orchestrator" "$@"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    init_variables
    network_connection
    packages_check
    repository_sync
    handoff "$@"
}

main "$@"
