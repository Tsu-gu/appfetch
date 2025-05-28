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

# Global associative array for parsed YAML data
declare -A YAML_DATA

# Simple trim function
trim() {
    local var="$*"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace  
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# Universal YAML parser - loads all data into YAML_DATA
# Format: YAML_DATA["app_name:field"] = "value"
parse_yaml_file() {
    local yaml_file="$1"
    local app="" in_app=false
    
    # Clear previous data
    unset YAML_DATA
    declare -gA YAML_DATA
    
    [[ ! -f "$yaml_file" ]] && return 1
    
    while IFS= read -r line || [[ -n $line ]]; do
        # Match app name line
        if [[ $line =~ ^([a-zA-Z0-9_-]+):$ ]]; then
            app="${BASH_REMATCH[1]}"
            in_app=true
            continue
        fi
        
        # Parse fields if we're in an app block
        if [[ $in_app == true ]]; then
            if [[ $line =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*)$ ]]; then
                local field="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                
                # Trim whitespace safely
                value=$(trim "$value")
                
                # Handle array syntax for aliases
                if [[ $field == "aliases" && $value =~ ^\[([^\]]*)\]$ ]]; then
                    value="${BASH_REMATCH[1]}"
                fi
                
                YAML_DATA["$app:$field"]="$value"
            elif [[ ! $line =~ ^[[:space:]] ]]; then
                # End of app block
                in_app=false
            fi
        fi
    done < "$yaml_file"
}

# Get value for app:field combination
get_app_field() {
    local app="$1" field="$2" default="${3:-}"
    echo "${YAML_DATA["$app:$field"]:-$default}"
}

# Check if app exists in config
app_exists() {
    local app="$1"
    [[ -n "${YAML_DATA["$app:comment"]:-}" ]] || 
    [[ -n "${YAML_DATA["$app:snap"]:-}" ]] || 
    [[ -n "${YAML_DATA["$app:flatpak"]:-}" ]] || 
    [[ -n "${YAML_DATA["$app:custom"]:-}" ]]
}

# Get all app names from loaded data
get_all_apps() {
    local apps=()
    for key in "${!YAML_DATA[@]}"; do
        if [[ $key == *":comment" ]]; then
            apps+=("${key%:*}")
        fi
    done
    printf '%s\n' "${apps[@]}" | sort -u
}

# Resolve input to app name (direct match or alias)
resolve_app_name() {
    local input="$1"
    
    # Try direct app name match first
    if app_exists "$input"; then
        echo "$input"
        return 0
    fi
    
    # Try alias match
    for key in "${!YAML_DATA[@]}"; do
        if [[ $key == *":aliases" ]]; then
            local app="${key%:*}"
            local aliases="${YAML_DATA[$key]}"
            
            IFS=',' read -ra alias_array <<< "$aliases"
            for alias in "${alias_array[@]}"; do
                alias=$(echo "$alias" | xargs)  # trim whitespace
                if [[ "$alias" == "$input" ]]; then
                    echo "$app"
                    return 0
                fi
            done
        fi
    done
    
    return 1
}

# Search for apps matching query
search_apps() {
    local queries=("$@")
    
    for query in "${queries[@]}"; do
        local query_lower="${query,,}"
        local found_this=false
        
        while IFS= read -r app; do
            local app_lower="${app,,}"
            local comment_lower="${YAML_DATA["$app:comment"]:-}"
            comment_lower="${comment_lower,,}"
            local aliases_lower="${YAML_DATA["$app:aliases"]:-}"
            aliases_lower="${aliases_lower,,}"
            
            if [[ "$app_lower" == *"$query_lower"* ]] || 
               [[ "$comment_lower" == *"$query_lower"* ]] || 
               [[ "$aliases_lower" == *"$query_lower"* ]]; then
                log_search "$app: ${YAML_DATA["$app:comment"]:-}"
                found_this=true
            fi
        done < <(get_all_apps)
        
        if [[ $found_this == false ]]; then
            log_error "$query: not found"
        fi
    done
}

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

# Get installed app info using the same parser
get_installed_app_info() {
    local app="$1"
    
    ensure_installed_file
    parse_yaml_file "$INSTALLED_FILE"
    
    local method=$(get_app_field "$app" "method")
    local package=$(get_app_field "$app" "package")
    local installed_at=$(get_app_field "$app" "installed_at")
    
    if [[ -n "$method" && -n "$package" ]]; then
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
# List installed apps
list_installed_apps() {
    ensure_installed_file
    
    if [[ ! -s "$INSTALLED_FILE" ]]; then
        log_info "No apps installed via appfetch yet"
        return 0
    fi
    
    echo "📦 Apps installed via appfetch:"
    echo
    
    parse_yaml_file "$INSTALLED_FILE"
    
    # Get apps from installed file (look for any key, not just :comment)
    local apps=()
    for key in "${!YAML_DATA[@]}"; do
        if [[ $key == *":method" ]]; then  # Use :method instead of :comment
            apps+=("${key%:*}")
        fi
    done
    
    # Sort and process apps
    while IFS= read -r app; do
        local method=$(get_app_field "$app" "method")
        local package=$(get_app_field "$app" "package")
        
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
    done < <(printf '%s\n' "${apps[@]}" | sort -u)
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

# Install packages via package manager
install_via_manager() {
    local manager="$1"
    shift
    local packages=("$@")
    
    case "$manager" in
        snap)
            log_info "Installing ${#packages[@]} snap packages: ${packages[*]}"
            sudo snap install "${packages[@]}"
            ;;
        flatpak)
            log_info "Installing ${#packages[@]} flatpak packages: ${packages[*]}"
            flatpak install -y flathub "${packages[@]}"
            ;;
        *)
            return 1
            ;;
    esac
}

