#!/bin/bash

set -euo pipefail

# Configuration
CONFIG_FILE="$HOME/Documents/apps.yaml"
INSTALLED_FILE="$HOME/.local/share/appfetch/installed.yaml"
PREFER_SNAP=true

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[1;36m'
readonly NC='\033[0m' # No Color

# Logging functions
log_error() { echo -e "${RED}❌ $*${NC}" >&2; }
log_success() { echo -e "${GREEN}✅ $*${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
log_search() { echo -e "🔎 $*"; }

# Ensure installed apps tracking file exists
ensure_installed_file() {
    local dir=$(dirname "$INSTALLED_FILE")
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
    if [[ ! -f "$INSTALLED_FILE" ]]; then
        touch "$INSTALLED_FILE"
    fi
}

# Record installed app
record_installed_app() {
    local app="$1"
    local method="$2"  # snap, flatpak, or custom
    local package="$3" # package name or custom command
    local timestamp=$(date -Iseconds)
    
    ensure_installed_file
    
    # Remove existing entry if present
    if grep -q "^$app:" "$INSTALLED_FILE" 2>/dev/null; then
        sed -i "/^$app:/,/^[^[:space:]]/{ /^[^[:space:]]/!d; /^$app:/d; }" "$INSTALLED_FILE"
    fi
    
    # Add new entry
    cat >> "$INSTALLED_FILE" << EOF
$app:
  method: $method
  package: $package
  installed_at: $timestamp

EOF
}

# Get installed app info
get_installed_app_info() {
    local app="$1"
    local method="" package="" installed_at=""
    local in_app=false
    
    ensure_installed_file
    
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^([a-zA-Z0-9_-]+):$ ]]; then
            if [[ $in_app == true && "$app" == "${BASH_REMATCH[1]}" ]]; then
                echo "$method§$package§$installed_at"
                return 0
            fi
            
            if [[ "${BASH_REMATCH[1]}" == "$app" ]]; then
                in_app=true
                method="" package="" installed_at=""
            else
                in_app=false
            fi
            continue
        fi
        
        if [[ $in_app == true ]]; then
            if [[ $line =~ ^[[:space:]]+method:[[:space:]]*(.+)$ ]]; then
                method="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^[[:space:]]+package:[[:space:]]*(.+)$ ]]; then
                package="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^[[:space:]]+installed_at:[[:space:]]*(.+)$ ]]; then
                installed_at="${BASH_REMATCH[1]}"
            elif [[ ! $line =~ ^[[:space:]] ]]; then
                break
            fi
        fi
    done < "$INSTALLED_FILE"
    
    # Handle case where target app is the last one in file
    if [[ $in_app == true ]]; then
        echo "$method§$package§$installed_at"
        return 0
    fi
    
    return 1
}

# Remove app from installed list
remove_from_installed() {
    local app="$1"
    
    ensure_installed_file
    
    if grep -q "^$app:" "$INSTALLED_FILE" 2>/dev/null; then
        # Create temp file and remove the app block
        local temp_file=$(mktemp)
        local in_app=false
        
        while IFS= read -r line || [[ -n $line ]]; do
            if [[ $line =~ ^([a-zA-Z0-9_-]+):$ ]]; then
                if [[ "${BASH_REMATCH[1]}" == "$app" ]]; then
                    in_app=true
                    continue
                else
                    in_app=false
                fi
            fi
            
            if [[ $in_app == true ]]; then
                if [[ ! $line =~ ^[[:space:]] ]]; then
                    in_app=false
                    echo "$line" >> "$temp_file"
                fi
            else
                echo "$line" >> "$temp_file"
            fi
        done < "$INSTALLED_FILE"
        
        mv "$temp_file" "$INSTALLED_FILE"
    fi
}

