#!/bin/bash

# Log Aggregation Script for CheaperForDrug Scraper
# Monitors logs from all 3 Docker containers simultaneously with color-coding
#
# Usage:
#   ./watch-logs.sh [country]
#   ./watch-logs.sh all       # Watch all containers (default)
#   ./watch-logs.sh poland    # Watch only Poland
#   ./watch-logs.sh germany   # Watch only Germany
#   ./watch-logs.sh czech     # Watch only Czech Republic

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# COLOR DEFINITIONS
# ============================================================================

# ANSI Color codes
COLOR_RESET='\033[0m'
COLOR_BOLD='\033[1m'

# Country-specific colors
COLOR_POLAND='\033[0;34m'      # Blue
COLOR_GERMANY='\033[0;32m'     # Green
COLOR_CZECH='\033[0;33m'       # Yellow

# Status colors
COLOR_ERROR='\033[0;31m'       # Red
COLOR_INFO='\033[0;36m'        # Cyan
COLOR_SUCCESS='\033[0;32m'     # Green

# ============================================================================
# CONTAINER CONFIGURATION
# ============================================================================

CONTAINER_POLAND="cheaperfordrug-scraper-poland"
CONTAINER_GERMANY="cheaperfordrug-scraper-germany"
CONTAINER_CZECH="cheaperfordrug-scraper-czech"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Print colored message
print_colored() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${COLOR_RESET}"
}

# Print error and exit
error_exit() {
    print_colored "$COLOR_ERROR" "ERROR: $1" >&2
    exit 1
}

# Check if container is running
is_container_running() {
    local container="$1"
    docker ps --filter "name=${container}" --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"
}

# Get container color
get_country_color() {
    local country="$1"
    case "$country" in
        poland)   echo "$COLOR_POLAND" ;;
        germany)  echo "$COLOR_GERMANY" ;;
        czech)    echo "$COLOR_CZECH" ;;
        *)        echo "$COLOR_RESET" ;;
    esac
}

# Get country label with padding
get_country_label() {
    local country="$1"
    case "$country" in
        poland)   echo "POLAND " ;;
        germany)  echo "GERMANY" ;;
        czech)    echo "CZECH  " ;;
        *)        echo "UNKNOWN" ;;
    esac
}

# Format log line with timestamp and country
format_log_line() {
    local country="$1"
    local line="$2"
    local color=$(get_country_color "$country")
    local label=$(get_country_label "$country")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${color}[${timestamp}] [${label}]${COLOR_RESET} ${line}"
}

# Watch logs for a single container
watch_single_container() {
    local container="$1"
    local country="$2"

    if ! is_container_running "$container"; then
        print_colored "$COLOR_ERROR" "Container $container is not running!"
        return 1
    fi

    print_colored "$(get_country_color $country)" "Watching logs for $container..."
    echo ""

    # Follow container logs with timestamp
    docker logs -f --tail 50 --timestamps "$container" 2>&1 | while IFS= read -r line; do
        format_log_line "$country" "$line"
    done
}

# Watch logs for multiple containers
watch_multiple_containers() {
    local countries=("$@")
    local pids=()

    # Print header
    clear
    print_colored "$COLOR_BOLD" "════════════════════════════════════════════════════════════════"
    print_colored "$COLOR_BOLD" "  CheaperForDrug Scraper - Log Aggregation"
    print_colored "$COLOR_BOLD" "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
    print_colored "$COLOR_BOLD" "════════════════════════════════════════════════════════════════"
    echo ""

    # Check which containers are running
    local active_countries=()
    for country in "${countries[@]}"; do
        local container_var="CONTAINER_${country^^}"
        local container="${!container_var}"

        if is_container_running "$container"; then
            active_countries+=("$country")
            print_colored "$(get_country_color $country)" "✓ $container is running"
        else
            print_colored "$COLOR_ERROR" "✗ $container is NOT running"
        fi
    done

    echo ""

    if [ ${#active_countries[@]} -eq 0 ]; then
        error_exit "No containers are running!"
    fi

    print_colored "$COLOR_INFO" "Watching logs from ${#active_countries[@]} container(s)..."
    print_colored "$COLOR_INFO" "Press Ctrl+C to stop"
    echo ""
    print_colored "$COLOR_BOLD" "────────────────────────────────────────────────────────────────"
    echo ""

    # Start log followers in background
    for country in "${active_countries[@]}"; do
        local container_var="CONTAINER_${country^^}"
        local container="${!container_var}"

        (
            docker logs -f --tail 20 --timestamps "$container" 2>&1 | while IFS= read -r line; do
                format_log_line "$country" "$line"
            done
        ) &

        pids+=($!)
    done

    # Trap Ctrl+C to clean up background processes
    trap 'echo ""; print_colored "$COLOR_INFO" "Stopping log watchers..."; for pid in "${pids[@]}"; do kill $pid 2>/dev/null || true; done; exit 0' SIGINT SIGTERM

    # Wait for all background processes
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
}

# Show usage information
show_usage() {
    cat <<EOF
Usage: $0 [COUNTRY]

Watch Docker container logs in real-time with color-coded output.

ARGUMENTS:
  all         Watch all containers (default)
  poland      Watch only Poland container
  germany     Watch only Germany container
  czech       Watch only Czech Republic container

EXAMPLES:
  $0              # Watch all containers
  $0 all          # Watch all containers
  $0 poland       # Watch only Poland
  $0 germany      # Watch only Germany

COLOR CODING:
  Poland  = Blue
  Germany = Green
  Czech   = Yellow

Press Ctrl+C to stop watching logs.
EOF
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    local country="${1:-all}"

    # Convert to lowercase
    country=$(echo "$country" | tr '[:upper:]' '[:lower:]')

    # Handle help flag
    if [[ "$country" == "-h" ]] || [[ "$country" == "--help" ]]; then
        show_usage
        exit 0
    fi

    # Validate Docker is running
    if ! docker info >/dev/null 2>&1; then
        error_exit "Docker is not running or not accessible!"
    fi

    # Watch logs based on country selection
    case "$country" in
        all)
            watch_multiple_containers "poland" "germany" "czech"
            ;;
        poland|germany|czech)
            local container_var="CONTAINER_${country^^}"
            local container="${!container_var}"
            watch_single_container "$container" "$country"
            ;;
        *)
            print_colored "$COLOR_ERROR" "Invalid country: $country"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# ============================================================================
# ENTRY POINT
# ============================================================================

main "$@"