# Remove packages via package manager
remove_via_manager() {
    local manager="$1"
    shift
    local packages=("$@")
    
    case "$manager" in
        snap)
            log_info "Removing ${#packages[@]} snap packages: ${packages[*]}"
            sudo snap remove "${packages[@]}"
            ;;
        flatpak)
            log_info "Removing ${#packages[@]} flatpak packages: ${packages[*]}"
            flatpak uninstall -y "${packages[@]}"
            ;;
        *)
            return 1
            ;;
    esac
}

# Process app installation queue
process_install_queue() {
    local manager="$1"
    shift
    local queue=("$@")
    
    if (( ${#queue[@]} == 0 )); then
        return 0
    fi
    
    echo
    if install_via_manager "$manager" "${queue[@]}"; then
        log_success "${manager^} packages installed successfully"
        
        # Record installed packages
        for pkg in "${queue[@]}"; do
            # Find which app this package belongs to
            while IFS= read -r app; do
                local app_pkg=$(get_app_field "$app" "$manager")
                if [[ "$app_pkg" == "$pkg" ]]; then
                    record_installed_app "$app" "$manager" "$pkg"
                    break
                fi
            done < <(get_all_apps)
        done
        return 0
    else
        log_error "Some $manager packages failed to install. You can report this via appfetch bug"
        return 1
    fi
}

# Process app removal queue
# Process app removal queue
process_remove_queue() {
    local manager="$1"
    shift
    local queue=("$@")
    
    if (( ${#queue[@]} == 0 )); then
        return 0
    fi
    
    echo
    if remove_via_manager "$manager" "${queue[@]}"; then
        log_success "${manager^} packages removed successfully"
        
        # Remove from installed list
        ensure_installed_file
        parse_yaml_file "$INSTALLED_FILE"
        
        # Get apps from installed file
        local installed_apps=()
        for key in "${!YAML_DATA[@]}"; do
            if [[ $key == *":method" ]]; then
                installed_apps+=("${key%:*}")
            fi
        done
        
        for pkg in "${queue[@]}"; do
            # Find apps that used this package
            for app in "${installed_apps[@]}"; do
                local install_method=$(get_app_field "$app" "method")
                local install_package=$(get_app_field "$app" "package")
                if [[ "$install_method" == "$manager" && "$install_package" == "$pkg" ]]; then
                    remove_from_installed "$app"
                fi
            done
        done
        return 0
    else
        log_error "Some $manager packages failed to remove"
        return 1
    fi
}

# Main installation logic
install_apps() {
    local apps=("$@")
    local snap_queue=()
    local flatpak_queue=()
    local failed_apps=()
    
    # Load configuration
    parse_yaml_file "$CONFIG_FILE"
    
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
            log_warning "Using mpm to search for $input because it's not in the database"
            if [[ -x "$HOME/Applications/mpm.bin" ]]; then
                "$HOME/Applications/mpm.bin" -v CRITICAL search "$input"
            else
                log_error "mpm not installed. Install it by typing appfetch mpm"
            fi
            failed_apps+=("$input")
            continue
        fi
        
        local snap_pkg=$(get_app_field "$resolved_app" "snap")
        local flatpak_pkg=$(get_app_field "$resolved_app" "flatpak")
        local custom_cmd=$(get_app_field "$resolved_app" "custom")
        
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
    
    if ! process_install_queue "snap" "${snap_queue[@]}"; then
        install_success=false
    fi
    
    if ! process_install_queue "flatpak" "${flatpak_queue[@]}"; then
        install_success=false
    fi
    
    # Summary
    if (( ${#failed_apps[@]} > 0 )); then
        echo
        log_error "Failed to process: ${failed_apps[*]}"
        install_success=false
    fi
    
    return $([[ $install_success == true ]] && echo 0 || echo 1)
}


# Remove/uninstall apps
# Remove/uninstall apps
remove_apps() {
    local apps=("$@")
    local snap_queue=()
    local flatpak_queue=()
    local custom_apps=()
    local failed_apps=()
    
    # Load configuration for custom uninstall commands
    parse_yaml_file "$CONFIG_FILE"
    
    # Store config data before we parse installed file
    declare -A CONFIG_DATA
    for key in "${!YAML_DATA[@]}"; do
        CONFIG_DATA["$key"]="${YAML_DATA[$key]}"
    done
    
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
    
    if ! process_remove_queue "snap" "${snap_queue[@]}"; then
        removal_success=false
    fi
    
    if ! process_remove_queue "flatpak" "${flatpak_queue[@]}"; then
        removal_success=false
    fi
    
    # Handle custom apps - restore config data first
    for key in "${!CONFIG_DATA[@]}"; do
        YAML_DATA["$key"]="${CONFIG_DATA[$key]}"
    done
    
    for app in "${custom_apps[@]}"; do
        echo
        local uninstall_cmd=$(get_app_field "$app" "uninstall")
        
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
            parse_yaml_file "$CONFIG_FILE"
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
            echo "appfetch version 28.5.2025"
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