# List installed apps
list_installed_apps() {
    ensure_installed_file
    
    if [[ ! -s "$INSTALLED_FILE" ]]; then
        log_info "No apps installed via appfetch yet"
        return 0
    fi
    
    echo "📦 Apps installed via appfetch:"
    echo
    
    local app="" in_app=false
    local method="" package=""
    local apps_data=()
    
    # First pass: collect all data
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^([a-zA-Z0-9_-]+):$ ]]; then
            # Store previous app info if we were in one
            if [[ $in_app == true ]]; then
                apps_data+=("$app|$method|$package")
            fi
            
            app="${BASH_REMATCH[1]}"
            method="" package=""
            in_app=true
            continue
        fi
        
        if [[ $in_app == true ]]; then
            if [[ $line =~ ^[[:space:]]+method:[[:space:]]*(.+)$ ]]; then
                method="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^[[:space:]]+package:[[:space:]]*(.+)$ ]]; then
                package="${BASH_REMATCH[1]}"
            elif [[ ! $line =~ ^[[:space:]] ]]; then
                # End of app block
                apps_data+=("$app|$method|$package")
                in_app=false
            fi
        fi
    done < "$INSTALLED_FILE"
    
    # Handle the last app in file
    if [[ $in_app == true ]]; then
        apps_data+=("$app|$method|$package")
    fi
    
    # Second pass: format and display
    for app_data in "${apps_data[@]}"; do
        IFS='|' read -r app method package <<< "$app_data"
        
        # Format based on method
        case "$method" in
            snap|flatpak)
                printf "  %-20s %s\n" "$app" "$method"
                ;;
            custom)
                if [[ ${#package} -gt 60 ]]; then
                    # Truncate long commands and add ellipsis
                    local truncated="${package:0:57}..."
                    printf "  %-20s custom %s\n" "$app" "$truncated"
                else
                    printf "  %-20s custom %s\n" "$app" "$package"
                fi
                ;;
        esac
    done
}

# Validate configuration
validate_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    if [[ "$PREFER_SNAP" != "true" && "$PREFER_SNAP" != "false" ]]; then
        log_warning "Invalid PREFER_SNAP value. Using default: true"
        PREFER_SNAP=true
    fi
}

# Check if package manager is available and working
check_package_manager() {
    case "$1" in
        snap)
            command -v snap >/dev/null 2>&1 || return 1
            snap list >/dev/null 2>&1 || return 1
            ;;
        flatpak)
            command -v flatpak >/dev/null 2>&1 || return 1
            flatpak list >/dev/null 2>&1 || return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# Parse a single app block from YAML and return all fields
parse_app_block() {
    local target_app="$1"
    local app="" in_app=false
    local snap="" flatpak="" custom="" uninstall="" comment="" aliases=""
    
    while IFS= read -r line || [[ -n $line ]]; do
        # Match app name line
        if [[ $line =~ ^([a-zA-Z0-9_-]+):$ ]]; then
            # If we were parsing an app and found a new one
            if [[ $in_app == true && "$app" == "$target_app" ]]; then
                echo "$snap§$flatpak§$custom§$uninstall§$comment§$aliases"
                return 0
            fi
            
            app="${BASH_REMATCH[1]}"
            if [[ "$app" == "$target_app" ]]; then
                in_app=true
                snap="" flatpak="" custom="" uninstall="" comment="" aliases=""
            else
                in_app=false
            fi
            continue
        fi
        
        # Parse fields if we're in the target app block
        if [[ $in_app == true ]]; then
            if [[ $line =~ ^[[:space:]]+snap:[[:space:]]*(.+)$ ]]; then
                snap="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^[[:space:]]+flatpak:[[:space:]]*(.+)$ ]]; then
                flatpak="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^[[:space:]]+custom:[[:space:]]*(.+)$ ]]; then
                custom="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^[[:space:]]+uninstall:[[:space:]]*(.+)$ ]]; then
                uninstall="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^[[:space:]]+comment:[[:space:]]*(.+)$ ]]; then
                comment="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^[[:space:]]+aliases:[[:space:]]*\[([^\]]*)\] ]]; then
                aliases="${BASH_REMATCH[1]}"
            elif [[ ! $line =~ ^[[:space:]] ]]; then
                # End of current app block
                break
            fi
        fi
    done < "$CONFIG_FILE"
    
    # Handle case where target app is the last one in file
    if [[ $in_app == true && "$app" == "$target_app" ]]; then
        echo "$snap§$flatpak§$custom§$uninstall§$comment§$aliases"
        return 0
    fi
    
    return 1
}

