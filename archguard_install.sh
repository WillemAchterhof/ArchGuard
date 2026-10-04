#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
#  Arch Secure Installer V2.6
# ==============================================================================
#  Bootstrap entry point for the Arch Secure Installer.
#
#  After successful preparation, control is handed off to: orchestrator.sh

# ==============================================================================
# Initialization
# ==============================================================================

check_root(){
   [[ $EUID -eq 0 ]] || fatal "Must be run as root. Use: sudo bash archguard_install.sh"
}

init_variables(){
    readonly AG_REPO_URL="https://github.com/WillemAchterhof/archguard-install.git"
    readonly AG_REPO_BRANCH="main"

    readonly AG_DIR_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    readonly AG_DIR_INSTALL="$AG_DIR_BASE/install"
    readonly AG_DIR_STATE="$AG_DIR_BASE/state"
	
	readonly AG_DIR_LOG="$AG_DIR_STATE/log"
	readonly AG_DIR_CONFIG="$AG_DIR_STATE/config"

    readonly AG_FILE_LOG="$AG_DIR_LOG/archguard_install.log"
    readonly AG_FILE_WIFI="$AG_DIR_CONFIG/wifi.env"
	
	AG_WIFI_DEVICE=""
	AG_WIFI_SSID=""
	AGS_WIFI_PASSWORD=""
}

init_state(){
    local dir

    for dir in \
        "$AG_DIR_STATE" \
        "$AG_DIR_LOG" \
        "$AG_DIR_CONFIG"
    do
        [[ -d "$dir" ]] || mkdir -p "$dir"

        if [[ ! -w "$dir" ]]; then
            chmod u+w "$dir" 2>/dev/null || true
        fi

        [[ -w "$dir" ]] \
            || fatal "Directory not writable: $dir"
    done

    : > "$AG_FILE_LOG"
}

# --------------
initialization(){
	init_variables
  	check_root
	init_state
}

# ==============================================================================
# Error Handling
# ==============================================================================

trap_err(){
    local exit_code=$?

    local command="${BASH_COMMAND:-unknown}"
    local line="${BASH_LINENO[0]}"
    local file="${BASH_SOURCE[1]:-unknown}"

    local message="[FATAL]
File    : $file:$line
Command : $command
Exit    : $exit_code"

    printf "%s\n" "$message"
    log_silent "$message"

    exit "$exit_code"
}

trap 'trap_err' ERR

# ==============================================================================
# Logging
# ==============================================================================

log(){
    printf " %s\n" "$1"
    log_silent "$1"
}

log_silent(){
    [[ -n "${AG_FILE_LOG:-}" && -w "$AG_FILE_LOG" ]] || return 0
    printf " %s\n" "$1" >> "$AG_FILE_LOG"
}

msg(){
    log "[*] $1"
}

fatal(){
    log "[FATAL] $1"
    exit 1
}

log_header(){
    log_silent "================================================================================"
    log_silent "$1"
    log_silent " $(date '+%Y-%m-%d %H:%M:%S')"
    log_silent "================================================================================"
}

log_variables(){
    log_silent "VARIABLES"

    while IFS= read -r var; do
        [[ "$var" == AGS_* ]] && continue
        log_silent "$(printf " %-20s = %q" "$var" "${!var}")"
    done < <(compgen -A variable AG_)

    log_silent "================================================================================"
}

logging_setup(){
    log_header "BOOTSTRAP"
    log_variables
}

# ==============================================================================
# Network Connection
# ==============================================================================

check_internet(){
    timeout 5 ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1
}

wifi_show(){
    AG_WIFI_DEVICE="$(iwctl device list | awk '/station/ {print $2; exit}')"

    [[ -n "$AG_WIFI_DEVICE" ]] \
        || fatal "No wireless adapter found."

    msg "Scanning for wireless networks..."

    iwctl station "$AG_WIFI_DEVICE" scan
    sleep 2

    printf "\nAvailable wireless networks:\n\n"

    iwctl station "$AG_WIFI_DEVICE" get-networks |
        tail -n +5 |
        sed 's/^[>* ]*//'

    printf "\n"
}

