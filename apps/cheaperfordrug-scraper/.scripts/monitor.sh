#!/bin/bash

# Monitoring Script for CheaperForDrug Scraper
# Displays real-time status of all containers and VPN connections
# Now includes scheduling information and last run times

set -e

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common utilities
source "$DEVOPS_DIR/common/utils.sh"

# Load app configuration
source "$SCRIPT_DIR/config.sh"

# Cron log file
CRON_LOG_FILE="${APP_DIR}/logs/cron/scraper-cron.log"

# Clear screen function
clear_screen() {
    clear
}

# Get container status
get_container_status() {
    local container="$1"

    if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
        local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-check")
        echo "$status|$health"
    else
        echo "stopped|n/a"
    fi
}

# Get VPN status from container
get_vpn_status() {
    local container="$1"

    if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
        docker exec "$container" nordvpn status 2>/dev/null | grep -i "status:" | awk '{print $2}' || echo "unknown"
    else
        echo "n/a"
    fi
}

# Get VPN IP from container
get_vpn_ip() {
    local container="$1"

    if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
        docker exec "$container" curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "unknown"
    else
        echo "n/a"
    fi
}

# Get scraper process count
get_scraper_count() {
    local container="$1"

    if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
        docker exec "$container" ps aux 2>/dev/null | grep -c "node.*scraper" || echo "0"
    else
        echo "0"
    fi
}

# Get last cron run time
get_last_cron_run() {
    if [[ -f "$CRON_LOG_FILE" ]]; then
        local last_run=$(grep "Cron job started" "$CRON_LOG_FILE" 2>/dev/null | tail -1 | sed 's/.*\[\(.*\)\].*/\1/' || echo "Never")
        echo "$last_run"
    else
        echo "Never"
    fi
}

# Get next scheduled run time
get_next_scheduled_run() {
    # Check if cron job is installed
    if ! crontab -l 2>/dev/null | grep -q "cheaperfordrug-scraper"; then
        echo "Not scheduled (cron not installed)"
        return
    fi

    # Calculate next Monday and Thursday at 7 AM
    local current_dow=$(date +%u)  # 1=Monday, 4=Thursday, 7=Sunday
    local current_hour=$(date +%H)
    local days_until_monday
    local days_until_thursday

    # Calculate days until next Monday
    if [[ $current_dow -eq 1 ]] && [[ $current_hour -lt 7 ]]; then
        days_until_monday=0
    else
        days_until_monday=$(( (8 - current_dow) % 7 ))
        [[ $days_until_monday -eq 0 ]] && days_until_monday=7
    fi

    # Calculate days until next Thursday
    if [[ $current_dow -eq 4 ]] && [[ $current_hour -lt 7 ]]; then
        days_until_thursday=0
    else
        days_until_thursday=$(( (11 - current_dow) % 7 ))
        [[ $days_until_thursday -eq 0 ]] && days_until_thursday=7
    fi

    # Determine which is sooner
    if [[ $days_until_monday -le $days_until_thursday ]]; then
        local next_date=$(date -d "+${days_until_monday} days" "+%Y-%m-%d" 2>/dev/null || date -v+${days_until_monday}d "+%Y-%m-%d" 2>/dev/null)
        echo "$next_date 07:00:00 (Monday)"
    else
        local next_date=$(date -d "+${days_until_thursday} days" "+%Y-%m-%d" 2>/dev/null || date -v+${days_until_thursday}d "+%Y-%m-%d" 2>/dev/null)
        echo "$next_date 07:00:00 (Thursday)"
    fi
}

# Check if scrapers are currently running (enhanced)
check_scrapers_running() {
    local poland_count=$(get_scraper_count "$CONTAINER_POLAND")
    local germany_count=$(get_scraper_count "$CONTAINER_GERMANY")
    local czech_count=$(get_scraper_count "$CONTAINER_CZECH")

    local total=$((poland_count + germany_count + czech_count))

    if [[ $total -gt 3 ]]; then
        echo "YES (running in $((total - 3)) container(s))"
    else
        echo "NO"
    fi
}

