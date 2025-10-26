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
        send_scale_notification "$old_scale" "$target_scale"
        exit 0
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
    local image_file="$1"

    # Check if setup has been run
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Application not set up. Please run setup.sh first."
        exit 1
    fi

    # Load environment variables
    load_env_file "$ENV_FILE"

    # If no image file specified, list available backups
    if [ -z "$image_file" ]; then
        log_info "Available image backups for rollback:"
        list_image_backups "$IMAGE_BACKUP_DIR"
        log_info "Usage: $0 rollback <image-file.tar.gz>"
        exit 0
    fi

    # Check if file exists
    if [ ! -f "$image_file" ]; then
        log_error "Image file not found: ${image_file}"
        exit 1
    fi

    # Load the image
    log_info "Rolling back to image: ${image_file}"
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
Image File: ${image_file}

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

# Display help
show_help() {
    cat << EOF
Usage: $0 [command] [scale]

Commands:
  deploy              Pull code, build image, deploy with zero downtime (default)
  restart             Restart containers with current image
  scale <number>      Scale to specified number of instances
  stop                Stop all containers
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
  $0 list-images
  $0 rollback ~/apps/${APP_NAME}/docker-images/${APP_NAME}_20250126_143022.tar.gz
  $0 ssl-setup

Configuration:
  App: ${APP_DISPLAY_NAME}
  Config: ${APP_CONFIG_DIR}/config.sh
  Domain: ${DOMAIN}
  Default Scale: ${DEFAULT_SCALE}
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
