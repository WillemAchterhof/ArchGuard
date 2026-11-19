#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
#  ArchGuard USB Builder Bootstrap
# ==============================================================================
# /create-archguard-usb.sh
#
# Downloads the selected USB Builder release and starts its orchestrator.

# ==============================================================================
# Initialization
# ==============================================================================

init_variables() {
    readonly GIT_URL="https://github.com/WillemAchterhof/archguard-usb-builder.git"
    readonly GIT_BRANCH="v0.1"
    readonly DIR_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    readonly DIR_PROJECT="$DIR_BASE/archguard-usb-builder"
    
    readonly DIR_ORCHESTRATOR="orchestrator"
    readonly FILE_ORCHESTRATOR="orchestrator-launch.sh"
    readonly PATH_ORCHESTRATOR="$DIR_ORCHESTRATOR/$FILE_ORCHESTRATOR"

    DIR_STAGING=""
    DIR_BACKUP=""
}

# ==============================================================================
# Logging
# ==============================================================================

msg() {
    printf '[*] %s\n' "$1"
}

warn() {
    printf '[WARNING] %s\n' "$1" >&2
}

fatal() {
    printf '[FATAL] %s\n' "$1" >&2
    exit 1
}

# ==============================================================================
# Error Handling
# ==============================================================================

trap_err() {
    local exit_code=$?
    local line_number=${1:-unknown}

    trap - ERR
    printf '[ERROR] Command failed at line %s (exit status %s).\n' \
        "$line_number" "$exit_code" >&2
    exit "$exit_code"
}

cleanup() {
    local exit_code=$?

    # Restore the previous project if activation was interrupted midway.
    if [[ -n "${DIR_BACKUP:-}" && -d "$DIR_BACKUP" && ! -e "${DIR_PROJECT:-}" ]]; then
        mv -- "$DIR_BACKUP" "$DIR_PROJECT" 2>/dev/null || \
            warn "Could not restore the previous project from: $DIR_BACKUP"
    fi

    # Staging only ever holds a fresh, user-owned clone: no sudo needed.
    if [[ -n "${DIR_STAGING:-}" && -d "$DIR_STAGING" ]]; then
        rm -rf -- "$DIR_STAGING"
    fi

    return "$exit_code"
}

# ==============================================================================
# Requirements
# ==============================================================================

check_requirements() {
    local required_command

    for required_command in git sudo; do
        command -v "$required_command" >/dev/null 2>&1 || \
            fatal "Required command not found: $required_command"
    done
    
    [[ -w "$DIR_BASE" ]] || \
        fatal "Project directory is not writable: $DIR_BASE"
}

check_sudo() {
    msg "Requesting administrator privileges..."
    sudo -v || fatal "Failed to authenticate with sudo."
}

# ==============================================================================
# Project
# ==============================================================================

download_project() {
    local staging_project

    msg "Downloading ArchGuard USB Builder ($GIT_BRANCH)..."

    DIR_STAGING="$(mktemp -d "$DIR_BASE/.archguard-usb-builder.XXXXXX")" || \
        fatal "Could not create a temporary download directory."

    staging_project="$DIR_STAGING/project"

    if ! git clone --branch "$GIT_BRANCH" --depth 1 \
        "$GIT_URL" "$staging_project"; then
        fatal "Could not download the selected ArchGuard USB Builder release."
    fi

    validate_project "$staging_project"
}

validate_project() {
    local project_dir=$1
    local orchestrator="$project_dir/$PATH_ORCHESTRATOR"

    msg "Validating downloaded project..."

    [[ -f "$orchestrator" ]] || \
        fatal "USB Builder orchestrator not found: $orchestrator"
    [[ -d "$project_dir/lib" ]] || \
        fatal "USB Builder library directory is missing."
    [[ -d "$project_dir/modules" ]] || \
        fatal "USB Builder modules directory is missing."

    if ! bash -n "$orchestrator"; then
        fatal "The downloaded orchestrator contains a Bash syntax error."
    fi

    chmod 0755 "$orchestrator" || \
        fatal "Could not make the orchestrator executable."
}

activate_project() {
    local staging_project="$DIR_STAGING/project"

    msg "Activating ArchGuard USB Builder..."

    # Preserve the current project until the replacement is validated.
    # Renaming within DIR_BASE does not require sudo.
    if [[ -e "$DIR_PROJECT" ]]; then
        DIR_BACKUP="$DIR_BASE/.archguard-usb-builder.previous.$$"

        [[ ! -e "$DIR_BACKUP" ]] || \
            fatal "Temporary backup path already exists: $DIR_BACKUP"

        mv -- "$DIR_PROJECT" "$DIR_BACKUP" || \
            fatal "Could not move the current project aside."
    fi

    # Activate the new project. Restore the previous one if this fails.
    if ! mv -- "$staging_project" "$DIR_PROJECT"; then
        if [[ -n "$DIR_BACKUP" && -d "$DIR_BACKUP" ]]; then
            if mv -- "$DIR_BACKUP" "$DIR_PROJECT"; then
                DIR_BACKUP=""
            else
                warn "Could not restore the previous project."
            fi
        fi

        fatal "Could not activate the downloaded project."
    fi

    # Remove the previous project. It may contain root-owned files.
    if [[ -n "$DIR_BACKUP" && -d "$DIR_BACKUP" ]]; then
        sudo rm -rf -- "$DIR_BACKUP" || \
            warn "Could not remove the previous project backup: $DIR_BACKUP"
        DIR_BACKUP=""
    fi

    # exec in handoff skips the EXIT trap, so remove staging here.
    rmdir -- "$DIR_STAGING" 2>/dev/null || true
    DIR_STAGING=""
}

# ==============================================================================
# Handoff
# ==============================================================================

handoff() {
    local orchestrator="$DIR_PROJECT/$PATH_ORCHESTRATOR"

    [[ -f "$orchestrator" ]] || \
        fatal "USB Builder orchestrator not found: $orchestrator"

    msg "Starting ArchGuard USB Builder..."
    export DIR_PROJECT
    exec bash "$orchestrator" "$@"
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    init_variables

    trap 'trap_err "$LINENO"' ERR
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    check_requirements
    check_sudo
    download_project
    activate_project
    handoff "$@"
}

main "$@"
