#!/bin/bash

# Elasticsearch Health Monitor and Auto-Restart Script
# Location: /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh
# Purpose: Monitor Elasticsearch health and auto-restart docker-compose services if unhealthy
# Frequency: Run via cron every 5 minutes
#
# DEPLOYMENT INSTRUCTIONS:
# 1. Deploy this file to the server:
#    scp -P 2222 DevOps/scripts/monitor-elasticsearch.sh andrzej@65.109.22.232:/home/andrzej/DevOps/scripts/
#    ssh -p 2222 andrzej@65.109.22.232 "chmod +x /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh"
#
# 2. Deploy the crontab configuration:
#    scp -P 2222 DevOps/config/cron.d/elasticsearch-monitoring andrzej@65.109.22.232:/tmp/
#    ssh -p 2222 andrzej@65.109.22.232 "sudo cp /tmp/elasticsearch-monitoring /etc/cron.d/ && sudo chmod 644 /etc/cron.d/elasticsearch-monitoring"
#
# 3. Deploy the logrotate configuration:
#    scp -P 2222 DevOps/config/logrotate.d/elasticsearch-monitoring andrzej@65.109.22.232:/tmp/
#    ssh -p 2222 andrzej@65.109.22.232 "sudo cp /tmp/elasticsearch-monitoring /etc/logrotate.d/ && sudo chmod 644 /etc/logrotate.d/elasticsearch-monitoring"
#
# 4. Create log directory:
#    ssh -p 2222 andrzej@65.109.22.232 "mkdir -p /home/andrzej/logs/elasticsearch-monitoring"
#
# 5. Verify cron job:
#    ssh -p 2222 andrzej@65.109.22.232 "sudo crontab -l"
#
# TESTING:
#    ssh -p 2222 andrzej@65.109.22.232 "/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh"

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Import common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/../common"

# Source common utilities if available
if [ -f "${COMMON_DIR}/utils.sh" ]; then
    source "${COMMON_DIR}/utils.sh"
fi

if [ -f "${COMMON_DIR}/elasticsearch-check.sh" ]; then
    source "${COMMON_DIR}/elasticsearch-check.sh"
fi

# Elasticsearch configuration
ES_URL="${ELASTICSEARCH_URL:-http://172.17.0.1:9200}"
ES_USERNAME="${ELASTICSEARCH_USERNAME:-}"
ES_PASSWORD="${ELASTICSEARCH_PASSWORD:-}"

# Docker compose configuration (adjust based on your setup)
# Note: Elasticsearch might be running as a docker-compose service or managed externally
DOCKER_COMPOSE_DIR="${DOCKER_COMPOSE_DIR:-/home/andrzej/apps/cheaperfordrug-api/docker}"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-docker-compose.yml}"
ES_SERVICE_NAME="${ES_SERVICE_NAME:-elasticsearch}"

# Retry configuration
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY=5  # seconds between retries

# Logging configuration
LOG_DIR="${LOG_DIR:-/home/andrzej/logs/elasticsearch-monitoring}"
LOG_FILE="${LOG_DIR}/monitor.log"
MAX_LOG_LINES=10000  # Rotate when log exceeds this

# Alert configuration (optional - can be integrated with email notifications)
ALERT_EMAIL="${ALERT_EMAIL:-}"
SEND_ALERTS="${SEND_ALERTS:-false}"

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$@"
}

