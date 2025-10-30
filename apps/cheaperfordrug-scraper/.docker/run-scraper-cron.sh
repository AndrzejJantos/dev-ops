#!/bin/bash

# Cron Wrapper Script for Container-Level Scraper Execution
# This script is called by cron inside each container
# It ensures environment variables are loaded and runs the scrapers for the container's country

set -euo pipefail

# Color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions with timestamps
log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[CRON]${NC} [INFO] $1"
}

log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[CRON]${NC} [SUCCESS] $1"
}

log_warning() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[CRON]${NC} [WARNING] $1"
}

log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[CRON]${NC} [ERROR] $1"
}

# Load environment variables from /proc/1/environ (PID 1 is the entrypoint)
load_environment() {
    log_info "Loading environment variables..."

    # Export common environment variables needed by scrapers
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/app/node_modules/.bin"
    export NODE_ENV="${NODE_ENV:-production}"
    export HOME="/root"

    # Read environment from PID 1 (main container process)
    if [ -f /proc/1/environ ]; then
        while IFS='=' read -r -d '' key value; do
            # Only export specific variables we need
            case "$key" in
                COUNTRY|COUNTRY_CODE|VPN_COUNTRY|API_ENDPOINT|API_TOKEN|SCRAPER_AUTH_TOKEN|HEADLESS|SEND_TO_API|NORDVPN_TOKEN)
                    export "$key=$value"
                    ;;
            esac
        done < /proc/1/environ
    fi

    # Verify critical environment variables
    if [ -z "${COUNTRY:-}" ]; then
        log_error "COUNTRY environment variable not set!"
        return 1
    fi

    log_success "Environment loaded. Country: ${COUNTRY}"
    return 0
}

# Check if VPN is connected
check_vpn_connection() {
    log_info "Checking VPN connection status..."

    if nordvpn status 2>&1 | grep -q "Status: Connected"; then
        local vpn_country=$(nordvpn status | grep "Country:" | awk '{print $2}' || echo "Unknown")
        local vpn_ip=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null || echo "unknown")
        log_success "VPN is connected. Country: ${vpn_country}, IP: ${vpn_ip}"
        return 0
    else
        log_error "VPN is not connected! Scrapers cannot run without VPN."
        return 1
    fi
}

# Get list of scrapers for current country
get_scrapers_list() {
    local country="$1"
    local scrapers_dir="/app/scrapers/${country}"

    if [ ! -d "$scrapers_dir" ]; then
        log_error "Scrapers directory not found: ${scrapers_dir}"
        return 1
    fi

    # List all scraper files
    find "$scrapers_dir" -name "*_scraper.js" -type f | sort
}

# Run a single scraper
run_single_scraper() {
    local scraper_file="$1"
    local scraper_name=$(basename "$scraper_file" .js)

    log_info "Starting scraper: ${scraper_name}"

    cd /app

    if su - scraper -c "cd /app && node '$scraper_file' 2>&1"; then
        log_success "Scraper completed: ${scraper_name}"
        return 0
    else
        local exit_code=$?
        log_error "Scraper failed: ${scraper_name} (exit code: ${exit_code})"
        return $exit_code
    fi
}

# Run all scrapers for the country
run_all_scrapers() {
    local country="$1"
    local scrapers=$(get_scrapers_list "$country")
    local total_scrapers=0
    local successful_scrapers=0
    local failed_scrapers=0

    if [ -z "$scrapers" ]; then
        log_warning "No scrapers found for country: ${country}"
        return 0
    fi

    total_scrapers=$(echo "$scrapers" | wc -l)
    log_info "Found ${total_scrapers} scrapers for ${country}"

    # Run each scraper
    while IFS= read -r scraper_file; do
        if [ -f "$scraper_file" ]; then
            if run_single_scraper "$scraper_file"; then
                successful_scrapers=$((successful_scrapers + 1))
            else
                failed_scrapers=$((failed_scrapers + 1))
            fi

            # Small delay between scrapers to avoid overwhelming the system
            sleep 5
        fi
    done <<< "$scrapers"

    # Summary
    log_info "================================================================"
    log_info "Cron Scraping Summary for ${country}:"
    log_info "  Total:      ${total_scrapers}"
    log_success "  Successful: ${successful_scrapers}"
    if [ $failed_scrapers -gt 0 ]; then
        log_error "  Failed:     ${failed_scrapers}"
    else
        log_info "  Failed:     ${failed_scrapers}"
    fi
    log_info "================================================================"

    # Return non-zero if any scrapers failed
    if [ $failed_scrapers -gt 0 ]; then
        return 1
    fi

    return 0
}

# Main execution
main() {
    log_info "==================================================================="
    log_info "Container Cron Job Started"
    log_info "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log_info "==================================================================="

    # Create log directory if it doesn't exist
    mkdir -p /app/logs/cron
    chown -R scraper:scraper /app/logs/cron

    # Load environment variables
    if ! load_environment; then
        log_error "Failed to load environment variables"
        exit 1
    fi

    # Check VPN connection
    if ! check_vpn_connection; then
        log_error "VPN connection check failed. Aborting scraper execution."
        exit 1
    fi

    # Run scrapers for this container's country
    log_info "Starting scrapers for country: ${COUNTRY}"

    if run_all_scrapers "${COUNTRY}"; then
        log_success "All scrapers completed successfully"
        exit_code=0
    else
        log_error "Some scrapers failed"
        exit_code=1
    fi

    log_info "==================================================================="
    log_info "Container Cron Job Completed"
    log_info "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log_info "Exit code: ${exit_code}"
    log_info "==================================================================="

    exit $exit_code
}

# Run main function
main "$@"
