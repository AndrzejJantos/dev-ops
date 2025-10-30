#!/bin/bash

# Health Check Script for CheaperForDrug Scraper Container
# Verifies VPN connection, scraper processes, and overall container health

set -e

# Exit codes
EXIT_SUCCESS=0
EXIT_FAILURE=1

# Check if NordVPN daemon is running
check_nordvpn_daemon() {
    if pgrep -f nordvpnd >/dev/null 2>&1; then
        return 0
    fi
    echo "UNHEALTHY: NordVPN daemon not running"
    return 1
}

# Check if VPN is connected
check_vpn_connection() {
    if nordvpn status 2>/dev/null | grep -q "Status: Connected"; then
        return 0
    fi
    echo "UNHEALTHY: VPN not connected"
    return 1
}

# Check if VPN rotation script is running
check_vpn_rotation() {
    if [ -f /tmp/vpn-rotate.pid ]; then
        local pid=$(cat /tmp/vpn-rotate.pid)
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    echo "WARNING: VPN rotation script not running"
    return 0  # Non-critical, don't fail health check
}

# Check if any scraper processes are running or supervisor is active
check_scraper_processes() {
    # Check if supervisord is running
    if pgrep -f supervisord >/dev/null 2>&1; then
        return 0
    fi

    # Alternative: check for node scraper processes
    if pgrep -f "node.*scraper" >/dev/null 2>&1; then
        return 0
    fi

    echo "WARNING: No scraper processes found"
    return 0  # Non-critical during startup
}

# Check API connectivity (optional, non-blocking)
check_api_connectivity() {
    if [ -n "${API_ENDPOINT:-}" ]; then
        if curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$API_ENDPOINT" >/dev/null 2>&1; then
            return 0
        fi
        echo "WARNING: API endpoint unreachable"
    fi
    return 0  # Non-critical
}

# Check disk space
check_disk_space() {
    local usage=$(df /app | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$usage" -gt 95 ]; then
        echo "UNHEALTHY: Disk usage critical: ${usage}%"
        return 1
    fi
    return 0
}

# Check if logs directory is writable
check_logs_directory() {
    if [ -w /app/logs ]; then
        return 0
    fi
    echo "UNHEALTHY: Logs directory not writable"
    return 1
}

# Main health check
main() {
    local checks_passed=0
    local checks_failed=0
    local checks_warned=0

    # Critical checks
    if check_nordvpn_daemon; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi

    if check_vpn_connection; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi

    if check_logs_directory; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi

    if check_disk_space; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi

    # Non-critical checks
    check_vpn_rotation
    check_scraper_processes
    check_api_connectivity

    # Return status
    if [ $checks_failed -eq 0 ]; then
        echo "HEALTHY: All critical checks passed"
        exit $EXIT_SUCCESS
    else
        echo "UNHEALTHY: ${checks_failed} critical check(s) failed"
        exit $EXIT_FAILURE
    fi
}

main "$@"
