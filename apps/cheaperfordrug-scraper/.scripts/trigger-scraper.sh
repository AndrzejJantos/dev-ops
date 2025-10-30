#!/bin/bash

# Manual Scraper Trigger Script for CheaperForDrug
# Triggers scrapers in specified containers with validation
#
# Usage:
#   ./trigger-scraper.sh [country]
#   ./trigger-scraper.sh all       # Trigger all containers
#   ./trigger-scraper.sh poland    # Trigger only Poland
#   ./trigger-scraper.sh germany   # Trigger only Germany
#   ./trigger-scraper.sh czech     # Trigger only Czech

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURATION
# ============================================================================

CONTAINER_POLAND="cheaperfordrug-scraper-poland"
CONTAINER_GERMANY="cheaperfordrug-scraper-germany"
CONTAINER_CZECH="cheaperfordrug-scraper-czech"

SCRAPER_SCRIPT="/app/docker-scripts/run-scraper.sh"

# Timeout for VPN check (seconds)
VPN_CHECK_TIMEOUT=10

# ============================================================================
# COLOR DEFINITIONS
# ============================================================================

COLOR_RESET='\033[0m'
COLOR_BOLD='\033[1m'
COLOR_SUCCESS='\033[0;32m'
COLOR_ERROR='\033[0;31m'
COLOR_WARNING='\033[0;33m'
COLOR_INFO='\033[0;36m'
COLOR_POLAND='\033[0;34m'
COLOR_GERMANY='\033[0;32m'
COLOR_CZECH='\033[0;33m'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Print colored message
print_colored() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${COLOR_RESET}"
}

