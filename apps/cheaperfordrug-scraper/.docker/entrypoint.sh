#!/bin/bash

# Entrypoint Script for CheaperForDrug Scraper Container
# Handles NordVPN authentication, connection, and scraper startup

set -e

# Color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[ENTRYPOINT]${NC} [INFO] $1"
}

log_success() {
    echo -e "${GREEN}[ENTRYPOINT]${NC} [SUCCESS] $1"
}

log_warning() {
    echo -e "${YELLOW}[ENTRYPOINT]${NC} [WARNING] $1"
}

log_error() {
    echo -e "${RED}[ENTRYPOINT]${NC} [ERROR] $1"
}

# Cleanup on exit
cleanup() {
    log_info "Shutting down container..."

    # Stop VPN rotation script
    if [ -f /tmp/vpn-rotate.pid ]; then
        local vpn_pid=$(cat /tmp/vpn-rotate.pid)
        if kill -0 "$vpn_pid" 2>/dev/null; then
            log_info "Stopping VPN rotation script..."
            kill "$vpn_pid" 2>/dev/null || true
        fi
    fi

    # Stop scraper processes
    log_info "Stopping scraper processes..."
    pkill -f "node.*scraper" || true

    # Disconnect VPN
    log_info "Disconnecting from VPN..."
    nordvpn disconnect >/dev/null 2>&1 || true

    log_success "Cleanup complete"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Validate required environment variables
validate_environment() {
    log_info "Validating environment variables..."

    local required_vars=(
        "NORDVPN_TOKEN"
        "COUNTRY"
        "VPN_COUNTRY"
        "API_ENDPOINT"
        "API_TOKEN"
        "SCRAPER_AUTH_TOKEN"
    )

    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi

    log_success "Environment variables validated"
}

# Setup NordVPN daemon
setup_nordvpn_daemon() {
    log_info "Starting NordVPN daemon..."

    # Start the daemon
    /etc/init.d/nordvpn start 2>&1 | tee -a /app/logs/nordvpn-daemon.log || {
        log_error "Failed to start NordVPN daemon"
        exit 1
    }

    # Wait for daemon to be ready
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if nordvpn account 2>&1 | grep -qE "(You are not logged in|Account Information)"; then
            log_success "NordVPN daemon is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    log_error "NordVPN daemon failed to become ready"
    exit 1
}

# Login to NordVPN
login_nordvpn() {
    log_info "Logging in to NordVPN..."

    if nordvpn account 2>&1 | grep -q "Account Information"; then
        log_success "Already logged in to NordVPN"
        return 0
    fi

    # Login with token (using expect to handle interactive prompt)
    log_info "Creating expect script for login..."
    cat > /tmp/nordvpn-login.exp << 'EXPECT_EOF'
#!/usr/bin/expect -f
set timeout 30
set token [lindex $argv 0]

spawn nordvpn login --token
expect "Press 'n' (no) to send only the essential data our app needs to work."
send "$token\r"
expect "Do you allow us to collect and use limited app performance data?"
send "n\r"
expect eof
EXPECT_EOF

    chmod +x /tmp/nordvpn-login.exp

    if /tmp/nordvpn-login.exp "$NORDVPN_TOKEN" 2>&1 | tee -a /app/logs/nordvpn-login.log | grep -qE "(Welcome|logged in)"; then
        log_success "Successfully logged in to NordVPN"
    else
        log_error "Failed to login to NordVPN"
        exit 1
    fi
}

# Configure NordVPN settings
configure_nordvpn() {
    log_info "Configuring NordVPN settings..."

    # Set protocol to NordLynx (WireGuard) for better performance
    nordvpn set technology nordlynx 2>&1 | tee -a /app/logs/nordvpn-config.log

    # Enable kill switch to prevent leaks
    nordvpn set killswitch enabled 2>&1 | tee -a /app/logs/nordvpn-config.log

    # Disable CyberSec (can cause issues with some sites)
    nordvpn set cybersec disabled 2>&1 | tee -a /app/logs/nordvpn-config.log

    # Enable auto-connect on startup
    nordvpn set autoconnect disabled 2>&1 | tee -a /app/logs/nordvpn-config.log

    # Set DNS to automatic
    nordvpn set dns disabled 2>&1 | tee -a /app/logs/nordvpn-config.log

    # Whitelist local network (for API access)
    # Add route to allow access to host network
    nordvpn whitelist add subnet 172.16.0.0/12 2>&1 | tee -a /app/logs/nordvpn-config.log || true
    nordvpn whitelist add subnet 192.168.0.0/16 2>&1 | tee -a /app/logs/nordvpn-config.log || true
    nordvpn whitelist add subnet 10.0.0.0/8 2>&1 | tee -a /app/logs/nordvpn-config.log || true

    log_success "NordVPN configured"
}

# Connect to VPN
connect_vpn() {
    log_info "Connecting to VPN in ${VPN_COUNTRY}..."

    local max_attempts=5
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if nordvpn connect "$VPN_COUNTRY" 2>&1 | tee -a /app/logs/nordvpn-connect.log | grep -q "Connected"; then
            sleep 5  # Wait for connection to stabilize

            # Verify connection
            if nordvpn status | grep -q "Status: Connected"; then
                local ip=$(curl -s --max-time 10 https://api.ipify.org || echo "unknown")
                log_success "Connected to VPN in ${VPN_COUNTRY}. IP: ${ip}"
                return 0
            fi
        fi

        attempt=$((attempt + 1))
        log_warning "Connection attempt $attempt failed. Retrying..."
        sleep 5
    done

    log_error "Failed to connect to VPN after $max_attempts attempts"
    exit 1
}

# Start VPN rotation in background
start_vpn_rotation() {
    log_info "Starting VPN rotation script (interval: ${VPN_ROTATE_INTERVAL:-15} minutes)..."

    /usr/local/bin/vpn-rotate.sh &

    local vpn_pid=$!
    echo "$vpn_pid" > /tmp/vpn-rotate-parent.pid

    log_success "VPN rotation started with PID: $vpn_pid"
}

# Verify API connectivity
verify_api_connectivity() {
    log_info "Verifying API connectivity to ${API_ENDPOINT}..."

    # Extract host and port from API endpoint
    local api_host=$(echo "$API_ENDPOINT" | sed -E 's|^https?://([^:/]+).*|\1|')
    local api_port=$(echo "$API_ENDPOINT" | sed -E 's|^https?://[^:]+:([0-9]+).*|\1|')

    # Default to port 80/443 if not specified
    if [ "$api_port" = "$API_ENDPOINT" ]; then
        if [[ "$API_ENDPOINT" =~ ^https ]]; then
            api_port=443
        else
            api_port=80
        fi
    fi

    log_info "Testing connection to ${api_host}:${api_port}..."

    # Try to resolve and connect (with timeout)
    if timeout 10 bash -c "curl -s -o /dev/null -w '%{http_code}' --max-time 10 '${API_ENDPOINT}' || echo 'failed'" | grep -qE '[0-9]{3}|failed'; then
        log_success "API endpoint is reachable"
    else
        log_warning "API endpoint may not be reachable, but continuing anyway"
    fi
}

# Setup cron for container-level scheduled execution
setup_cron() {
    log_info "Setting up container-level cron..."

    # Create cron log directory
    mkdir -p /app/logs/cron
    chown -R scraper:scraper /app/logs/cron

    # Verify cron configuration is installed
    if crontab -l >/dev/null 2>&1; then
        log_success "Cron configuration installed successfully"

        # Log the cron schedule
        log_info "Cron schedule:"
        crontab -l | grep -v "^#" | grep -v "^$" || true
    else
        log_warning "Cron configuration not found, reinstalling..."
        if [ -f /etc/cron.d/scraper-cron ]; then
            crontab /etc/cron.d/scraper-cron
            log_success "Cron configuration reinstalled"
        else
            log_error "Cron configuration file not found!"
        fi
    fi

    # Touch the cron log file
    touch /app/logs/cron/scraper.log
    chown scraper:scraper /app/logs/cron/scraper.log

    log_success "Cron setup complete (runs Monday/Thursday at 7:00 AM)"
}

# Main entrypoint logic
main() {
    log_info "==================================================================="
    log_info "CheaperForDrug Scraper Container Starting"
    log_info "Country: ${COUNTRY} (${COUNTRY_CODE:-N/A})"
    log_info "VPN Country: ${VPN_COUNTRY}"
    log_info "==================================================================="

    # Create required subdirectories (parent dirs are volume mounts from host)
    # /app/logs, /app/outputs, /app/state are bind-mounted from host
    # We only create subdirectories within them if needed
    mkdir -p /app/logs/cron
    chown -R scraper:scraper /app/logs/cron 2>/dev/null || true

    # Validate environment
    validate_environment

    # Setup and configure NordVPN
    setup_nordvpn_daemon
    login_nordvpn
    configure_nordvpn
    connect_vpn

    # Verify API connectivity
    verify_api_connectivity

    # Setup container-level cron
    setup_cron

    # Start VPN rotation
    start_vpn_rotation

    log_success "Container initialization complete"
    log_info "==================================================================="

    # Execute the command passed to the container
    if [ $# -gt 0 ]; then
        case "$1" in
            scraper)
                log_info "Starting scraper service..."
                # Use supervisor to manage scraper process
                exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
                ;;
            bash|sh)
                log_info "Starting interactive shell..."
                exec /bin/bash
                ;;
            *)
                log_info "Executing custom command: $*"
                exec "$@"
                ;;
        esac
    else
        log_info "No command specified, starting scraper service..."
        exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
    fi
}

# Run main function
main "$@"
