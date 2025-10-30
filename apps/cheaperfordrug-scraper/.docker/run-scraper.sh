#!/bin/bash

# Scraper Runner Script - Runs country-specific scrapers
# This script is executed by supervisord and handles running scrapers for a specific country

set -euo pipefail

# Color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COUNTRY="${COUNTRY:-poland}"
COUNTRY_CODE="${COUNTRY_CODE:-PL}"
SCRAPER_MODE="${SCRAPER_MODE:-continuous}"  # continuous or once
RETRY_INTERVAL="${RETRY_INTERVAL:-300}"     # 5 minutes between runs

# Logging functions
log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[SCRAPER]${NC} [INFO] $1"
}

log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[SCRAPER]${NC} [SUCCESS] $1"
}

log_warning() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[SCRAPER]${NC} [WARNING] $1"
}

log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[SCRAPER]${NC} [ERROR] $1"
}

# Check if VPN is connected
check_vpn_connection() {
    if nordvpn status | grep -q "Status: Connected"; then
        return 0
    else
        log_error "VPN is not connected!"
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

    log_info "Starting scraper: ${scraper_name} (${COUNTRY})"

    # Switch to scraper user and run
    cd /app

    if su - scraper -c "cd /app && node '$scraper_file' 2>&1"; then
        log_success "Scraper completed successfully: ${scraper_name}"
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

            # Small delay between scrapers
            sleep 5
        fi
    done <<< "$scrapers"

    # Summary
    log_info "================================================================"
    log_info "Scraping Summary for ${country}:"
    log_info "  Total:      ${total_scrapers}"
    log_success "  Successful: ${successful_scrapers}"
    if [ $failed_scrapers -gt 0 ]; then
        log_error "  Failed:     ${failed_scrapers}"
    else
        log_info "  Failed:     ${failed_scrapers}"
    fi
    log_info "================================================================"

    return 0
}

# Use the scraper manager if available
run_with_manager() {
    local country="$1"

    log_info "Starting scrapers using manager script..."

    cd /app

    # Check if manager script exists
    if [ ! -f "/app/scripts/manager.js" ]; then
        log_warning "Manager script not found, falling back to direct execution"
        run_all_scrapers "$country"
        return
    fi

    # Use the manager to start scrapers
    if su - scraper -c "cd /app && npm run scrapers:start:headless 2>&1"; then
        log_success "Scrapers started via manager"

        # Monitor scrapers if in continuous mode
        if [ "$SCRAPER_MODE" = "continuous" ]; then
            log_info "Monitoring scrapers..."
            while true; do
                sleep 300  # Check every 5 minutes

                # Check if VPN is still connected
                if ! check_vpn_connection; then
                    log_error "VPN connection lost, waiting for reconnection..."
                    sleep 60
                    continue
                fi

                # Check scraper status
                su - scraper -c "cd /app && npm run scrapers:status 2>&1" || true
            done
        fi
    else
        log_error "Failed to start scrapers via manager"
        return 1
    fi
}

# Main execution loop
main() {
    log_info "================================================================"
    log_info "Scraper Service Starting"
    log_info "Country: ${COUNTRY} (${COUNTRY_CODE})"
    log_info "Mode: ${SCRAPER_MODE}"
    log_info "================================================================"

    # Verify VPN connection before starting
    if ! check_vpn_connection; then
        log_error "Cannot start scrapers without VPN connection"
        exit 1
    fi

    case "$SCRAPER_MODE" in
        continuous)
            log_info "Running in continuous mode..."
            while true; do
                run_with_manager "$COUNTRY"

                log_info "Waiting ${RETRY_INTERVAL} seconds before next run..."
                sleep "$RETRY_INTERVAL"
            done
            ;;

        once)
            log_info "Running in single-run mode..."
            run_all_scrapers "$COUNTRY"
            log_success "Single run completed"
            ;;

        manager)
            log_info "Running with manager (continuous monitoring)..."
            run_with_manager "$COUNTRY"
            ;;

        *)
            log_error "Unknown scraper mode: ${SCRAPER_MODE}"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
