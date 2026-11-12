#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Common
# ==============================================================================
# /lib/common.sh

require_command(){
    command -v "$1" >/dev/null 2>&1 \
        || fatal "Required command not found: $1"
}
