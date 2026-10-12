#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Common
# ==============================================================================
# /lib/common.sh

require_command(){
    command -v "$1" >/dev/null 2>&1 \
        || fatal "Required command not found: $1"
}

cleanup(){
    if [[ -n "${DIR_PROJECT:-}" && "$DIR_PROJECT" != "/" && -d "$DIR_PROJECT" ]]; then
        msg "Removing project: $DIR_PROJECT"
        sudo rm -rf -- "$DIR_PROJECT" || true
    fi

    sudo -K || true
}