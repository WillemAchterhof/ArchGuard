#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
#  ArchGuard Bootstrap
# ==============================================================================
# /install-archguard.sh
#
# Downloads the selected ArchGuard release and starts its orchestrator.

# ==============================================================================
# Initialization
# ==============================================================================

init_variables() {
    readonly GIT_URL="https://github.com/WillemAchterhof/archguard.git"
    readonly GIT_BRANCH="version-one"

    DIR_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    readonly DIR_BASE

    readonly DIR_PROJECT="$DIR_BASE/archguard"
    readonly DIR_ORCHESTRATOR="orchestrator"
    readonly FILE_ORCHESTRATOR="launch-orchestrator.sh"
    readonly REL_ORCHESTRATOR="$DIR_ORCHESTRATOR/$FILE_ORCHESTRATOR"

    export GIT_TERMINAL_PROMPT=0

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

# ==============================================================================
# Clean Up
# ==============================================================================

restore_previous_project() {
    # Nothing to do on a fresh install.
    [[ -n "$DIR_BACKUP" && -d "$DIR_BACKUP" ]] || return 0

    # Target must be empty, or restoring would clobber the new project.
    if [[ -e "$DIR_PROJECT" ]]; then
        warn "New project exists; leaving backup in place: $DIR_BACKUP"
        return 0
    fi

    if mv -- "$DIR_BACKUP" "$DIR_PROJECT"; then
        msg "Restored previous project."
        DIR_BACKUP=""
    else
        warn "Could not restore the previous project from: $DIR_BACKUP"
    fi
}

remove_staging() {
    [[ -n "$DIR_STAGING" && -d "$DIR_STAGING" ]] || return 0
    rm -rf -- "$DIR_STAGING"
}

cleanup() {
    local exit_code=$?

    restore_previous_project || true
    remove_staging || warn "Could not remove staging directory: $DIR_STAGING"

    return "$exit_code"
}

# ==============================================================================
# Requirements
# ==============================================================================

check_requirements() {
    local required_command

    for required_command in git bash; do
        command -v "$required_command" >/dev/null 2>&1 ||
            fatal "Required command not found: $required_command"
    done

    [[ -w "$DIR_BASE" ]] ||
        fatal "Project directory is not writable: $DIR_BASE"
}

check_internet_connectivity() {
    git ls-remote --exit-code --heads "$GIT_URL" "$GIT_BRANCH" >/dev/null 2>&1 || \
        fatal "Cannot reach $GIT_URL or branch '$GIT_BRANCH' does not exist."
}

# ==============================================================================
# Project
# ==============================================================================

download_project() {
    local staging_project

    msg "Downloading ArchGuard ($GIT_BRANCH)..."

    DIR_STAGING="$(mktemp -d "$DIR_BASE/.archguard.XXXXXX")" || \
        fatal "Could not create a temporary download directory."

    staging_project="$DIR_STAGING/project"

    if ! git clone --branch "$GIT_BRANCH" --depth 1 \
        "$GIT_URL" "$staging_project"; then
        fatal "Could not download the selected ArchGuard release."
    fi

    validate_project "$staging_project"
}

purge_leftover_backups() {
    # Backups from previously interrupted runs never had their owner come back.
    local leftover
    for leftover in "$DIR_BASE"/.archguard.previous.*; do
        [[ -e "$leftover" ]] || return 0   # no matches: glob stayed literal
        rm -rf -- "$leftover" || \
            warn "Could not remove leftover backup: $leftover"
    done
}

discard_previous_backup() {
    [[ -n "$DIR_BACKUP" && -d "$DIR_BACKUP" ]] || return 0
    rm -rf -- "$DIR_BACKUP" || \
        warn "Could not remove the previous project backup: $DIR_BACKUP"
    DIR_BACKUP=""
}

backup_current_project() {
    # Preserve the current project until the replacement is validated.
    # Renaming within DIR_BASE does not require sudo.
    if [[ -e "$DIR_PROJECT" ]]; then
        DIR_BACKUP="$DIR_BASE/.archguard.previous.$$"

        [[ ! -e "$DIR_BACKUP" ]] || \
            fatal "Temporary backup path already exists: $DIR_BACKUP"

        mv -- "$DIR_PROJECT" "$DIR_BACKUP" || \
            fatal "Could not move the current project aside."
    fi
}

promote_staged_project() {
    local staging_project=$1

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
}

validate_project() {
    local project_dir=$1
    local orchestrator="$project_dir/$REL_ORCHESTRATOR"

    [[ -f "$orchestrator" ]] || \
        fatal "Orchestrator launcher not found: $orchestrator"
    bash -n "$orchestrator" || \
        fatal "Orchestrator has a Bash syntax error."
}

activate_project() {
    local staging_project="$DIR_STAGING/project"

    msg "Activating ArchGuard..."

    # mv DIR_PROJECT → DIR_BACKUP, sets DIR_BACKUP
    backup_current_project

    # mv staging → DIR_PROJECT; on failure, restore + fatal
    promote_staged_project "$staging_project"

    # rm backup + clear DIR_BACKUP
    discard_previous_backup

    # exec in handoff skips the EXIT trap, so remove staging here.
    if rmdir -- "$DIR_STAGING" 2>/dev/null; then
        DIR_STAGING=""
    fi
}

# ==============================================================================
# Handoff
# ==============================================================================

handoff() {
    local orchestrator="$DIR_PROJECT/$REL_ORCHESTRATOR"

    [[ -f "$orchestrator" ]] || \
        fatal "Orchestrator not found: $orchestrator"

    msg "Starting ArchGuard..."
    export DIR_PROJECT
    exec bash "$orchestrator" "$@"
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    init_variables

    trap 'trap_err "${BASH_LINENO[0]}"' ERR
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    check_requirements
    check_internet_connectivity
    purge_leftover_backups
    download_project
    activate_project
    handoff "$@"
}

main "$@"