wifi_select(){
    printf "SSID: "
    read -r AG_WIFI_SSID
}

wifi_password(){
    printf "\nPassword: "
    read -rs AGS_WIFI_PASSWORD
    printf "\n"
}

wifi_attempt(){
    iwctl station "$AG_WIFI_DEVICE" connect \
        "$AG_WIFI_SSID" \
        --passphrase "$AGS_WIFI_PASSWORD"
}

wifi_connect(){
    while ! check_internet; do

        wifi_select
        wifi_password

        if wifi_attempt; then
            sleep 3
        fi

        if check_internet; then
            break
        fi

        printf "\nUnable to connect. Please try again.\n\n"

    done

    printf "\nConnected.\n\n"
}

wifi_save(){
    cat > "$AG_FILE_WIFI" <<EOF
AG_WIFI_SSID=$(printf '%q' "$AG_WIFI_SSID")
AGS_WIFI_PASSWORD=$(printf '%q' "$AGS_WIFI_PASSWORD")
EOF

    chmod 600 "$AG_FILE_WIFI"
    
    unset AGS_WIFI_PASSWORD
}

# ------------------
network_connection(){
    check_internet && return
    wifi_show
	wifi_connect
    wifi_save
}

# ==============================================================================
# Packages Check
# ==============================================================================

package_check(){

	AG_INSTALL_PACKAGES=()	
	readonly AG_PACKAGES_BOOTSTRAP=(
		git
		curl
	)
	
    local package

    for package in "${AG_PACKAGES_BOOTSTRAP[@]}"; do

        if command -v "$package" >/dev/null 2>&1; then
            log "[installed] $package"
        else
            AG_INSTALL_PACKAGES+=("$package")
        fi

    done
}

package_install(){
    [[ ${#AG_INSTALL_PACKAGES[@]} -eq 0 ]] && return

    msg "Installing required bootstrap packages..."

    pacman -Sy --noconfirm --needed \
        "${AG_INSTALL_PACKAGES[@]}" \
        || fatal "Failed to install required packages."
}

# --------------
packages_check(){
	package_check
	package_install
}

# ==============================================================================
# Repository
# ==============================================================================

check_install_dir(){
    local base
	local install

    base="$(realpath "$AG_DIR_BASE")"
    install="$(realpath -m "$AG_DIR_INSTALL")"

    [[ "$install" == "$base" ]] \
        && fatal "AG_DIR_INSTALL must not be the base dir itself: $install"

    [[ "$install" == "$base/"* ]] \
        || fatal "AG_DIR_INSTALL is outside base dir, refusing to remove: $install"
}

repository_remove(){
    check_install_dir

    if [[ -d "$AG_DIR_INSTALL" ]]; then
        rm -rf -- "$AG_DIR_INSTALL" \
            || fatal "Failed to remove previous installer."

        msg "Previous repository removed."
    else
        msg "No previous repository detected."
    fi
}

repository_clone(){
    msg "Downloading installer..."

    git clone \
        --branch "$AG_REPO_BRANCH" \
        --depth 1 \
        "$AG_REPO_URL" \
        "$AG_DIR_INSTALL" \
        || fatal "Failed to clone repository."
}

# ---------------
repository_sync(){
    repository_remove
    repository_clone
}

# ------
handoff(){
    [[ -f "$AG_DIR_INSTALL/orchestrator.sh" ]] \
        || fatal "Installer entry point not found."

    msg "Starting installer..."

	exec bash "$AG_DIR_INSTALL/orchestrator.sh"
}

# ==============================================================================
# MAIN
# ==============================================================================

main(){
	initialization
	logging_setup
	network_connection
	packages_check
	repository_sync
	handoff
}

main