# Get status indicator with color
get_status_indicator() {
    local status="$1"
    local health="$2"

    if [[ "$status" == "running" ]]; then
        if [[ "$health" == "healthy" ]]; then
            echo "✓ RUNNING (healthy)"
        elif [[ "$health" == "unhealthy" ]]; then
            echo "⚠ RUNNING (unhealthy)"
        else
            echo "✓ RUNNING"
        fi
    else
        echo "✗ STOPPED"
    fi
}

# Get VPN status indicator
get_vpn_indicator() {
    local vpn_status="$1"

    if [[ "$vpn_status" == "Connected" ]]; then
        echo "✓ Connected"
    else
        echo "✗ $vpn_status"
    fi
}

# Display status
display_status() {
    clear_screen

    echo "================================================================"
    echo "CheaperForDrug Scraper - Status Monitor"
    echo "Updated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================"
    echo ""

    # Scheduling Information
    echo "--- SCHEDULING INFORMATION ---"
    echo "Scrapers Running:    $(check_scrapers_running)"
    echo "Last Cron Run:       $(get_last_cron_run)"
    echo "Next Scheduled Run:  $(get_next_scheduled_run)"
    echo ""

    # Poland Container
    echo "--- POLAND Container ---"
    local poland_status=$(get_container_status "$CONTAINER_POLAND")
    local poland_vpn=$(get_vpn_status "$CONTAINER_POLAND")
    local poland_ip=$(get_vpn_ip "$CONTAINER_POLAND")
    local poland_scrapers=$(get_scraper_count "$CONTAINER_POLAND")

    echo "Container:       $CONTAINER_POLAND"
    echo "Status:          $(get_status_indicator $(echo $poland_status | cut -d'|' -f1) $(echo $poland_status | cut -d'|' -f2))"
    echo "VPN Status:      $(get_vpn_indicator $poland_vpn)"
    echo "VPN IP:          $poland_ip"
    echo "Scraper Procs:   $poland_scrapers"
    echo ""

    # Germany Container
    echo "--- GERMANY Container ---"
    local germany_status=$(get_container_status "$CONTAINER_GERMANY")
    local germany_vpn=$(get_vpn_status "$CONTAINER_GERMANY")
    local germany_ip=$(get_vpn_ip "$CONTAINER_GERMANY")
    local germany_scrapers=$(get_scraper_count "$CONTAINER_GERMANY")

    echo "Container:       $CONTAINER_GERMANY"
    echo "Status:          $(get_status_indicator $(echo $germany_status | cut -d'|' -f1) $(echo $germany_status | cut -d'|' -f2))"
    echo "VPN Status:      $(get_vpn_indicator $germany_vpn)"
    echo "VPN IP:          $germany_ip"
    echo "Scraper Procs:   $germany_scrapers"
    echo ""

    # Czech Container
    echo "--- CZECH Container ---"
    local czech_status=$(get_container_status "$CONTAINER_CZECH")
    local czech_vpn=$(get_vpn_status "$CONTAINER_CZECH")
    local czech_ip=$(get_vpn_ip "$CONTAINER_CZECH")
    local czech_scrapers=$(get_scraper_count "$CONTAINER_CZECH")

    echo "Container:       $CONTAINER_CZECH"
    echo "Status:          $(get_status_indicator $(echo $czech_status | cut -d'|' -f1) $(echo $czech_status | cut -d'|' -f2))"
    echo "VPN Status:      $(get_vpn_indicator $czech_vpn)"
    echo "VPN IP:          $czech_ip"
    echo "Scraper Procs:   $czech_scrapers"
    echo ""

    # Resource Usage
    echo "--- Resource Usage ---"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
        "$CONTAINER_POLAND" "$CONTAINER_GERMANY" "$CONTAINER_CZECH" 2>/dev/null || echo "Stats not available"
    echo ""

    echo "================================================================"
    echo "Commands: npm run scrapers:start | npm run scrapers:watch"
    echo "Press Ctrl+C to exit"
    echo "================================================================"
}

# Main monitoring loop
main() {
    local refresh_interval="${1:-5}"  # Default 5 seconds

    log_info "Starting monitoring (refresh every ${refresh_interval}s)..."
    echo ""

    trap 'log_info "Monitoring stopped"; exit 0' SIGINT SIGTERM

    while true; do
        display_status
        sleep "$refresh_interval"
    done
}

# Run main function
main "$@"
