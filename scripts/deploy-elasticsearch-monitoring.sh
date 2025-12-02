#!/bin/bash

# Elasticsearch Monitoring Deployment Script
# Location: /home/andrzej/DevOps/scripts/deploy-elasticsearch-monitoring.sh
# Purpose: Deploy Elasticsearch monitoring to the production server
#
# USAGE:
#   Local execution (from development machine):
#     ./DevOps/scripts/deploy-elasticsearch-monitoring.sh
#
#   Or copy and run on server:
#     scp -P 2222 DevOps/scripts/deploy-elasticsearch-monitoring.sh andrzej@65.109.22.232:/tmp/
#     ssh -p 2222 andrzej@65.109.22.232 "bash /tmp/deploy-elasticsearch-monitoring.sh"

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Server configuration (adjust as needed)
SERVER_USER="${SERVER_USER:-andrzej}"
SERVER_HOST="${SERVER_HOST:-65.109.22.232}"
SERVER_PORT="${SERVER_PORT:-2222}"
REMOTE_DEVOPS_DIR="/home/${SERVER_USER}/DevOps"

# Local paths (relative to DevOps directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Files to deploy
MONITOR_SCRIPT="scripts/monitor-elasticsearch.sh"
CRON_FILE="config/cron.d/elasticsearch-monitoring"
LOGROTATE_FILE="config/logrotate.d/elasticsearch-monitoring"

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# ==============================================================================
# DEPLOYMENT FUNCTIONS
# ==============================================================================

check_local_files() {
    log_header "Checking Local Files"

    local all_files_exist=true

    for file in "$MONITOR_SCRIPT" "$CRON_FILE" "$LOGROTATE_FILE"; do
        local full_path="${DEVOPS_ROOT}/${file}"
        if [ -f "$full_path" ]; then
            log_success "Found: ${file}"
        else
            log_error "Missing: ${file}"
            all_files_exist=false
        fi
    done

    if [ "$all_files_exist" = false ]; then
        log_error "Some required files are missing. Cannot proceed."
        exit 1
    fi

    log_success "All required files are present"
}

is_remote_deployment() {
    # Check if we're running on the production server
    if [ -f "/home/${SERVER_USER}/DevOps/scripts/monitor-elasticsearch.sh" ]; then
        return 0  # We're on the server
    else
        return 1  # We're on local machine
    fi
}

deploy_remote() {
    log_header "Deploying to Remote Server"

    log_info "Deploying to ${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}"

    # Create remote directories
    log_info "Creating remote directories..."
    ssh -p "$SERVER_PORT" "${SERVER_USER}@${SERVER_HOST}" "mkdir -p ${REMOTE_DEVOPS_DIR}/scripts ${REMOTE_DEVOPS_DIR}/config/cron.d ${REMOTE_DEVOPS_DIR}/config/logrotate.d"

    # Deploy monitoring script
    log_info "Deploying monitoring script..."
    scp -P "$SERVER_PORT" "${DEVOPS_ROOT}/${MONITOR_SCRIPT}" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_DEVOPS_DIR}/${MONITOR_SCRIPT}"
    ssh -p "$SERVER_PORT" "${SERVER_USER}@${SERVER_HOST}" "chmod +x ${REMOTE_DEVOPS_DIR}/${MONITOR_SCRIPT}"
    log_success "Monitoring script deployed"

    # Deploy cron configuration
    log_info "Deploying cron configuration..."
    scp -P "$SERVER_PORT" "${DEVOPS_ROOT}/${CRON_FILE}" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_DEVOPS_DIR}/${CRON_FILE}"
    log_success "Cron configuration deployed"

    # Deploy logrotate configuration
    log_info "Deploying logrotate configuration..."
    scp -P "$SERVER_PORT" "${DEVOPS_ROOT}/${LOGROTATE_FILE}" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_DEVOPS_DIR}/${LOGROTATE_FILE}"
    log_success "Logrotate configuration deployed"

    log_success "All files deployed to server"
}

install_on_server() {
    log_header "Installing Monitoring Components"

    # Determine paths based on where we're running
    local devops_dir
    if is_remote_deployment; then
        devops_dir="${REMOTE_DEVOPS_DIR}"
    else
        log_error "This function must be run on the server"
        exit 1
    fi

    # Create log directory
    log_info "Creating log directory..."
    mkdir -p /home/${SERVER_USER}/logs/elasticsearch-monitoring
    log_success "Log directory created"

    # Install cron configuration
    log_info "Installing cron configuration..."
    sudo cp "${devops_dir}/${CRON_FILE}" /etc/cron.d/elasticsearch-monitoring
    sudo chmod 644 /etc/cron.d/elasticsearch-monitoring
    sudo chown root:root /etc/cron.d/elasticsearch-monitoring
    log_success "Cron configuration installed"

    # Install logrotate configuration
    log_info "Installing logrotate configuration..."
    sudo cp "${devops_dir}/${LOGROTATE_FILE}" /etc/logrotate.d/elasticsearch-monitoring
    sudo chmod 644 /etc/logrotate.d/elasticsearch-monitoring
    sudo chown root:root /etc/logrotate.d/elasticsearch-monitoring
    log_success "Logrotate configuration installed"

    # Test logrotate configuration
    log_info "Testing logrotate configuration..."
    if sudo logrotate -d /etc/logrotate.d/elasticsearch-monitoring >/dev/null 2>&1; then
        log_success "Logrotate configuration is valid"
    else
        log_warning "Logrotate configuration test had warnings (this may be normal)"
    fi

    # Reload cron
    log_info "Reloading cron service..."
    sudo systemctl reload cron 2>/dev/null || sudo service cron reload 2>/dev/null || true
    log_success "Cron service reloaded"
}

