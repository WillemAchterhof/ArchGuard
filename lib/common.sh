
#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Common
# ==============================================================================
# /lib/common.sh

# ==============================================================================
# COMMAND REQUIREMENTS
# ==============================================================================

require_command()
{
    command -v "$1" >/dev/null 2>&1 \
        || fatal "Required command not found: $1"
}

# ==============================================================================
# BLOCK DEVICE HELPERS
# ==============================================================================

get_parent_disk()
{
    local device="$1"
    local resolved
    local parent_disk

    [[ -n "$device" ]] || return 1

    resolved="$(readlink -f -- "$device" 2>/dev/null)" || return 1

    [[ -b "$resolved" ]] || return 1

    parent_disk="$(
        lsblk -s -nrpo NAME,TYPE -- "$resolved" |
            awk '$2 == "disk" { print $1; exit }'
    )"

    [[ -n "$parent_disk" ]] || return 1

    printf '%s\n' "$parent_disk"
}

# ==============================================================================
# CLEANUP
# ==============================================================================

cleanup()
{
    local project_dir=""
    local main_dir=""

    # Project deletion must be explicitly enabled.
    if [[ "${AG_CLEANUP_PROJECT:-0}" == "1" &&
          -n "${DIR_PROJECT:-}" &&
          -d "$DIR_PROJECT" ]]; then

        project_dir="$(readlink -f -- "$DIR_PROJECT" 2>/dev/null || true)"
        main_dir="$(readlink -f -- "${DIR_MAIN:-}" 2>/dev/null || true)"

        if [[ -n "$project_dir" &&
              "$project_dir" != "/" &&
              "$project_dir" != "$main_dir" &&
              "$main_dir" != "$project_dir/"* ]]; then

            msg "Removing project: $project_dir"

            sudo rm -rf -- "$project_dir" || \
                warn "Could not remove project directory."

        else
            warn "Unsafe project cleanup path. Skipping deletion."
        fi
    fi

    # Invalidate sudo credentials.
    sudo -K 2>/dev/null || true
}
