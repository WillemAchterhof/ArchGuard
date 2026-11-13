
#!/usr/bin/env bash
# ==============================================================================
# ArchGuard — Target Disk Selection
# ==============================================================================
# modules/select-disk.sh
# ==============================================================================
# 1. DISK DISCOVERY — map.sh
# ==============================================================================

build_disk_map()
{
    declare -gA DISK_MAP
    DISK_MAP=()

    local index=1
    local disk
    local installer_disk="${AG_HW_USB_DEVICE:-}"
    local installer_real=""

    if [[ -n "$installer_disk" ]]; then
        installer_real="$(get_parent_disk "$installer_disk" 2>/dev/null || true)"
    fi

    while IFS= read -r disk; do

        [[ -n "$disk" ]] || continue

        if [[ -n "$installer_real" ]]; then
            local disk_real
            disk_real="$(get_parent_disk "$disk" 2>/dev/null || true)"

            [[ "$disk_real" == "$installer_real" ]] && continue
        fi

        DISK_MAP["$index"]="$disk"
        index=$((index + 1))

    done < <(
        lsblk -dnpo NAME,TYPE |
        awk '$2 == "disk" { print $1 }'
    )
}

# ==============================================================================
# 2. MENU HEADER — render.sh
# ==============================================================================

render_disk_menu()
{
    printf "\n"
    printf "================================================\n"
    printf " Target Disk Selection\n"
    printf "================================================\n\n"

    printf " Choose the disk on which Arch Linux will be installed.\n"
    printf " The selected disk will eventually be partitioned and\n"
    printf " formatted according to your installation settings.\n\n"

    printf " Nothing will be modified during disk selection.\n\n"

    printf "================================================\n\n"

    if [[ -n "${AG_HW_USB_DEVICE:-}" ]]; then
        printf " Installer USB: %s (excluded)\n\n" \
            "$AG_HW_USB_DEVICE"
    fi
}

# ==============================================================================
# 3. PARTITION DISPLAY — partitions.sh
# ==============================================================================

display_partitions()
{
    local disk="$1"

    local partitions=()
    local name
    local size
    local type
    local label
    local part
    local total
    local count=0

    while read -r name size type; do

        [[ "$type" == "part" ]] || continue

        label="$(lsblk -dnro PARTLABEL "/dev/$name" 2>/dev/null || true)"

        partitions+=("$name|$size|$label")

    done < <(
        lsblk -rno NAME,SIZE,TYPE "$disk"
    )

    total="${#partitions[@]}"

    # Check whether any partition is mounted.
    if lsblk -nrpo MOUNTPOINT "$disk" |
        grep -q '[^[:space:]]'; then
        printf "       ⚠ Mounted partitions detected\n"
    fi

    for part in "${partitions[@]}"; do

        count=$((count + 1))

        IFS='|' read -r name size label <<< "$part"

        if (( count == total )); then
            printf "       └── %-15s %-8s %s\n" \
                "/dev/$name" \
                "$size" \
                "${label:--}"
        else
            printf "       ├── %-15s %-8s %s\n" \
                "/dev/$name" \
                "$size" \
                "${label:--}"
        fi

    done
}

# ==============================================================================
# 4. DISK DISPLAY — display.sh
# ==============================================================================

display_disks()
{
    local key
    local disk
    local size
    local model

    for key in $(printf '%s\n' "${!DISK_MAP[@]}" | sort -n); do

        disk="${DISK_MAP[$key]}"

        size="$(lsblk -dnro SIZE "$disk" 2>/dev/null || true)"
        model="$(lsblk -dnro MODEL "$disk" 2>/dev/null | xargs)"

        printf " [%s] %-15s %-10s %s\n" \
            "$key" "$disk" "${size:--}" "${model:--}"

        display_partitions "$disk"

        printf "\n"
    done
}

# ==============================================================================
# 5. DISK SELECTION — select.sh
# ==============================================================================

select_disk()
{
    local choice="$1"
    local selected
    local selected_real
    local installer_real=""

    if [[ ! "$choice" =~ ^[1-9][0-9]*$ ]] ||
       [[ ! -v "DISK_MAP[$choice]" ]]; then
        printf " Invalid selection.\n"
        return 1
    fi

    selected="${DISK_MAP[$choice]}"

    # Confirm that the selected device still exists.
    if [[ ! -b "$selected" ]]; then
        printf " Invalid block device.\n"
        return 1
    fi

    selected_real="$(get_parent_disk "$selected" 2>/dev/null || true)"

    if [[ -n "${AG_HW_USB_DEVICE:-}" ]]; then
        installer_real="$(get_parent_disk "$AG_HW_USB_DEVICE" 2>/dev/null || true)"
    
        if [[ -n "$installer_real" &&
              "$selected_real" == "$installer_real" ]]; then
            printf " Cannot select the installer USB: %s\n" "$selected"
            return 1
        fi
    fi

    # Commit selection.
    AG_P_DISK="$selected"

    msg "Selected installation disk: $AG_P_DISK"

    return 0
}

# ==============================================================================
# 6. DISK SELECTION CONTROLLER — setter.sh
# ==============================================================================

run_disk()
{
    local choice

    while true; do

        build_disk_map

        clear || true
        render_disk_menu

        if [[ "${#DISK_MAP[@]}" -eq 0 ]]; then
            printf " No usable installation disks found.\n\n"
            printf " Returning to Arch live environment.\n"
            return 1
        fi

        display_disks

        printf "\n"
        printf " Select a disk number: "

        if ! read -r choice; then
            printf "\n Disk selection interrupted.\n"
            return 1
        fi

        if select_disk "$choice"; then
            return 0
        fi

        sleep 1

    done
}
