#!/bin/bash

CONFIG_FILE="$HOME/Documents/apps.yaml"

method_available() {
    case "$1" in
        snap) command -v snap >/dev/null ;;
        flatpak) command -v flatpak >/dev/null ;;
        *) return 0 ;;  # Assume custom commands always available
    esac
}

get_value() {
    local app=$1 method=$2 in_app=0
    while IFS= read -r line || [[ -n $line ]]; do
        # Detect app start
        [[ $line =~ ^$app: ]] && in_app=1 && continue
        if (( in_app )); then
            # Match method: followed by anything (no quotes needed)
            if [[ $line =~ ^[[:space:]]{2}$method:[[:space:]]*(.+)$ ]]; then
                echo "${BASH_REMATCH[1]}"
                return
            # Stop if new key at same or less indent found
            elif [[ ! $line =~ ^[[:space:]] ]]; then
                break
            fi
        fi
    done < "$CONFIG_FILE"
}

run_cmd() {
    local cmd="$1"
    [[ -z "$cmd" ]] && return 1
    echo "➤ Running: $cmd"
    eval "$cmd"
}

if (( $# < 1 )); then
    echo "Usage: $0 app1 app2 ..."
    exit 1
fi

snap_apps=()
flatpak_apps=()

for app in "$@"; do
    snap_pkg=$(get_value "$app" snap)
    flatpak_pkg=$(get_value "$app" flatpak)
    custom_cmd=$(get_value "$app" custom)

    if [[ -n $snap_pkg && "$(method_available snap && echo yes)" == "yes" ]]; then
        snap_apps+=("$snap_pkg")

    elif [[ -n $flatpak_pkg && "$(method_available flatpak && echo yes)" == "yes" ]]; then
        flatpak_apps+=("$flatpak_pkg")

    elif [[ -n $custom_cmd ]]; then
        echo "Installing $app via custom command"
        run_cmd "$custom_cmd"

    else
        echo "⚠️ No install method found for '$app'"
    fi
done

if (( ${#snap_apps[@]} > 0 )); then
    echo "Installing snap packages: ${snap_apps[*]}"
    sudo snap install "${snap_apps[@]}"
fi

if (( ${#flatpak_apps[@]} > 0 )); then
    echo "Installing flatpak packages: ${flatpak_apps[*]}"
    flatpak install -y flathub "${flatpak_apps[@]}"
fi

