#!/bin/bash
set -euo pipefail

# Elasticsearch Security Script
# Purpose: Block external access to Elasticsearch ports 9200 and 9300
# Location: /home/andrzej/DevOps/scripts/secure-elasticsearch.sh
#
# This script addresses the BSI security notification about publicly
# accessible Elasticsearch instances.
#
# IMPORTANT: Docker containers use the FORWARD chain, not INPUT.
# Rules must be added to DOCKER-USER chain to take effect.
#
# Usage: ./secure-elasticsearch.sh [--apply|--check|--remove]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
ES_HTTP_PORT=9200
ES_TRANSPORT_PORT=9300
DOCKER_NETWORK_1="172.17.0.0/16"
DOCKER_NETWORK_2="172.18.0.0/16"
LOCALHOST="127.0.0.0/8"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_header() {
    echo ""
    echo "=============================================="
    echo "$1"
    echo "=============================================="
}

# Check if running as root or with sudo
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Check current iptables rules for ES ports
check_current_rules() {
    log_header "Current DOCKER-USER chain rules"

    if iptables -L DOCKER-USER -n --line-numbers 2>/dev/null | grep -E "${ES_HTTP_PORT}|${ES_TRANSPORT_PORT}"; then
        log_info "Found rules for Elasticsearch ports"
    else
        log_warn "No DOCKER-USER rules found for Elasticsearch ports"
        log_warn "Elasticsearch may be publicly accessible!"
    fi

    log_header "Current INPUT chain rules for ES ports"
    iptables -L INPUT -n --line-numbers 2>/dev/null | grep -E "${ES_HTTP_PORT}|${ES_TRANSPORT_PORT}" || log_info "No INPUT rules for ES ports"

    # Check if ports are listening
    log_header "Elasticsearch port listening status"
    ss -tlnp 2>/dev/null | grep -E ":${ES_HTTP_PORT}|:${ES_TRANSPORT_PORT}" || log_info "Elasticsearch ports not listening"

    # Check Docker port bindings
    log_header "Docker containers with Elasticsearch ports"
    docker ps --format "table {{.Names}}\t{{.Ports}}" 2>/dev/null | grep -E "${ES_HTTP_PORT}|${ES_TRANSPORT_PORT}|PORTS" || log_info "No containers using Elasticsearch ports"
}

# Test external accessibility
test_external_access() {
    log_header "Testing external accessibility"

    # Get public IP
    local public_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "unknown")
    log_info "Server public IP: ${public_ip}"

    # Test localhost access (should work)
    if curl -s --connect-timeout 3 "http://localhost:${ES_HTTP_PORT}" > /dev/null 2>&1; then
        log_success "Elasticsearch is responding on localhost:${ES_HTTP_PORT} (internal access works)"
    else
        log_warn "Elasticsearch is not responding on localhost:${ES_HTTP_PORT}"
    fi
}

# Apply firewall rules to secure Elasticsearch
apply_security_rules() {
    log_header "Applying Elasticsearch Security Rules"

    check_root

    # Ensure DOCKER-USER chain exists
    if ! iptables -L DOCKER-USER -n &>/dev/null; then
        log_info "Creating DOCKER-USER chain..."
        iptables -N DOCKER-USER 2>/dev/null || true
    fi

    # Remove any existing rules for ES ports in DOCKER-USER
    log_info "Removing any existing DOCKER-USER rules for ES ports..."
    while iptables -D DOCKER-USER -p tcp --dport ${ES_HTTP_PORT} -j DROP 2>/dev/null; do :; done
    while iptables -D DOCKER-USER -p tcp --dport ${ES_HTTP_PORT} -j RETURN 2>/dev/null; do :; done
    while iptables -D DOCKER-USER -p tcp --dport ${ES_TRANSPORT_PORT} -j DROP 2>/dev/null; do :; done
    while iptables -D DOCKER-USER -p tcp --dport ${ES_TRANSPORT_PORT} -j RETURN 2>/dev/null; do :; done

    # Add rules to DOCKER-USER chain (Docker traffic goes through FORWARD, not INPUT)
    log_info "Adding DOCKER-USER rules for port ${ES_HTTP_PORT}..."

    # Allow from localhost
    iptables -I DOCKER-USER -p tcp --dport ${ES_HTTP_PORT} -s ${LOCALHOST} -j RETURN
    # Allow from Docker networks
    iptables -I DOCKER-USER -p tcp --dport ${ES_HTTP_PORT} -s ${DOCKER_NETWORK_1} -j RETURN
    iptables -I DOCKER-USER -p tcp --dport ${ES_HTTP_PORT} -s ${DOCKER_NETWORK_2} -j RETURN
    # Drop all other traffic
    iptables -A DOCKER-USER -p tcp --dport ${ES_HTTP_PORT} -j DROP

    log_info "Adding DOCKER-USER rules for port ${ES_TRANSPORT_PORT}..."
    # Allow from localhost
    iptables -I DOCKER-USER -p tcp --dport ${ES_TRANSPORT_PORT} -s ${LOCALHOST} -j RETURN
    # Allow from Docker networks
    iptables -I DOCKER-USER -p tcp --dport ${ES_TRANSPORT_PORT} -s ${DOCKER_NETWORK_1} -j RETURN
    iptables -I DOCKER-USER -p tcp --dport ${ES_TRANSPORT_PORT} -s ${DOCKER_NETWORK_2} -j RETURN
    # Drop all other traffic
    iptables -A DOCKER-USER -p tcp --dport ${ES_TRANSPORT_PORT} -j DROP

    # IPv6 rules
    log_info "Adding IPv6 rules..."
    if ip6tables -L DOCKER-USER -n &>/dev/null; then
        ip6tables -I DOCKER-USER -p tcp --dport ${ES_HTTP_PORT} -j DROP 2>/dev/null || true
        ip6tables -I DOCKER-USER -p tcp --dport ${ES_TRANSPORT_PORT} -j DROP 2>/dev/null || true
    fi

    # Also add INPUT rules as backup (for non-Docker access attempts)
    log_info "Adding INPUT chain backup rules..."
    # Remove existing INPUT rules first
    while iptables -D INPUT -p tcp --dport ${ES_HTTP_PORT} -j DROP 2>/dev/null; do :; done
    while iptables -D INPUT -p tcp --dport ${ES_HTTP_PORT} -j ACCEPT 2>/dev/null; do :; done
    while iptables -D INPUT -p tcp --dport ${ES_TRANSPORT_PORT} -j DROP 2>/dev/null; do :; done
    while iptables -D INPUT -p tcp --dport ${ES_TRANSPORT_PORT} -j ACCEPT 2>/dev/null; do :; done

    # Add INPUT rules
    iptables -I INPUT -p tcp --dport ${ES_HTTP_PORT} -s 127.0.0.1 -j ACCEPT
    iptables -I INPUT -p tcp --dport ${ES_HTTP_PORT} -s ${DOCKER_NETWORK_1} -j ACCEPT
    iptables -A INPUT -p tcp --dport ${ES_HTTP_PORT} -j DROP

    iptables -I INPUT -p tcp --dport ${ES_TRANSPORT_PORT} -s 127.0.0.1 -j ACCEPT
    iptables -I INPUT -p tcp --dport ${ES_TRANSPORT_PORT} -s ${DOCKER_NETWORK_1} -j ACCEPT
    iptables -A INPUT -p tcp --dport ${ES_TRANSPORT_PORT} -j DROP

    # IPv6 INPUT rules
    ip6tables -I INPUT -p tcp --dport ${ES_HTTP_PORT} -s ::1 -j ACCEPT 2>/dev/null || true
    ip6tables -A INPUT -p tcp --dport ${ES_HTTP_PORT} -j DROP 2>/dev/null || true
    ip6tables -I INPUT -p tcp --dport ${ES_TRANSPORT_PORT} -s ::1 -j ACCEPT 2>/dev/null || true
    ip6tables -A INPUT -p tcp --dport ${ES_TRANSPORT_PORT} -j DROP 2>/dev/null || true

    log_success "Firewall rules applied successfully"

    # Save rules persistently
    save_rules

    # Verify
    check_current_rules
}