# Print section header
print_header() {
    local message="$1"
    echo ""
    print_colored "$COLOR_BOLD" "════════════════════════════════════════════════════════════════"
    print_colored "$COLOR_BOLD" "  $message"
    print_colored "$COLOR_BOLD" "════════════════════════════════════════════════════════════════"
    echo ""
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

# Check if container is healthy
is_container_healthy() {
    local container="$1"
    local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
    [[ "$health" == "healthy" ]] || [[ "$health" == "none" ]]
}

# Check if scrapers are already running in container
are_scrapers_running() {
    local container="$1"
    local count=$(docker exec "$container" ps aux 2>/dev/null | grep -c "node.*scraper" || echo "0")
    [[ "$count" -gt 1 ]]  # More than 1 means scrapers are running (1 is the grep itself)
}

# Check VPN connection status
check_vpn_status() {
    local container="$1"
    local country_name="$2"

    print_colored "$COLOR_INFO" "Checking VPN status for $country_name..."

    # Check if nordvpn is connected
    local vpn_status=$(docker exec "$container" timeout $VPN_CHECK_TIMEOUT nordvpn status 2>/dev/null | grep -i "Status:" | awk '{print $2}' || echo "Unknown")

    if [[ "$vpn_status" == "Connected" ]]; then
        print_colored "$COLOR_SUCCESS" "✓ VPN is connected"

        # Get VPN IP and location
        local vpn_ip=$(docker exec "$container" timeout 5 curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "unknown")
        local vpn_country=$(docker exec "$container" nordvpn status 2>/dev/null | grep -i "Country:" | cut -d: -f2 | xargs || echo "unknown")

        print_colored "$COLOR_INFO" "  IP: $vpn_ip"
        print_colored "$COLOR_INFO" "  Location: $vpn_country"
        return 0
    else
        print_colored "$COLOR_WARNING" "⚠ VPN is NOT connected (Status: $vpn_status)"
        print_colored "$COLOR_WARNING" "  Scrapers may not work correctly without VPN!"
        return 1
    fi
}

# Trigger scraper in container
trigger_scraper() {
    local container="$1"
    local country="$2"
    local country_name="$3"
    local color="$4"

    print_header "$country_name Scraper"

    # Check if container is running
    if ! is_container_running "$container"; then
        print_colored "$COLOR_ERROR" "✗ Container $container is NOT running!"
        print_colored "$COLOR_ERROR" "  Start the container first: docker start $container"
        return 1
    fi

    print_colored "$COLOR_SUCCESS" "✓ Container is running"

    # Check container health
    if ! is_container_healthy "$container"; then
        print_colored "$COLOR_WARNING" "⚠ Container health check failed"
        print_colored "$COLOR_WARNING" "  Proceeding anyway..."
    fi

    # Check if scrapers are already running
    if are_scrapers_running "$container"; then
        print_colored "$COLOR_WARNING" "⚠ Scrapers are already running in this container!"
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_colored "$COLOR_INFO" "Skipping $country_name..."
            return 0
        fi
    fi

    # Check VPN status
    check_vpn_status "$container" "$country_name" || true

    # Trigger the scraper
    echo ""
    print_colored "$color" "Starting scrapers in $country_name container..."
    echo ""

    if docker exec "$container" bash -c "cd /app && $SCRAPER_SCRIPT" 2>&1 | while IFS= read -r line; do
        print_colored "$color" "  $line"
    done; then
        echo ""
        print_colored "$COLOR_SUCCESS" "✓ Scraper started successfully in $country_name container"
        return 0
    else
        echo ""
        print_colored "$COLOR_ERROR" "✗ Failed to start scraper in $country_name container"
        return 1
    fi
}

# Show usage information
show_usage() {
    cat <<EOF
Usage: $0 [COUNTRY]

Manually trigger scrapers in Docker containers.

ARGUMENTS:
  all         Trigger scrapers in all containers (default)
  poland      Trigger only Poland scrapers
  germany     Trigger only Germany scrapers
  czech       Trigger only Czech Republic scrapers

FEATURES:
  - Validates container is running
  - Checks VPN connection status
  - Detects if scrapers are already running
  - Provides detailed feedback

EXAMPLES:
  $0              # Trigger all containers
  $0 all          # Trigger all containers
  $0 poland       # Trigger only Poland
  $0 germany      # Trigger only Germany

NOTES:
  - Scrapers require VPN to be connected
  - Multiple scraper runs in same container are possible but not recommended
  - Check logs with: npm run scrapers:watch
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

    # Show header
    print_header "CheaperForDrug Scraper - Manual Trigger"
    print_colored "$COLOR_INFO" "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local success_count=0
    local total_count=0

    # Trigger scrapers based on country selection
    case "$country" in
        all)
            trigger_scraper "$CONTAINER_POLAND" "poland" "Poland" "$COLOR_POLAND" && ((success_count++)) || true
            ((total_count++))

            trigger_scraper "$CONTAINER_GERMANY" "germany" "Germany" "$COLOR_GERMANY" && ((success_count++)) || true
            ((total_count++))

            trigger_scraper "$CONTAINER_CZECH" "czech" "Czech Republic" "$COLOR_CZECH" && ((success_count++)) || true
            ((total_count++))

            # Summary
            echo ""
            print_colored "$COLOR_BOLD" "════════════════════════════════════════════════════════════════"
            if [[ $success_count -eq $total_count ]]; then
                print_colored "$COLOR_SUCCESS" "✓ All scrapers started successfully ($success_count/$total_count)"
            elif [[ $success_count -gt 0 ]]; then
                print_colored "$COLOR_WARNING" "⚠ Some scrapers started ($success_count/$total_count)"
            else
                print_colored "$COLOR_ERROR" "✗ No scrapers started (0/$total_count)"
            fi
            print_colored "$COLOR_BOLD" "════════════════════════════════════════════════════════════════"
            echo ""

            [[ $success_count -gt 0 ]] && exit 0 || exit 1
            ;;
        poland)
            trigger_scraper "$CONTAINER_POLAND" "poland" "Poland" "$COLOR_POLAND"
            ;;
        germany)
            trigger_scraper "$CONTAINER_GERMANY" "germany" "Germany" "$COLOR_GERMANY"
            ;;
        czech)
            trigger_scraper "$CONTAINER_CZECH" "czech" "Czech Republic" "$COLOR_CZECH"
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