test_monitoring() {
    log_header "Testing Monitoring Script"

    local script_path
    if is_remote_deployment; then
        script_path="${REMOTE_DEVOPS_DIR}/${MONITOR_SCRIPT}"
    else
        log_error "This function must be run on the server"
        exit 1
    fi

    log_info "Running test execution of monitoring script..."
    log_warning "This will check Elasticsearch health and potentially trigger restarts if unhealthy"

    if bash "$script_path"; then
        log_success "Monitoring script executed successfully"
    else
        log_warning "Monitoring script reported issues (exit code: $?)"
        log_info "Check logs at: /home/${SERVER_USER}/logs/elasticsearch-monitoring/monitor.log"
    fi

    # Show recent log entries
    log_info "Recent log entries:"
    if [ -f "/home/${SERVER_USER}/logs/elasticsearch-monitoring/monitor.log" ]; then
        tail -20 "/home/${SERVER_USER}/logs/elasticsearch-monitoring/monitor.log" | sed 's/^/  /'
    else
        log_warning "Log file not created yet"
    fi
}

verify_installation() {
    log_header "Verifying Installation"

    local all_ok=true

    # Check cron file
    if [ -f "/etc/cron.d/elasticsearch-monitoring" ]; then
        log_success "Cron configuration installed"
    else
        log_error "Cron configuration not found"
        all_ok=false
    fi

    # Check logrotate file
    if [ -f "/etc/logrotate.d/elasticsearch-monitoring" ]; then
        log_success "Logrotate configuration installed"
    else
        log_error "Logrotate configuration not found"
        all_ok=false
    fi

    # Check log directory
    if [ -d "/home/${SERVER_USER}/logs/elasticsearch-monitoring" ]; then
        log_success "Log directory exists"
    else
        log_error "Log directory not found"
        all_ok=false
    fi

    # Check monitoring script
    if [ -f "${REMOTE_DEVOPS_DIR}/${MONITOR_SCRIPT}" ] && [ -x "${REMOTE_DEVOPS_DIR}/${MONITOR_SCRIPT}" ]; then
        log_success "Monitoring script is executable"
    else
        log_error "Monitoring script not found or not executable"
        all_ok=false
    fi

    if [ "$all_ok" = true ]; then
        log_success "All components verified successfully"
    else
        log_error "Some components are missing or misconfigured"
        exit 1
    fi
}

show_usage_instructions() {
    log_header "Deployment Complete"

    cat << EOF
${GREEN}Elasticsearch monitoring has been successfully deployed!${NC}

${BLUE}What was installed:${NC}
  • Monitoring script: ${REMOTE_DEVOPS_DIR}/scripts/monitor-elasticsearch.sh
  • Cron job: /etc/cron.d/elasticsearch-monitoring (runs every 5 minutes)
  • Log rotation: /etc/logrotate.d/elasticsearch-monitoring

${BLUE}Log locations:${NC}
  • Monitoring logs: /home/${SERVER_USER}/logs/elasticsearch-monitoring/monitor.log
  • Cron logs: /home/${SERVER_USER}/logs/elasticsearch-monitoring/cron.log

${BLUE}Useful commands:${NC}
  # View monitoring logs
  tail -f /home/${SERVER_USER}/logs/elasticsearch-monitoring/monitor.log

  # View cron execution logs
  tail -f /home/${SERVER_USER}/logs/elasticsearch-monitoring/cron.log

  # Run monitoring check manually
  /home/${SERVER_USER}/DevOps/scripts/monitor-elasticsearch.sh

  # Check cron job status
  sudo grep elasticsearch /etc/cron.d/elasticsearch-monitoring

  # View system cron logs
  sudo tail -f /var/log/syslog | grep CRON

  # Test logrotate
  sudo logrotate -d /etc/logrotate.d/elasticsearch-monitoring

${BLUE}Configuration:${NC}
  The monitoring script can be configured via environment variables in the cron file:
  • ELASTICSEARCH_URL (default: http://localhost:9200)
  • DOCKER_COMPOSE_DIR (if ES runs in docker-compose)
  • ES_SERVICE_NAME (default: elasticsearch)
  • SEND_ALERTS (set to 'true' to enable email alerts)
  • ALERT_EMAIL (email address for alerts)

  Edit: sudo nano /etc/cron.d/elasticsearch-monitoring

${BLUE}Next steps:${NC}
  1. Monitor the logs to ensure the cron job runs successfully
  2. Adjust the schedule in /etc/cron.d/elasticsearch-monitoring if needed
  3. Configure email alerts if desired
  4. Test the auto-restart functionality by stopping Elasticsearch

${YELLOW}Note:${NC} The first cron execution will occur at the next 5-minute interval.
You can run the script manually now to verify it works.

EOF
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    log_header "Elasticsearch Monitoring Deployment"

    # Check if we're on the server or local machine
    if is_remote_deployment; then
        log_info "Running on production server"
        install_on_server
        verify_installation
        test_monitoring
        show_usage_instructions
    else
        log_info "Running from local machine"
        check_local_files
        deploy_remote

        log_info "Files deployed to server. Now installing on server..."
        ssh -p "$SERVER_PORT" "${SERVER_USER}@${SERVER_HOST}" "bash -s" << 'ENDSSH'
            set -euo pipefail
            source /home/andrzej/DevOps/scripts/deploy-elasticsearch-monitoring.sh
            install_on_server
            verify_installation
            test_monitoring
            show_usage_instructions
ENDSSH

        log_success "Deployment completed successfully"
    fi
}

# Only run main if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
