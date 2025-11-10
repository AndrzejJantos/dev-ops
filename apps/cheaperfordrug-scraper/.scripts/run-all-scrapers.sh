#!/bin/bash

# Run All Scrapers Script
# Triggers all scrapers in all country containers simultaneously

set -euo pipefail

# Color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[RUN-ALL]${NC} [INFO] $1"
}

log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[RUN-ALL]${NC} [SUCCESS] $1"
}

log_warning() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[RUN-ALL]${NC} [WARNING] $1"
}

log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[RUN-ALL]${NC} [ERROR] $1"
}

# Container names
CONTAINERS=(
    "cheaperfordrug-scraper-poland"
    "cheaperfordrug-scraper-germany"
    "cheaperfordrug-scraper-czech"
)

# Main function
main() {
    log_info "================================================================"
    log_info "Running scrapers in all containers"
    log_info "================================================================"

    local success_count=0
    local failed_count=0
    local pids=()

    # Start scrapers in all containers simultaneously
    for container in "${CONTAINERS[@]}"; do
        log_info "Triggering scraper in: $container"

        if docker exec "$container" /usr/local/bin/run-scraper-cron.sh &> "/tmp/${container}-scraper.log" & then
            pids+=($!)
            log_success "Started scraper in $container (PID: $!)"
        else
            log_error "Failed to start scraper in $container"
            ((failed_count++))
        fi
    done

    # Wait for all scrapers to complete
    log_info ""
    log_info "Waiting for scrapers to complete..."
    log_info ""

    for i in "${!pids[@]}"; do
        local pid="${pids[$i]}"
        local container="${CONTAINERS[$i]}"

        if wait "$pid"; then
            log_success "Scraper completed in $container"
            ((success_count++))
        else
            log_error "Scraper failed in $container"
            ((failed_count++))
        fi
    done

    # Summary
    log_info "================================================================"
    log_info "Scraping Summary:"
    log_success "  Successful: $success_count"
    if [ $failed_count -gt 0 ]; then
        log_error "  Failed: $failed_count"
    else
        log_info "  Failed: $failed_count"
    fi
    log_info "================================================================"

    # Show logs location
    log_info ""
    log_info "Detailed logs available at:"
    for container in "${CONTAINERS[@]}"; do
        echo "  - /tmp/${container}-scraper.log"
    done

    # Exit with error if any scraper failed
    if [ $failed_count -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main "$@"
