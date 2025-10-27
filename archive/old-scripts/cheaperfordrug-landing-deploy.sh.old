#!/bin/bash

# Application-specific deployment script for cheaperfordrug-landing
# Location: /home/andrzej/DevOps/apps/cheaperfordrug-landing/deploy.sh
# Usage: ./deploy.sh [command] [scale]

set -euo pipefail

# Parse arguments
COMMAND="${1:-deploy}"
SCALE="${2:-}"

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG_DIR="$SCRIPT_DIR"
DEVOPS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load app configuration
if [ ! -f "${APP_CONFIG_DIR}/config.sh" ]; then
    echo "Error: Configuration file not found: ${APP_CONFIG_DIR}/config.sh"
    exit 1
fi

source "${APP_CONFIG_DIR}/config.sh"

# Load common utilities
source "${DEVOPS_DIR}/common/utils.sh"
source "${DEVOPS_DIR}/common/docker-utils.sh"

# Load Rails-specific functions
source "${DEVOPS_DIR}/common/rails/deploy.sh"

# Set scale if not provided
if [ -z "$SCALE" ]; then
    SCALE="$DEFAULT_SCALE"
fi

# Validate scale parameter
if ! [[ "$SCALE" =~ ^[0-9]+$ ]]; then
    log_error "Scale must be a positive integer"
    exit 1
fi

# ============================================================================
# OVERRIDE/EXTEND FUNCTIONS
# ============================================================================
# You can override any function from common/rails/deploy.sh here

# Example: Add custom pre-deployment checks
# pre_deploy_hook() {
#     log_info "Running custom pre-deployment checks..."
#     # Your custom logic here
#     return 0
# }

# Example: Override Rails migration check to add custom logic
# rails_check_pending_migrations() {
#     local test_container="$1"
#
#     log_info "Custom migration check for cheaperfordrug-landing..."
#
#     # Call original function or implement custom logic
#     source "${DEVOPS_DIR}/common/rails/deploy.sh"
#
#     return $?
# }

# ============================================================================
# NOTIFICATION FUNCTIONS
# ============================================================================

# Send deployment success notification
send_deploy_success_notification() {
    local scale="$1"
    local image_tag="$2"

    send_mailgun_notification \
        "${APP_DISPLAY_NAME} - Deployment Successful" \
        "Application ${APP_NAME} has been deployed successfully!

Timestamp: $(date)
Host: $(hostname)
Image Tag: ${image_tag}
Scale: ${scale} instances
Git Commit: ${CURRENT_COMMIT:0:7}

All containers are healthy and serving traffic.
Domain: ${DOMAIN}" \
        "$MAILGUN_API_KEY" \
        "$MAILGUN_DOMAIN" \
        "$NOTIFICATION_EMAIL"
}

# Send deployment failure notification
send_deploy_failure_notification() {
    local error_msg="$1"

    send_mailgun_notification \
        "${APP_DISPLAY_NAME} - Deployment Failed" \
        "Deployment failed for ${APP_NAME}.

Timestamp: $(date)
Host: $(hostname)
Error: ${error_msg}

Please check the logs for more details.
Logs: ${LOG_DIR}" \
        "$MAILGUN_API_KEY" \
        "$MAILGUN_DOMAIN" \
        "$NOTIFICATION_EMAIL"
}

# Send restart notification
send_restart_notification() {
    local scale="$1"

    send_mailgun_notification \
        "${APP_DISPLAY_NAME} - Restart Completed" \
        "Application ${APP_NAME} has been restarted.

Timestamp: $(date)
Host: $(hostname)
Scale: ${scale} instances

All containers are healthy." \
        "$MAILGUN_API_KEY" \
        "$MAILGUN_DOMAIN" \
        "$NOTIFICATION_EMAIL"
}

# Send scale notification
send_scale_notification() {
    local old_scale="$1"
    local new_scale="$2"

    local scale_direction="scaled"
    if [ $new_scale -gt $old_scale ]; then
        scale_direction="scaled up"
    elif [ $new_scale -lt $old_scale ]; then
        scale_direction="scaled down"
    fi

    send_mailgun_notification \
        "${APP_DISPLAY_NAME} - Application ${scale_direction^}" \
        "Application ${APP_NAME} has been ${scale_direction}.

Timestamp: $(date)
Host: $(hostname)
Previous Scale: ${old_scale} instances
New Scale: ${new_scale} instances

All containers are healthy." \
        "$MAILGUN_API_KEY" \
        "$MAILGUN_DOMAIN" \
        "$NOTIFICATION_EMAIL"
}

