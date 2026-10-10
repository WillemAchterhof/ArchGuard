
#!/usr/bin/env bash

# ==============================================================================
# ArchGuard - Configuration Backup Paths
# ==============================================================================

declare -A BACKUP_PATHS=(

    # Neovim
    ["nvim"]="/home/willem/.config/nvim"

    # SDDM
    ["sddm"]="/etc/sddm.conf"

    # KDE Plasma
    ["kde-global"]="/home/willem/.config/kdeglobals"
    ["kde-shortcuts"]="/home/willem/.config/kglobalshortcutsrc"
    ["kde-window-manager"]="/home/willem/.config/kwinrc"

    # Add more configuration paths below
    # ["example"]="/other/config/files"
)
