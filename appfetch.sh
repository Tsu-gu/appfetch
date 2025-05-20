#!/bin/bash

CONFIG_FILE="apps.yaml"

# Check if an install method is available
method_available() {
    case "$1" in
        snap) command -v snap >/dev/null ;;
        flatpak) command -v flatpak >/dev/null ;;
        *) return 0 ;;
    esac
}

# Get value for a given app and method (snap, flatpak, custom)
get_value() {
    local app=$1 method=$2 in_app=0
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ ^$app: ]] && in_app=1 && continue
        if (( in_app )); then
            if [[ $line =~ ^[[:space:]]{2}$method:[[:space:]]*(.+)$ ]]; then
                echo "${BASH_REMATCH[1]}"
                return
            elif [[ ! $line =~ ^[[:space:]] ]]; then
                break
            fi
        fi
    done < "$CONFIG_FILE"
}

# Resolve user input to the actual app key (via direct name or alias)
resolve_app_name() {
    local input=$1 app line

    # First: exact app name match
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^([a-zA-Z0-9_-]+): ]]; then
            app=${BASH_REMATCH[1]}
            if [[ "$app" == "$input" ]]; then
                echo "$app"
                return
            fi
        fi
    done < "$CONFIG_FILE"

    # Second: search aliases
    local current
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^([a-zA-Z0-9_-]+): ]]; then
            current=${BASH_REMATCH[1]}
        elif [[ $line =~ ^[[:space:]]{2}aliases:[[:space:]]*\[(.*)\] ]]; then
            IFS=',' read -ra alias_arr <<< "${BASH_REMATCH[1]}"
            for alias in "${alias_arr[@]}"; do
                trimmed=$(echo "$alias" | xargs)
                if [[ "$trimmed" == "$input" ]]; then
                    echo "$current"
                    return
                fi
            done
        fi
    done < "$CONFIG_FILE"

    echo ""  # No match
}

# Execute a custom shell command
run_cmd() {
    local cmd="$1"
    [[ -z "$cmd" ]] && return 1
    echo "➤ Running: $cmd"
    eval "$cmd"
}

# Argument check
if (( $# < 1 )); then
    echo "Usage: $0 app1 app2 ..."
    exit 1
fi

# Arrays for queued installs
snap_apps=()
flatpak_apps=()

# Loop through input arguments
for input in "$@"; do
    app=$(resolve_app_name "$input")

    if [[ -z "$app" ]]; then
        echo "❌ No matching app or alias found for '$input'"
        continue
    fi

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
        echo "⚠️ No install method found for '$input'"
    fi
done

# Execute batch installs
if (( ${#snap_apps[@]} > 0 )); then
    echo "Installing snap packages: ${snap_apps[*]}"
    sudo snap install "${snap_apps[@]}"
fi

if (( ${#flatpak_apps[@]} > 0 )); then
    echo "Installing flatpak packages: ${flatpak_apps[*]}"
    flatpak install -y flathub "${flatpak_apps[@]}"
fi