# Send stop notification
send_stop_notification() {
    local container_count="$1"

    send_mailgun_notification \
        "${APP_DISPLAY_NAME} - Application Stopped" \
        "Application ${APP_NAME} has been stopped.

Timestamp: $(date)
Host: $(hostname)
Containers stopped: ${container_count}

To restart, run: ${SCRIPT_DIR}/deploy.sh deploy" \
        "$MAILGUN_API_KEY" \
        "$MAILGUN_DOMAIN" \
        "$NOTIFICATION_EMAIL"
}

# ============================================================================
# COMMAND HANDLERS
# ============================================================================

# Handle deploy command
handle_deploy() {
    local scale="$1"

    # Check if setup has been run
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Application not set up. Please run setup.sh first."
        log_info "Run: ${SCRIPT_DIR}/setup.sh"
        exit 1
    fi

    if [ ! -d "$REPO_DIR" ]; then
        log_error "Repository not found. Please run setup.sh first."
        exit 1
    fi

    # Load environment variables
    load_env_file "$ENV_FILE"

    # Run Rails deployment workflow
    local image_tag="$(date +%Y%m%d_%H%M%S)"

    if rails_deploy_application "$scale"; then
        send_deploy_success_notification "$scale" "$image_tag"
        exit 0
    else
        send_deploy_failure_notification "Deployment workflow failed"
        exit 1
    fi
}

# Handle restart command
handle_restart() {
    local scale="$1"

    # Check if setup has been run
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Application not set up. Please run setup.sh first."
        exit 1
    fi

    # Load environment variables
    load_env_file "$ENV_FILE"

    # Run restart
    if rails_restart_application "$scale"; then
        send_restart_notification "$scale"
        exit 0
    else
        send_deploy_failure_notification "Restart failed"
        exit 1
    fi
}

# Function: Update Nginx upstream configuration for scaling
update_nginx_upstream() {
    local new_scale="$1"

    log_info "Updating Nginx upstream configuration for ${new_scale} containers..."

    # Generate new upstream servers list
    local UPSTREAM_SERVERS=""
    for i in $(seq 1 $new_scale); do
        local PORT=$((BASE_PORT + i - 1))
        UPSTREAM_SERVERS="${UPSTREAM_SERVERS}    server localhost:${PORT} max_fails=3 fail_timeout=30s;\n"
    done

    # Regenerate nginx config from template
    local nginx_config="/etc/nginx/sites-available/${APP_NAME}"
    local nginx_template="${APP_CONFIG_DIR}/nginx.conf.template"

    if [ ! -f "$nginx_template" ]; then
        log_error "Nginx template not found: ${nginx_template}"
        return 1
    fi

    # Create backup of current config
    sudo cp "$nginx_config" "${nginx_config}.backup"
    log_info "Created backup: ${nginx_config}.backup"

    # Generate new config from template
    cat "$nginx_template" | \
        sed "s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g" | \
        sed "s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|g" | \
        sed "s|{{DOMAIN}}|${DOMAIN}|g" | \
        sed "s|{{APP_NAME}}|${APP_NAME}|g" | \
        sudo tee "$nginx_config" > /dev/null

    # Test nginx configuration
    if sudo nginx -t 2>&1 | grep -q "successful"; then
        log_success "Nginx configuration updated successfully"
        sudo systemctl reload nginx
        log_success "Nginx reloaded with new upstream configuration"

        # Show what was updated
        log_info "Nginx now routing to ${new_scale} containers (ports ${BASE_PORT}-$((BASE_PORT + new_scale - 1)))"

        return 0
    else
        log_error "Nginx configuration test failed, restoring backup"
        sudo mv "${nginx_config}.backup" "$nginx_config"
        sudo systemctl reload nginx
        return 1
    fi
}

