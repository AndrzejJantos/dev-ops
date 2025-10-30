#!/bin/bash

# VPN Rotation Script for CheaperForDrug Scraper
# Rotates NordVPN connection every N minutes to avoid IP blocking
# Runs in background and logs to /app/logs/vpn-rotation.log

set -euo pipefail

# Configuration
VPN_COUNTRY="${VPN_COUNTRY:-Poland}"
VPN_ROTATE_INTERVAL="${VPN_ROTATE_INTERVAL:-15}"  # Minutes
LOG_FILE="/app/logs/vpn-rotation.log"
PID_FILE="/tmp/vpn-rotate.pid"

# Color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[VPN-ROTATE]${NC} [INFO] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[VPN-ROTATE]${NC} [SUCCESS] $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[VPN-ROTATE]${NC} [WARNING] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[VPN-ROTATE]${NC} [ERROR] $1" | tee -a "$LOG_FILE"
}

# Check if NordVPN is logged in
check_vpn_login() {
    if nordvpn account | grep -q "You are not logged in"; then
        log_error "NordVPN not logged in!"
        return 1
    fi
    return 0
}

# Get current VPN status
get_vpn_status() {
    nordvpn status | grep -i "status:" | awk '{print $2}'
}

# Get current IP address
get_current_ip() {
    curl -s --max-time 10 https://api.ipify.org || echo "unknown"
}

# Disconnect from VPN
disconnect_vpn() {
    log_info "Disconnecting from VPN..."
    if nordvpn disconnect >/dev/null 2>&1; then
        log_success "Disconnected from VPN"
        return 0
    else
        log_error "Failed to disconnect from VPN"
        return 1
    fi
}

# Connect to VPN
connect_vpn() {
    local country="$1"
    local max_retries=3
    local retry=0

    log_info "Connecting to NordVPN in ${country}..."

    while [ $retry -lt $max_retries ]; do
        if nordvpn connect "$country" 2>&1 | tee -a "$LOG_FILE" | grep -q "Connected"; then
            sleep 5  # Wait for connection to stabilize
            local new_ip=$(get_current_ip)
            log_success "Connected to VPN in ${country}. New IP: ${new_ip}"
            return 0
        fi

        retry=$((retry + 1))
        log_warning "Connection attempt $retry failed. Retrying..."
        sleep 5
    done

    log_error "Failed to connect to VPN after $max_retries attempts"
    return 1
}

# Rotate VPN connection
rotate_vpn() {
    log_info "Starting VPN rotation..."

    local old_ip=$(get_current_ip)
    log_info "Current IP: ${old_ip}"

    # Disconnect
    if ! disconnect_vpn; then
        log_error "Failed to disconnect, attempting to continue anyway..."
    fi

    sleep 3

    # Reconnect
    if connect_vpn "$VPN_COUNTRY"; then
        local new_ip=$(get_current_ip)
        if [ "$old_ip" != "$new_ip" ]; then
            log_success "IP successfully rotated: ${old_ip} -> ${new_ip}"
        else
            log_warning "IP remained the same after rotation: ${new_ip}"
        fi
        return 0
    else
        log_error "VPN rotation failed!"
        return 1
    fi
}

# Cleanup on exit
cleanup() {
    log_info "VPN rotation script stopping..."
    rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main loop
main() {
    log_info "VPN Rotation Script Started"
    log_info "Country: ${VPN_COUNTRY}"
    log_info "Rotation Interval: ${VPN_ROTATE_INTERVAL} minutes"

    # Save PID
    echo $$ > "$PID_FILE"

    # Check if logged in
    if ! check_vpn_login; then
        log_error "Cannot start rotation without VPN login"
        exit 1
    fi

    # Initial connection check
    local status=$(get_vpn_status)
    if [ "$status" != "Connected" ]; then
        log_info "VPN not connected. Attempting initial connection..."
        if ! connect_vpn "$VPN_COUNTRY"; then
            log_error "Failed to establish initial VPN connection"
            exit 1
        fi
    else
        log_success "VPN already connected"
        local current_ip=$(get_current_ip)
        log_info "Current IP: ${current_ip}"
    fi

    # Rotation loop
    local interval_seconds=$((VPN_ROTATE_INTERVAL * 60))

    while true; do
        log_info "Sleeping for ${VPN_ROTATE_INTERVAL} minutes until next rotation..."
        sleep "$interval_seconds"

        # Check if VPN is still connected
        status=$(get_vpn_status)
        if [ "$status" != "Connected" ]; then
            log_warning "VPN disconnected unexpectedly. Reconnecting..."
            if ! connect_vpn "$VPN_COUNTRY"; then
                log_error "Failed to reconnect VPN"
                sleep 60  # Wait before retry
                continue
            fi
        fi

        # Perform rotation
        if ! rotate_vpn; then
            log_error "Rotation failed, will retry in next cycle"
        fi
    done
}

# Run main function
main "$@"
