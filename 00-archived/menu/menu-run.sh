#!/usr/bin/env bash

# ==============================================================================
# ArchGuard USB Builder - Menu Loader
# ==============================================================================
# /menu/menu-run.sh

# ==============================================================================
# Load Validation
# ==============================================================================

source "$DIR_MAIN/validate/validate-base.sh"
source "$DIR_MAIN/validate/validate-software.sh"

# ==============================================================================
# Load Menu Functions
# ==============================================================================

source "$DIR_MENU/agboot-device.sh"
source "$DIR_MENU/base-edit.sh"
source "$DIR_MENU/base-run.sh"
source "$DIR_MENU/software-edit.sh"
source "$DIR_MENU/software-run.sh"