# Save iptables rules persistently
save_rules() {
    log_header "Saving iptables rules persistently"

    # Install iptables-persistent if not present
    if ! dpkg -l 2>/dev/null | grep -q iptables-persistent; then
        log_info "Installing iptables-persistent..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    fi

    # Save current rules
    log_info "Saving current iptables rules..."
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6

    log_success "Rules saved to /etc/iptables/rules.v4 and rules.v6"
}

# Remove security rules (for testing/rollback)
remove_security_rules() {
    log_header "Removing Elasticsearch Security Rules"

    check_root

    log_info "Removing DOCKER-USER rules for ES ports..."
    while iptables -D DOCKER-USER -p tcp --dport ${ES_HTTP_PORT} -j DROP 2>/dev/null; do :; done
    while iptables -D DOCKER-USER -p tcp --dport ${ES_HTTP_PORT} -j RETURN 2>/dev/null; do :; done
    while iptables -D DOCKER-USER -p tcp --dport ${ES_TRANSPORT_PORT} -j DROP 2>/dev/null; do :; done
    while iptables -D DOCKER-USER -p tcp --dport ${ES_TRANSPORT_PORT} -j RETURN 2>/dev/null; do :; done

    log_info "Removing INPUT rules for ES ports..."
    while iptables -D INPUT -p tcp --dport ${ES_HTTP_PORT} -j DROP 2>/dev/null; do :; done
    while iptables -D INPUT -p tcp --dport ${ES_HTTP_PORT} -j ACCEPT 2>/dev/null; do :; done
    while iptables -D INPUT -p tcp --dport ${ES_TRANSPORT_PORT} -j DROP 2>/dev/null; do :; done
    while iptables -D INPUT -p tcp --dport ${ES_TRANSPORT_PORT} -j ACCEPT 2>/dev/null; do :; done

    log_info "Removing IPv6 rules..."
    while ip6tables -D INPUT -p tcp --dport ${ES_HTTP_PORT} -j DROP 2>/dev/null; do :; done
    while ip6tables -D INPUT -p tcp --dport ${ES_HTTP_PORT} -j ACCEPT 2>/dev/null; do :; done
    while ip6tables -D DOCKER-USER -p tcp --dport ${ES_HTTP_PORT} -j DROP 2>/dev/null; do :; done

    log_success "Rules removed"

    # Update persistent rules
    if [ -f /etc/iptables/rules.v4 ]; then
        iptables-save > /etc/iptables/rules.v4
        ip6tables-save > /etc/iptables/rules.v6
        log_info "Persistent rules updated"
    fi

    check_current_rules
}

# Main
main() {
    local action="${1:-check}"

    log_header "Elasticsearch Security Script"
    log_info "Action: ${action}"
    log_info "HTTP Port: ${ES_HTTP_PORT}"
    log_info "Transport Port: ${ES_TRANSPORT_PORT}"

    case "$action" in
        --apply|-a|apply)
            apply_security_rules
            test_external_access
            ;;
        --remove|-r|remove)
            remove_security_rules
            ;;
        --check|-c|check|*)
            check_current_rules
            test_external_access
            ;;
    esac

    echo ""
    log_info "Done."
}

main "$@"
