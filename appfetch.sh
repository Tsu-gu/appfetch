#!/bin/bash

set -euo pipefail

# Configuration
CONFIG_FILE="$HOME/Documents/apps.yaml"
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
    local snap="" flatpak="" custom="" comment="" aliases=""
    
    while IFS= read -r line || [[ -n $line ]]; do
        # Match app name line
        if [[ $line =~ ^([a-zA-Z0-9_-]+):$ ]]; then
            # If we were parsing an app and found a new one
            if [[ $in_app == true && "$app" == "$target_app" ]]; then
                echo "$snap|$flatpak|$custom|$comment|$aliases"
                return 0
            fi
            
            app="${BASH_REMATCH[1]}"
            if [[ "$app" == "$target_app" ]]; then
                in_app=true
                snap="" flatpak="" custom="" comment="" aliases=""
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
        echo "$snap|$flatpak|$custom|$comment|$aliases"
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
    else
        log_error "Failed to install $app via custom command. You can report this by typing appfetch bug."
        return 1
    fi
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
        
        IFS='|' read -r snap_pkg flatpak_pkg custom_cmd comment aliases <<< "$app_data"
        
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
Usage: appfetch app1 app2 ...

Commands:
  appfetch search <query>...    Search for apps matching query
  appfetch <app>...             Install specified apps

Configuration:
  change this variable PREFER_SNAP=$PREFER_SNAP  if you want to prefer snap over flatpak when both available
  sudo nano /usr/local/bin/appfetch

Examples:
  appfetch search video         # Search for apps with 'video' in name/comment
  appfetch vlc firefox          # Install VLC and Firefox
  appfetch minecraft mullvad    # Install using aliases

EOF
}

# Main script logic
main() {
    validate_config
    
    if (( $# == 0 )); then
        show_usage
        exit 1
    fi
    
    if [[ "$1" == "search" ]]; then
        shift
        if (( $# == 0 )); then
            log_error "Search requires at least one query"
            show_usage
            exit 1
        fi
        search_apps "$@"
    else
        install_apps "$@"
    fi
}

main "$@"