log_warning() {
    log "WARNING" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

# ==============================================================================
# SETUP FUNCTIONS
# ==============================================================================

setup_logging() {
    # Create log directory if it doesn't exist
    mkdir -p "${LOG_DIR}"

    # Create log file if it doesn't exist
    if [ ! -f "${LOG_FILE}" ]; then
        touch "${LOG_FILE}"
    fi

    # Rotate log if too large (simple rotation, logrotate will handle the rest)
    if [ -f "${LOG_FILE}" ]; then
        local line_count=$(wc -l < "${LOG_FILE}")
        if [ "${line_count}" -gt "${MAX_LOG_LINES}" ]; then
            log_info "Rotating log file (${line_count} lines)"
            mv "${LOG_FILE}" "${LOG_FILE}.old"
            touch "${LOG_FILE}"
        fi
    fi
}

# ==============================================================================
# HEALTH CHECK FUNCTIONS
# ==============================================================================

check_elasticsearch_available() {
    local url="$1"
    local username="$2"
    local password="$3"

    # Use the common elasticsearch-check.sh function if available
    if type check_elasticsearch_health >/dev/null 2>&1; then
        check_elasticsearch_health "$url" "$username" "$password"
        return $?
    fi

    # Fallback to basic curl check
    local auth_flag=""
    if [ -n "$username" ] && [ -n "$password" ]; then
        auth_flag="-u ${username}:${password}"
    fi

    local response=$(curl -s $auth_flag -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)

    if [ "$response" = "200" ]; then
        return 0
    else
        return 1
    fi
}

get_cluster_health() {
    local url="$1"
    local username="$2"
    local password="$3"

    # Use the common function if available
    if type get_elasticsearch_cluster_health >/dev/null 2>&1; then
        get_elasticsearch_cluster_health "$url" "$username" "$password"
        return
    fi

    # Fallback implementation
    local auth_flag=""
    if [ -n "$username" ] && [ -n "$password" ]; then
        auth_flag="-u ${username}:${password}"
    fi

    local health=$(curl -s $auth_flag "${url}/_cluster/health" 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$health" ]; then
        echo "$health"
    else
        echo "unreachable"
    fi
}

# ==============================================================================
# RESTART FUNCTIONS
# ==============================================================================

restart_elasticsearch_docker() {
    if [ -z "${DOCKER_COMPOSE_DIR}" ]; then
        log_warning "DOCKER_COMPOSE_DIR not set, skipping docker-compose restart"
        return 1
    fi

    if [ ! -d "${DOCKER_COMPOSE_DIR}" ]; then
        log_error "Docker compose directory not found: ${DOCKER_COMPOSE_DIR}"
        return 1
    fi

    if [ ! -f "${DOCKER_COMPOSE_DIR}/${DOCKER_COMPOSE_FILE}" ]; then
        log_error "Docker compose file not found: ${DOCKER_COMPOSE_DIR}/${DOCKER_COMPOSE_FILE}"
        return 1
    fi

    log_info "Restarting Elasticsearch via docker-compose in ${DOCKER_COMPOSE_DIR}"

    cd "${DOCKER_COMPOSE_DIR}"

    # Try to restart the specific service first
    if docker-compose ps | grep -q "${ES_SERVICE_NAME}"; then
        log_info "Restarting service: ${ES_SERVICE_NAME}"
        docker-compose restart "${ES_SERVICE_NAME}" 2>&1 | tee -a "${LOG_FILE}"
    else
        log_warning "Service ${ES_SERVICE_NAME} not found in docker-compose"
        log_info "Attempting to restart all docker-compose services"
        docker-compose restart 2>&1 | tee -a "${LOG_FILE}"
    fi

    if [ $? -eq 0 ]; then
        log_success "Docker-compose restart completed"
        return 0
    else
        log_error "Docker-compose restart failed"
        return 1
    fi
}

# ==============================================================================
# ALERT FUNCTIONS
# ==============================================================================

send_alert() {
    local subject="$1"
    local message="$2"

    if [ "${SEND_ALERTS}" != "true" ]; then
        return 0
    fi

    if [ -z "${ALERT_EMAIL}" ]; then
        log_warning "ALERT_EMAIL not configured, skipping alert"
        return 0
    fi

    # Try to use the email notification system if available
    if [ -f "${COMMON_DIR}/email-notification.sh" ]; then
        source "${COMMON_DIR}/email-notification.sh"

        if type send_deployment_failure_email >/dev/null 2>&1; then
            log_info "Sending alert via email notification system"
            # Adapt the message for the email system
            send_deployment_failure_email "elasticsearch-monitor" "$subject" "$message"
            return $?
        fi
    fi

    # Fallback to simple mail command
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$subject" "$ALERT_EMAIL"
        log_info "Alert sent to ${ALERT_EMAIL}"
    else
        log_warning "No email command available, cannot send alert"
    fi
}

# ==============================================================================
# MAIN MONITORING LOGIC
# ==============================================================================

monitor_elasticsearch() {
    local attempt=1
    local healthy=false
    local restart_attempted=false

    log_info "======================================================================"
    log_info "Starting Elasticsearch health check (URL: ${ES_URL})"
    log_info "======================================================================"

    # Attempt health check with retries
    while [ $attempt -le $MAX_RETRY_ATTEMPTS ]; do
        log_info "Health check attempt ${attempt}/${MAX_RETRY_ATTEMPTS}"

        if check_elasticsearch_available "$ES_URL" "$ES_USERNAME" "$ES_PASSWORD"; then
            local cluster_health=$(get_cluster_health "$ES_URL" "$ES_USERNAME" "$ES_PASSWORD")
            log_success "Elasticsearch is responding"
            log_info "Cluster health status: ${cluster_health}"

            # Check if health is acceptable (green or yellow)
            if [ "$cluster_health" = "green" ] || [ "$cluster_health" = "yellow" ]; then
                log_success "Elasticsearch cluster health is acceptable: ${cluster_health}"
                healthy=true
                break
            elif [ "$cluster_health" = "red" ]; then
                log_error "Elasticsearch cluster health is RED - data loss or unavailability detected"
                send_alert "Elasticsearch Cluster RED" "Elasticsearch cluster health is RED. Manual intervention may be required."
                # Don't restart on RED status - may indicate data issues
                return 1
            else
                log_warning "Elasticsearch cluster health is unknown: ${cluster_health}"
            fi
        else
            log_error "Elasticsearch health check failed (attempt ${attempt}/${MAX_RETRY_ATTEMPTS})"
        fi

        if [ $attempt -lt $MAX_RETRY_ATTEMPTS ]; then
            log_info "Waiting ${RETRY_DELAY} seconds before retry..."
            sleep $RETRY_DELAY
        fi

        ((attempt++))
    done

    # If still unhealthy after retries, attempt restart
    if [ "$healthy" = false ]; then
        log_error "Elasticsearch is unhealthy after ${MAX_RETRY_ATTEMPTS} attempts"

        if [ "$restart_attempted" = false ]; then
            log_warning "Attempting to restart Elasticsearch..."
            send_alert "Elasticsearch Down - Attempting Restart" "Elasticsearch failed health checks. Automatic restart initiated."

            if restart_elasticsearch_docker; then
                restart_attempted=true
                log_info "Restart completed, waiting 30 seconds for service to come up..."
                sleep 30

                # Verify restart was successful
                if check_elasticsearch_available "$ES_URL" "$ES_USERNAME" "$ES_PASSWORD"; then
                    local cluster_health=$(get_cluster_health "$ES_URL" "$ES_USERNAME" "$ES_PASSWORD")
                    log_success "Elasticsearch is now responding after restart"
                    log_info "Cluster health status: ${cluster_health}"
                    send_alert "Elasticsearch Restart Successful" "Elasticsearch was restarted successfully. Current health: ${cluster_health}"
                    return 0
                else
                    log_error "Elasticsearch still not responding after restart"
                    send_alert "Elasticsearch Restart Failed" "Elasticsearch restart failed. Manual intervention required."
                    return 1
                fi
            else
                log_error "Failed to restart Elasticsearch via docker-compose"
                send_alert "Elasticsearch Restart Failed" "Failed to restart Elasticsearch via docker-compose. Manual intervention required."
                return 1
            fi
        fi
    else
        log_success "Elasticsearch monitoring check completed - service is healthy"
        return 0
    fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    # Setup logging
    setup_logging

    # Run monitoring
    monitor_elasticsearch
    local exit_code=$?

    log_info "======================================================================"
    log_info "Elasticsearch monitoring completed with exit code: ${exit_code}"
    log_info "======================================================================"
    echo ""

    exit $exit_code
}

# Only run main if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