# Handle scale command
handle_scale() {
    local target_scale="$1"

    if [ -z "$target_scale" ]; then
        log_error "Scale parameter required"
        echo "Usage: $0 scale <number>"
        exit 1
    fi

    # Check if setup has been run
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Application not set up. Please run setup.sh first."
        exit 1
    fi

    # Load environment variables
    load_env_file "$ENV_FILE"

    local old_scale=$(get_container_count "$APP_NAME")

    # Run scaling
    if rails_scale_application "$target_scale"; then
        # Update nginx upstream configuration
        update_nginx_upstream "$target_scale"

        if [ $? -eq 0 ]; then
            log_success "Scaling completed: ${old_scale} → ${target_scale} containers"
            log_success "Nginx now routing to all ${target_scale} containers"
            send_scale_notification "$old_scale" "$target_scale"
            exit 0
        else
            log_warning "Containers scaled but nginx update failed"
            log_info "Please update nginx manually or run setup again"
            exit 1
        fi
    else
        send_deploy_failure_notification "Scaling failed"
        exit 1
    fi
}

# Handle stop command
handle_stop() {
    # Check if setup has been run
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Application not set up. Please run setup.sh first."
        exit 1
    fi

    # Load environment variables
    load_env_file "$ENV_FILE"

    local containers=($(get_running_containers "$APP_NAME"))
    local container_count=${#containers[@]}

    # Run stop
    if rails_stop_application; then
        send_stop_notification "$container_count"
        exit 0
    else
        log_error "Failed to stop application"
        exit 1
    fi
}

# Handle rollback command
handle_rollback() {
    local image_param="$1"

    # Check if setup has been run
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Application not set up. Please run setup.sh first."
        exit 1
    fi

    # Load environment variables
    load_env_file "$ENV_FILE"

    # If no parameter specified, list available backups
    if [ -z "$image_param" ]; then
        log_info "Available image backups for rollback:"
        list_image_backups "$IMAGE_BACKUP_DIR"
        echo ""
        log_info "Usage:"
        echo "  $0 rollback -1              # Rollback to previous version"
        echo "  $0 rollback -2              # Rollback 2 versions back"
        echo "  $0 rollback <image-file>    # Rollback to specific image file"
        exit 0
    fi

    local image_file=""

    # Check if parameter is a negative number (e.g., -1, -2)
    if [[ "$image_param" =~ ^-[0-9]+$ ]]; then
        local versions_back="${image_param#-}"  # Remove the minus sign
        log_info "Rolling back ${versions_back} version(s)..."

        # Get the Nth most recent backup (sorted by modification time)
        image_file=$(ls -t "${IMAGE_BACKUP_DIR}"/*.tar.gz 2>/dev/null | sed -n "$((versions_back + 1))p")

        if [ -z "$image_file" ]; then
            log_error "No backup found ${versions_back} version(s) back"
            log_info "Available backups:"
            ls -t "${IMAGE_BACKUP_DIR}"/*.tar.gz 2>/dev/null | nl -v 0 | sed 's/^/  /'
            exit 1
        fi

        log_info "Selected backup: $(basename $image_file)"
    else
        # Parameter is a file path
        image_file="$image_param"

        # Check if file exists
        if [ ! -f "$image_file" ]; then
            log_error "Image file not found: ${image_file}"
            exit 1
        fi
    fi

    # Load the image
    log_info "Rolling back to image: $(basename $image_file)"
    if load_docker_image "$image_file"; then
        # Restart with the loaded image (it will be tagged as latest)
        log_info "Restarting application with rolled-back image..."
        if rails_restart_application "$SCALE"; then
            log_success "Rollback completed successfully"
            send_mailgun_notification \
                "${APP_DISPLAY_NAME} - Rollback Completed" \
                "Application ${APP_NAME} has been rolled back.

Timestamp: $(date)
Host: $(hostname)
Image File: $(basename $image_file)
Rollback: ${image_param}

All containers have been restarted with the previous version." \
                "$MAILGUN_API_KEY" \
                "$MAILGUN_DOMAIN" \
                "$NOTIFICATION_EMAIL"
            exit 0
        else
            log_error "Failed to restart after rollback"
            exit 1
        fi
    else
        log_error "Failed to load image for rollback"
        exit 1
    fi
}

# Handle list-images command
handle_list_images() {
    # Check if setup has been run
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Application not set up. Please run setup.sh first."
        exit 1
    fi

    # Load environment variables
    load_env_file "$ENV_FILE"

    # List available image backups
    list_image_backups "$IMAGE_BACKUP_DIR"
    exit 0
}

# Handle ssl-setup command
handle_ssl_setup() {
    # Check if setup has been run
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Application not set up. Please run setup.sh first."
        exit 1
    fi

    # Load environment variables
    load_env_file "$ENV_FILE"

    log_info "Setting up SSL certificate for ${DOMAIN}..."

    # Check if certbot is installed
    if ! command -v certbot >/dev/null 2>&1; then
        log_info "Installing certbot..."
        sudo apt-get update -qq
        sudo apt-get install -y certbot python3-certbot-nginx
    fi

    # Get SSL certificate
    log_info "Obtaining SSL certificate from Let's Encrypt..."
    if sudo certbot --nginx \
        -d "$DOMAIN" \
        --email "${NOTIFICATION_EMAIL}" \
        --agree-tos \
        --non-interactive \
        --redirect; then
        log_success "SSL certificate obtained successfully"
        log_success "Site is now available at: https://${DOMAIN}"

        # Setup auto-renewal
        if ! sudo systemctl is-active --quiet certbot.timer; then
            sudo systemctl enable certbot.timer
            sudo systemctl start certbot.timer
            log_success "SSL auto-renewal enabled"
        fi

        send_mailgun_notification \
            "${APP_DISPLAY_NAME} - SSL Certificate Installed" \
            "SSL certificate has been installed successfully.

Domain: ${DOMAIN}
Certificate: Let's Encrypt
Auto-renewal: Enabled

The site is now available at: https://${DOMAIN}" \
            "$MAILGUN_API_KEY" \
            "$MAILGUN_DOMAIN" \
            "$NOTIFICATION_EMAIL"

        exit 0
    else
        log_error "Failed to obtain SSL certificate"
        log_info "Common issues:"
        echo "  - DNS not pointing to this server"
        echo "  - Port 80 not accessible"
        echo "  - Domain not reachable"
        exit 1
    fi
}

# Handle status command
handle_status() {
    log_info "Checking status of ${APP_DISPLAY_NAME} containers"
    echo ""

    # Get all containers (running and stopped)
    local all_containers=($(docker ps -a --filter "name=${APP_NAME}" --format "{{.Names}}" 2>/dev/null))

    if [ ${#all_containers[@]} -eq 0 ]; then
        log_warning "No containers found for ${APP_NAME}"
        echo ""
        log_info "Run './deploy.sh deploy' to start the application"
        exit 0
    fi

    # Print nice header
    echo "================================================================================"
    echo "                    APPLICATION STATUS: ${APP_DISPLAY_NAME}"
    echo "================================================================================"
    echo ""

    # Container status table
    printf "%-35s %-15s %-20s %-20s %-15s\n" "CONTAINER NAME" "STATUS" "PORTS" "STARTED" "UPTIME"
    echo "---------------------------------------------------------------------------------------------------"

    for container in "${all_containers[@]}"; do
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
        local ports=$(docker port "$container" 2>/dev/null | grep -oP '\d+:\d+' | head -1 || echo "-")
        local started_time=""
        local running_time=""

        if [ "$status" = "running" ]; then
            local started=$(docker inspect -f '{{.State.StartedAt}}' "$container" 2>/dev/null)
            local now_ts=$(date +%s)
            local started_ts=$(date -d "$started" +%s 2>/dev/null || echo "$now_ts")
            local seconds=$(( now_ts - started_ts ))

            # Format start time
            started_time=$(date -d "$started" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "-")

            # Format uptime
            if [ $seconds -lt 0 ] || [ $seconds -gt 31536000 ]; then
                running_time="?"
            elif [ $seconds -lt 60 ]; then
                running_time="${seconds}s"
            elif [ $seconds -lt 3600 ]; then
                local mins=$(($seconds / 60))
                running_time="${mins}m"
            elif [ $seconds -lt 86400 ]; then
                local hours=$(($seconds / 3600))
                local mins=$(($seconds % 3600 / 60))
                running_time="${hours}h ${mins}m"
            else
                local days=$(($seconds / 86400))
                local hours=$(($seconds % 86400 / 3600))
                running_time="${days}d ${hours}h"
            fi

            printf "%-35s \033[32m%-15s\033[0m %-20s %-20s %-15s\n" "$container" "$status" "$ports" "$started_time" "$running_time"
        else
            started_time=$(docker inspect -f '{{.State.StartedAt}}' "$container" 2>/dev/null | xargs -I {} date -d {} +"%Y-%m-%d %H:%M" 2>/dev/null || echo "-")
            printf "%-35s \033[31m%-15s\033[0m %-20s %-20s %-15s\n" "$container" "$status" "$ports" "$started_time" "-"
        fi
    done

    echo "---------------------------------------------------------------------------------------------------"
    echo ""

    # Summary
    local running_count=$(docker ps --filter "name=${APP_NAME}" --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')
    local total_count=${#all_containers[@]}

    echo "SUMMARY:"
    echo "  Running: ${running_count} / ${total_count} containers"
    echo "  Domain: https://${DOMAIN}"
    echo "  Health Check: https://${DOMAIN}${HEALTH_CHECK_PATH}"
    echo ""

    # Show web containers
    local web_containers=($(docker ps --filter "name=${APP_NAME}_web" --format "{{.Names}}" 2>/dev/null))
    if [ ${#web_containers[@]} -gt 0 ]; then
        echo "WEB CONTAINERS: ${#web_containers[@]}"
        for container in "${web_containers[@]}"; do
            local port=$(docker port "$container" 80 2>/dev/null | cut -d ':' -f2)
            echo "  - ${container} (port ${port})"
        done
        echo ""
    fi

    # Show worker containers if any
    local worker_containers=($(docker ps --filter "name=${APP_NAME}_worker" --format "{{.Names}}" 2>/dev/null))
    if [ ${#worker_containers[@]} -gt 0 ]; then
        echo "WORKER CONTAINERS: ${#worker_containers[@]}"
        for container in "${worker_containers[@]}"; do
            echo "  - ${container}"
        done
        echo ""
    fi

    # Show scheduler if any
    local scheduler="${APP_NAME}_scheduler"
    if docker ps --filter "name=${scheduler}" --format "{{.Names}}" 2>/dev/null | grep -q "^${scheduler}$"; then
        echo "SCHEDULER CONTAINER: 1"
        echo "  - ${scheduler}"
        echo ""
    fi

    # Quick commands
    echo "QUICK COMMANDS:"
    echo "  View logs:       docker logs ${APP_NAME}_web_1 -f"
    echo "  Rails console:   docker exec -it ${APP_NAME}_web_1 rails console"
    echo "  Restart:         ./deploy.sh restart"
    echo "  Stop:            ./deploy.sh stop"
    echo ""
    echo "================================================================================"

    exit 0
}

# Display help
show_help() {
    cat << EOF
Usage: $0 [command] [scale]

Commands:
  deploy              Pull code, build image, deploy with zero downtime (default)
  restart             Restart containers with current image
  scale <number>      Scale to specified number of instances
  stop                Stop all containers
  status              Show status of all containers in a nice table
  rollback [file]     Rollback to a previous image backup
  list-images         List available image backups for rollback
  ssl-setup           Setup SSL certificate with Let's Encrypt
  help                Show this help message

Examples:
  $0 deploy
  $0 deploy 3
  $0 restart
  $0 scale 4
  $0 stop
  $0 status                     # Show container status table
  $0 list-images
  $0 rollback -1                # Rollback to previous version
  $0 rollback -2                # Rollback 2 versions back
  $0 rollback <image-file>      # Rollback to specific file
  $0 ssl-setup

Configuration:
  App: ${APP_DISPLAY_NAME}
  Config: ${APP_CONFIG_DIR}/config.sh
  Domain: ${DOMAIN}
  Containers: ${DEFAULT_SCALE} web$([ "${WORKER_COUNT:-0}" -gt 0 ] && echo " + ${WORKER_COUNT} worker" || echo "")$([ "${SCHEDULER_ENABLED:-false}" = "true" ] && echo " + scheduler" || echo "")
  Port Range: ${BASE_PORT}-${PORT_RANGE_END}
  Image Backups: ${IMAGE_BACKUP_DIR}
  Max Backups: ${MAX_IMAGE_BACKUPS}
EOF
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Check if running as deploy user
    if [ "$(whoami)" != "$DEPLOY_USER" ]; then
        log_error "This script must be run as user: ${DEPLOY_USER}"
        log_info "Run: sudo -u ${DEPLOY_USER} bash ${SCRIPT_DIR}/deploy.sh $@"
        exit 1
    fi

    # Execute command
    case "$COMMAND" in
        deploy)
            handle_deploy "$SCALE"
            ;;
        restart)
            handle_restart "$SCALE"
            ;;
        scale)
            handle_scale "$SCALE"
            ;;
        stop)
            handle_stop
            ;;
        status)
            handle_status
            ;;
        rollback)
            handle_rollback "$SCALE"
            ;;
        list-images)
            handle_list_images
            ;;
        ssl-setup)
            handle_ssl_setup
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