# Search for apps matching query
search_apps() {
    local queries=("$@")
    
    for query in "${queries[@]}"; do
        local query_lower="${query,,}"
        local found_this=false
        local app="" in_app=false
        local comment="" aliases=""
        
        # Function to check and print match
        check_and_print_match() {
            local app_lower="${app,,}"
            local comment_lower="${comment,,}" 
            local aliases_lower="${aliases,,}"
            
            if [[ "$app_lower" == *"$query_lower"* ]] || 
               [[ "$comment_lower" == *"$query_lower"* ]] || 
               [[ "$aliases_lower" == *"$query_lower"* ]]; then
                log_search "$app: $comment"
                found_this=true
            fi
        }
        
        while IFS= read -r line || [[ -n $line ]]; do
            if [[ $line =~ ^([a-zA-Z0-9_-]+):$ ]]; then
                # Check previous app before moving to next
                if [[ $in_app == true ]]; then
                    check_and_print_match
                fi
                
                # Start new app
                app="${BASH_REMATCH[1]}"
                comment=""
                aliases=""
                in_app=true
                continue
            fi
            
            if [[ $in_app == true ]]; then
                if [[ $line =~ ^[[:space:]]+comment:[[:space:]]*(.*)$ ]]; then
                    comment="${BASH_REMATCH[1]}"
                elif [[ $line =~ ^[[:space:]]+aliases:[[:space:]]*\[([^\]]*)\] ]]; then
                    aliases="${BASH_REMATCH[1]}"
                elif [[ ! $line =~ ^[[:space:]] ]]; then
                    # End of app block - check before resetting
                    check_and_print_match
                    in_app=false
                fi
            fi
        done < "$CONFIG_FILE"
        
        # Check the final app in file
        if [[ $in_app == true ]]; then
            check_and_print_match
        fi
        
        if [[ $found_this == false ]]; then
            log_error "$query: not found"
        fi
    done
}

# Resolve input to app name (direct match or alias)
resolve_app_name() {
    local input="$1"
    local app="" in_app=false
    
    # Try direct app name match first
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^([a-zA-Z0-9_-]+):$ ]]; then
            app="${BASH_REMATCH[1]}"
            if [[ "$app" == "$input" ]]; then
                echo "$app"
                return 0
            fi
        fi
    done < "$CONFIG_FILE"
    
    # Try alias match
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^([a-zA-Z0-9_-]+):$ ]]; then
            app="${BASH_REMATCH[1]}"
            in_app=true
            continue
        fi
        
        if [[ $in_app == true ]]; then
            if [[ $line =~ ^[[:space:]]+aliases:[[:space:]]*\[([^\]]*)\] ]]; then
                local aliases="${BASH_REMATCH[1]}"
                IFS=',' read -ra alias_array <<< "$aliases"
                for alias in "${alias_array[@]}"; do
                    alias=$(echo "$alias" | xargs)  # trim whitespace
                    if [[ "$alias" == "$input" ]]; then
                        echo "$app"
                        return 0
                    fi
                done
            elif [[ ! $line =~ ^[[:space:]] ]]; then
                in_app=false
            fi
        fi
    done < "$CONFIG_FILE"
    
    return 1
}

# Execute custom command with error handling
execute_custom_command() {
    local app="$1"
    local cmd="$2"
    
    log_info "Installing $app via custom command"
    echo "➤ Running: $cmd"
    
    if eval "$cmd"; then
        log_success "$app installed successfully"
        record_installed_app "$app" "custom" "$cmd"
    else
        log_error "Failed to install $app via custom command. You can report this by typing appfetch bug."
        return 1
    fi
}

