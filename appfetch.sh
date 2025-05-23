#!/bin/bash

CONFIG_FILE="$HOME/Documents/apps.yaml"

# Configuration: Set preference when both snap and flatpak are available
# Set to true to prefer snap, false to prefer flatpak
PREFER_SNAP=true

# Handle "search" command with multiple apps
if [[ "$1" == "search" ]]; then
    shift
    if (( $# == 0 )); then
        echo "Usage: $0 search app1 app2 ..."
        exit 1
    fi

    search_single_app() {
        local query="${1,,}"  # lowercase query for case-insensitive matching
        local app="" comment="" aliases="" found=0 in_app=0 matched_this_app=0

        print_match_if_needed() {
            if (( matched_this_app == 0 )); then
                local lower_app="${app,,}"
                local lower_aliases="${aliases,,}"
                local lower_comment="${comment,,}"
                if [[ "$lower_app" == *"$query"* || "$lower_aliases" == *"$query"* || "$lower_comment" == *"$query"* ]]; then
                    echo "🔎 $app: $comment"
                    found=1
                    matched_this_app=1
                fi
            fi
        }

        while IFS= read -r line || [[ -n $line ]]; do
            if [[ $line =~ ^([a-zA-Z0-9_-]+): ]]; then
                if (( in_app )); then
                    print_match_if_needed
                fi
                app=${BASH_REMATCH[1]}
                comment=""
                aliases=""
                in_app=1
                matched_this_app=0
                continue
            fi

            if (( in_app )); then
                if [[ $line =~ ^[[:space:]]{2}comment:[[:space:]]*(.*)$ ]]; then
                    comment=${BASH_REMATCH[1]}
                elif [[ $line =~ ^[[:space:]]{2}aliases:[[:space:]]*\[(.*)\] ]]; then
                    aliases=${BASH_REMATCH[1]}
                elif [[ ! $line =~ ^[[:space:]] ]]; then
                    print_match_if_needed
                    in_app=0
                fi
            fi
        done < "$CONFIG_FILE"

        # Final check for last app block
        if (( in_app )); then
            print_match_if_needed
        fi

        if (( found == 0 )); then
            echo "❌ $1: not found"
        fi
    }

    for query in "$@"; do
        search_single_app "$query"
    done
    exit 0
fi

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

# Check if an app has both snap and flatpak options
has_both_snap_and_flatpak() {
    local app=$1
    local snap_pkg=$(get_value "$app" snap)
    local flatpak_pkg=$(get_value "$app" flatpak)
    [[ -n "$snap_pkg" && -n "$flatpak_pkg" ]]
}

# Determine preferred install method based on configuration
get_preferred_method() {
    local app=$1
    local snap_pkg=$(get_value "$app" snap)
    local flatpak_pkg=$(get_value "$app" flatpak)
    local custom_cmd=$(get_value "$app" custom)

    # If custom command exists, always prefer it
    if [[ -n "$custom_cmd" ]]; then
        echo "custom"
        return
    fi

    # If only one method is available, use it
    if [[ -n "$snap_pkg" && -z "$flatpak_pkg" ]]; then
        echo "snap"
        return
    elif [[ -z "$snap_pkg" && -n "$flatpak_pkg" ]]; then
        echo "flatpak"
        return
    fi

    # If both are available, use preference
    if [[ -n "$snap_pkg" && -n "$flatpak_pkg" ]]; then
        if [[ "$PREFER_SNAP" == true ]] && method_available snap; then
            echo "snap"
        elif [[ "$PREFER_SNAP" == false ]] && method_available flatpak; then
            echo "flatpak"
        elif method_available snap; then
            echo "snap"
        elif method_available flatpak; then
            echo "flatpak"
        fi
        return
    fi

    # No method available
    echo "none"
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
    echo "Configuration: PREFER_SNAP is currently set to $PREFER_SNAP"
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

    preferred_method=$(get_preferred_method "$app")
    
    case "$preferred_method" in
        snap)
            snap_pkg=$(get_value "$app" snap)
            snap_apps+=("$snap_pkg")
            if has_both_snap_and_flatpak "$app"; then
                echo "📦 $app: Using snap (preferred over flatpak)"
            fi
            ;;
        flatpak)
            flatpak_pkg=$(get_value "$app" flatpak)
            flatpak_apps+=("$flatpak_pkg")
            if has_both_snap_and_flatpak "$app"; then
                echo "📦 $app: Using flatpak (preferred over snap)"
            fi
            ;;
        custom)
            custom_cmd=$(get_value "$app" custom)
            echo "💾 Installing $app via custom command"
            run_cmd "$custom_cmd"
            ;;
        none)
            echo "⚠️ No install method found for '$input'"
            ;;
    esac
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
