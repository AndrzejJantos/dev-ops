#!/bin/bash

# Application-specific setup script for cheaperfordrug-landing
# Location: /home/andrzej/DevOps/apps/cheaperfordrug-landing/setup.sh
# Usage: ./setup.sh

set -euo pipefail

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG_DIR="$SCRIPT_DIR"
DEVOPS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load app configuration first
if [ ! -f "${APP_CONFIG_DIR}/config.sh" ]; then
    echo "Error: Configuration file not found: ${APP_CONFIG_DIR}/config.sh"
    exit 1
fi

source "${APP_CONFIG_DIR}/config.sh"

# Load common utilities
source "${DEVOPS_DIR}/common/utils.sh"
source "${DEVOPS_DIR}/common/docker-utils.sh"

# Load Rails-specific functions
source "${DEVOPS_DIR}/common/rails/setup.sh"
source "${DEVOPS_DIR}/common/rails/setup-helpers.sh"

# ============================================================================
# PRE-SETUP HOOKS
# ============================================================================
# Override or extend functions here if needed

# Example: Add custom pre-setup validation
pre_setup_hook() {
    log_info "Running pre-setup validations for ${APP_DISPLAY_NAME}..."

    # Add any app-specific checks here
    # Example: Check for required API keys, validate domain, etc.

    return 0
}

# ============================================================================
# POST-SETUP HOOKS
# ============================================================================

# Function: Send setup notification
send_setup_notification() {
    send_mailgun_notification \
        "${APP_DISPLAY_NAME} - Initial Setup Completed" \
        "Application ${APP_NAME} has been set up successfully on $(hostname).

Repository: ${REPO_URL}
Domain: ${DOMAIN}
Database: ${DB_NAME}
Redis DB: ${REDIS_DB_NUMBER}

Automated tasks:
- Database backup: Every 30 minutes
- Cleanup old backups: Daily at 2 AM
  * Image backups: Keep last ${MAX_IMAGE_BACKUPS} versions
  * Database backups: Delete after ${BACKUP_RETENTION_DAYS} days
  * Docker images: Keep last ${MAX_IMAGE_VERSIONS} versions

Backup locations:
- Database: ${BACKUP_DIR}
- Docker images: ${IMAGE_BACKUP_DIR}

Next steps:
1. Edit ${ENV_FILE} and update credentials
2. Run deployment: ${SCRIPT_DIR}/deploy.sh deploy

Setup completed at: $(date)" \
        "$MAILGUN_API_KEY" \
        "$MAILGUN_DOMAIN" \
        "$NOTIFICATION_EMAIL"

    return 0
}

# Custom post-setup tasks
post_setup_hook() {
    log_info "Running post-setup tasks for ${APP_DISPLAY_NAME}..."

    # Send notification (optional)
    send_setup_notification || log_warning "Failed to send setup notification"

    return 0
}

# ============================================================================
# MAIN SETUP EXECUTION
# ============================================================================

main() {
    log_info "Starting setup for ${APP_DISPLAY_NAME} (${APP_NAME})"

    # Check if running as deploy user
    if [ "$(whoami)" != "$DEPLOY_USER" ]; then
        log_error "This script must be run as user: ${DEPLOY_USER}"
        log_info "Run: sudo -u ${DEPLOY_USER} bash ${SCRIPT_DIR}/setup.sh"
        exit 1
    fi

    # Run pre-setup hook
    pre_setup_hook || exit 1

    # Create directory structure
    log_info "Creating directory structure..."
    ensure_directory "$APP_BASE_DIR" "$DEPLOY_USER"
    ensure_directory "$APP_DIR" "$DEPLOY_USER"
    ensure_directory "$BACKUP_DIR" "$DEPLOY_USER"
    ensure_directory "$LOG_DIR" "$DEPLOY_USER"
    ensure_directory "$IMAGE_BACKUP_DIR" "$DEPLOY_USER"

    # Clone or update repository
    if [ ! -d "$REPO_DIR" ]; then
        log_info "Cloning repository from ${REPO_URL}"
        cd "$APP_BASE_DIR"
        git clone "$REPO_URL" "${APP_NAME}/repo"
        cd "${APP_NAME}/repo"
        git checkout "$REPO_BRANCH"
        log_success "Repository cloned successfully"
    else
        log_info "Repository already exists at ${REPO_DIR}"
        cd "$REPO_DIR"
        git fetch origin "$REPO_BRANCH"
        git checkout "$REPO_BRANCH"
        git pull origin "$REPO_BRANCH"
        log_success "Repository updated"
    fi

    # Ensure Dockerfile exists in repo - copy from template if needed
    cd "$REPO_DIR"

    # Copy Dockerfile from template (don't commit - just use it)
    log_info "Copying Dockerfile from template..."

    if [ -f "${DEVOPS_DIR}/common/rails/Dockerfile.template" ]; then
        cp "${DEVOPS_DIR}/common/rails/Dockerfile.template" Dockerfile
        log_success "Dockerfile copied from template"
    else
        log_error "Dockerfile template not found"
        exit 1
    fi

    # Copy .dockerignore template
    if [ -f "${DEVOPS_DIR}/common/rails/.dockerignore.template" ]; then
        cp "${DEVOPS_DIR}/common/rails/.dockerignore.template" .dockerignore
        log_success ".dockerignore copied from template"
    fi

    # Add to .gitignore so Dockerfile isn't tracked in app repo
    if [ -f .gitignore ]; then
        if ! grep -q "^Dockerfile$" .gitignore; then
            echo "Dockerfile" >> .gitignore
            log_info "Added Dockerfile to .gitignore"
        fi
        if ! grep -q "^.dockerignore$" .gitignore; then
            echo ".dockerignore" >> .gitignore
            log_info "Added .dockerignore to .gitignore"
        fi
    fi

    log_success "Dockerfile managed by DevOps (not committed to app repo)"

    # Run Rails setup workflow
    # This includes: prerequisites check, database setup, env file creation,
    # native environment setup, asset precompilation, Docker build, and migrations
    rails_setup_workflow || exit 1

    # Generate Nginx configuration
    rails_generate_nginx_config || exit 1

    # Setup default catch-all server
    rails_setup_default_nginx_server || exit 1

    # Setup SSL certificate (optional, checks DNS first)
    rails_setup_ssl_certificate || exit 1

    # Setup automated cron jobs (backup & cleanup)
    rails_setup_cron_jobs || exit 1

    # Create deployment info file
    rails_create_deployment_info || exit 1

    # Run post-setup hook
    post_setup_hook || exit 1

    # Display next steps
    log_success "Setup completed successfully!"
    echo ""
    log_info "Next steps:"
    echo "  1. Edit the environment file and update credentials:"
    echo "     nano ${ENV_FILE}"
    echo "  2. Deploy the application:"
    echo "     ${SCRIPT_DIR}/deploy.sh deploy"
    echo ""
    log_info "Configuration file: ${APP_CONFIG_DIR}/config.sh"
    log_info "Deployment info: ${APP_DIR}/deployment-info.txt"
}

# Run main function
main "$@"