# Execute custom uninstall command
execute_custom_uninstall() {
    local app="$1"
    local cmd="$2"
    
    log_info "Uninstalling $app via custom command"
    echo "➤ Running: $cmd"
    
    if eval "$cmd"; then
        log_success "$app uninstalled successfully"
        remove_from_installed "$app"
    else
        log_error "Failed to uninstall $app via custom command"
        return 1
    fi
}

# Remove/uninstall apps
remove_apps() {
    local apps=("$@")
    local snap_queue=()
    local flatpak_queue=()
    local custom_apps=()
    local failed_apps=()
    
    # Process each app
    for input in "${apps[@]}"; do
        local resolved_app
        if ! resolved_app=$(resolve_app_name "$input"); then
            log_error "No matching app or alias found for '$input'"
            failed_apps+=("$input")
            continue
        fi
        
        # Check if app is installed via appfetch
        local install_info
        if ! install_info=$(get_installed_app_info "$resolved_app"); then
            log_error "$resolved_app: not installed via appfetch"
            failed_apps+=("$input")
            continue
        fi
        
        IFS='§' read -r method package installed_at <<< "$install_info"
        
        case "$method" in
            snap)
                snap_queue+=("$package")
                ;;
            flatpak)
                flatpak_queue+=("$package")
                ;;
            custom)
                custom_apps+=("$resolved_app")
                ;;
            *)
                log_error "$resolved_app: unknown installation method '$method'"
                failed_apps+=("$input")
                ;;
        esac
    done
    
    # Execute batch removals
    local removal_success=true
    
    if (( ${#snap_queue[@]} > 0 )); then
        echo
        log_info "Removing ${#snap_queue[@]} snap packages: ${snap_queue[*]}"
        if sudo snap remove "${snap_queue[@]}"; then
            log_success "Snap packages removed successfully"
            # Remove from installed list
            for pkg in "${snap_queue[@]}"; do
                for input in "${apps[@]}"; do
                    local resolved_app
                    if resolved_app=$(resolve_app_name "$input"); then
                        local install_info
                        if install_info=$(get_installed_app_info "$resolved_app"); then
                            IFS='§' read -r method package installed_at <<< "$install_info"
                            if [[ "$method" == "snap" && "$package" == "$pkg" ]]; then
                                remove_from_installed "$resolved_app"
                                break
                            fi
                        fi
                    fi
                done
            done
        else
            log_error "Some snap packages failed to remove"
            removal_success=false
        fi
    fi
    
    if (( ${#flatpak_queue[@]} > 0 )); then
        echo
        log_info "Removing ${#flatpak_queue[@]} flatpak packages: ${flatpak_queue[*]}"
        if flatpak uninstall -y "${flatpak_queue[@]}"; then
            log_success "Flatpak packages removed successfully"
            # Remove from installed list
            for pkg in "${flatpak_queue[@]}"; do
                for input in "${apps[@]}"; do
                    local resolved_app
                    if resolved_app=$(resolve_app_name "$input"); then
                        local install_info
                        if install_info=$(get_installed_app_info "$resolved_app"); then
                            IFS='§' read -r method package installed_at <<< "$install_info"
                            if [[ "$method" == "flatpak" && "$package" == "$pkg" ]]; then
                                remove_from_installed "$resolved_app"
                                break
                            fi
                        fi
                    fi
                done
            done
        else
            log_error "Some flatpak packages failed to remove"
            removal_success=false
        fi
    fi
    
    # Handle custom apps
    for app in "${custom_apps[@]}"; do
        echo
        local app_data
        if ! app_data=$(parse_app_block "$app"); then
            log_error "Failed to parse data for '$app'"
            failed_apps+=("$app")
            continue
        fi
        
        IFS='§' read -r snap_pkg flatpak_pkg custom_cmd uninstall_cmd comment aliases <<< "$app_data"
        
        if [[ -n "$uninstall_cmd" ]]; then
            execute_custom_uninstall "$app" "$uninstall_cmd"
        else
            log_error "$app: no uninstall command defined"
            failed_apps+=("$app")
        fi
    done
    
    # Summary
    if (( ${#failed_apps[@]} > 0 )); then
        echo
        log_error "Failed to remove: ${failed_apps[*]}"
        removal_success=false
    fi
    
    return $([[ $removal_success == true ]] && echo 0 || echo 1)
}

# Main installation logic
install_apps() {
    local apps=("$@")
    local snap_queue=()
    local flatpak_queue=()
    local failed_apps=()
    
    # Validate package managers upfront
    local snap_available=false
    local flatpak_available=false
    
    if check_package_manager snap; then
        snap_available=true
    else
        log_warning "Snap is not available or not working"
    fi
    
    if check_package_manager flatpak; then
        flatpak_available=true
    else
        log_warning "Flatpak is not available or not working"
    fi
    
    # Process each app
    for input in "${apps[@]}"; do
        local resolved_app
        if ! resolved_app=$(resolve_app_name "$input"); then
            log_error "No matching app or alias found for '$input'"
            failed_apps+=("$input")
            continue
        fi
        
        local app_data
        if ! app_data=$(parse_app_block "$resolved_app"); then
            log_error "Failed to parse data for '$resolved_app'"
            failed_apps+=("$input")
            continue
        fi
        
        IFS='§' read -r snap_pkg flatpak_pkg custom_cmd uninstall_cmd comment aliases <<< "$app_data"
        
        # Determine best installation method
        if [[ -n "$custom_cmd" ]]; then
            execute_custom_command "$resolved_app" "$custom_cmd"
        elif [[ -n "$snap_pkg" && -n "$flatpak_pkg" ]]; then
            # Both available, use preference
            if [[ "$PREFER_SNAP" == "true" && "$snap_available" == "true" ]]; then
                snap_queue+=("$snap_pkg")
            elif [[ "$PREFER_SNAP" == "false" && "$flatpak_available" == "true" ]]; then
                flatpak_queue+=("$flatpak_pkg")
            elif [[ "$snap_available" == "true" ]]; then
                snap_queue+=("$snap_pkg")
                log_warning "$resolved_app: Using snap (flatpak not available)"
            elif [[ "$flatpak_available" == "true" ]]; then
                flatpak_queue+=("$flatpak_pkg")
                log_warning "$resolved_app: Using flatpak (snap not available)"
            else
                log_error "$resolved_app: Neither snap nor flatpak is available"
                failed_apps+=("$input")
            fi
        elif [[ -n "$snap_pkg" && "$snap_available" == "true" ]]; then
            snap_queue+=("$snap_pkg")
        elif [[ -n "$flatpak_pkg" && "$flatpak_available" == "true" ]]; then
            flatpak_queue+=("$flatpak_pkg")
        else
            log_error "No available installation method for '$input'"
            failed_apps+=("$input")
        fi
    done
    
    # Execute batch installations
    local install_success=true
    
    if (( ${#snap_queue[@]} > 0 )); then
        echo
        log_info "Installing ${#snap_queue[@]} snap packages: ${snap_queue[*]}"
        if sudo snap install "${snap_queue[@]}"; then
            log_success "Snap packages installed successfully"
            # Record installed packages
            for pkg in "${snap_queue[@]}"; do
                for input in "${apps[@]}"; do
                    local resolved_app
                    if resolved_app=$(resolve_app_name "$input"); then
                        local app_data
                        if app_data=$(parse_app_block "$resolved_app"); then
                            IFS='§' read -r snap_pkg flatpak_pkg custom_cmd uninstall_cmd comment aliases <<< "$app_data"
                            if [[ "$snap_pkg" == "$pkg" ]]; then
                                record_installed_app "$resolved_app" "snap" "$pkg"
                                break
                            fi
                        fi
                    fi
                done
            done
        else
            log_error "Some snap packages failed to install. You can report this via appfetch bug"
            install_success=false
        fi
    fi
    
    if (( ${#flatpak_queue[@]} > 0 )); then
        echo
        log_info "Installing ${#flatpak_queue[@]} flatpak packages: ${flatpak_queue[*]}"
        if flatpak install -y flathub "${flatpak_queue[@]}"; then
            log_success "Flatpak packages installed successfully"
            # Record installed packages
            for pkg in "${flatpak_queue[@]}"; do
                for input in "${apps[@]}"; do
                    local resolved_app
                    if resolved_app=$(resolve_app_name "$input"); then
                        local app_data
                        if app_data=$(parse_app_block "$resolved_app"); then
                            IFS='§' read -r snap_pkg flatpak_pkg custom_cmd uninstall_cmd comment aliases <<< "$app_data"
                            if [[ "$flatpak_pkg" == "$pkg" ]]; then
                                record_installed_app "$resolved_app" "flatpak" "$pkg"
                                break
                            fi
                        fi
                    fi
                done
            done
        else
            log_error "Some flatpak packages failed to install. You can report this via appfetch bug"
            install_success=false
        fi
    fi
    
    # Summary
    if (( ${#failed_apps[@]} > 0 )); then
        echo
        log_error "Failed to process: ${failed_apps[*]}"
        install_success=false
    fi
    
    return $([[ $install_success == true ]] && echo 0 || echo 1)
}

# Show usage information
show_usage() {
    cat << EOF
Usage: appfetch <command> [args...]

Commands:
  appfetch search <query>...       Search for apps matching query
  appfetch <app>...                Install specified apps
  appfetch list-installed          List apps installed via appfetch
  appfetch remove <app>...         Remove/uninstall specified apps
  appfetch update                  Update apps database
  appfetch version                 Show version information
  appfetch bug                     Report a bug or request an app

Configuration:
  change this variable PREFER_SNAP=$PREFER_SNAP  if you want to prefer snap over flatpak when both available
  sudo nano /usr/local/bin/appfetch

Examples:
  appfetch search video            Search for apps with 'video' in name/comment
  appfetch vlc firefox             Install VLC and Firefox
  appfetch list-installed          Show all installed apps
  appfetch remove vlc firefox      Remove VLC and Firefox
  appfetch update                  Update the apps database
  appfetch bug                     Report an issue

EOF
}

# Main script logic
main() {
    validate_config
    
    if (( $# == 0 )); then
        show_usage
        exit 1
    fi
    
    case "$1" in
        search)
            shift
            if (( $# == 0 )); then
                log_error "Search requires at least one query"
                show_usage
                exit 1
            fi
            search_apps "$@"
            ;;
        list-installed)
            list_installed_apps
            ;;
        remove)
            shift
            if (( $# == 0 )); then
                log_error "Remove requires at least one app"
                show_usage
                exit 1
            fi
            remove_apps "$@"
            ;;
        update)
            log_info "Updating apps database..."
            if wget -O "$HOME/Documents/apps.yaml" "https://raw.githubusercontent.com/Tsu-gu/appfetch/refs/heads/main/apps.yaml"; then
                log_success "Database updated successfully"
            else
                log_error "Failed to update database"
                exit 1
            fi
            ;;
        version)
            echo "appfetch version 24.5.2025"
            ;;
        bug|bugreport|bug-report|report|report-bug)
            log_info "Opening bug report page..."
            xdg-open "https://github.com/Tsu-gu/appfetch/issues/new?body=%23%20I%20would%20like%20to%20report%20a%3A%0Amissing%20app%2Fbug%2Fbroken%20install%20script%0A%0A%23%20The%20missing%20app%3A"
            ;;
        *)
            install_apps "$@"
            ;;
    esac
}

main "$@"
