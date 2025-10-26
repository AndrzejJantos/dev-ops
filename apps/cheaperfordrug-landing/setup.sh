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

# Example: Override Rails environment file creation to add custom variables
# Uncomment and modify if you need to customize the env file creation
# rails_create_env_file() {
#     # Call the original function first
#     source "${DEVOPS_DIR}/common/rails/setup.sh"
#
#     # Then add your customizations
#     log_info "Adding custom environment variables..."
#     cat >> "$ENV_FILE" << EOF
# # Custom variables for cheaperfordrug-landing
# CUSTOM_VAR=value
# EOF
#
#     return 0
# }

# ============================================================================
# POST-SETUP HOOKS
# ============================================================================

# Custom post-setup tasks
post_setup_hook() {
    log_info "Running post-setup tasks for ${APP_DISPLAY_NAME}..."

    # Generate Nginx configuration
    generate_nginx_config

    # Create deployment info file
    create_deployment_info

    # Send notification
    send_setup_notification

    return 0
}

# Function: Generate Nginx configuration
generate_nginx_config() {
    log_info "Creating Nginx configuration..."

    # Generate upstream servers list
    UPSTREAM_SERVERS=""
    for i in $(seq 1 $DEFAULT_SCALE); do
        PORT=$((BASE_PORT + i - 1))
        UPSTREAM_SERVERS="${UPSTREAM_SERVERS}    server localhost:${PORT} max_fails=3 fail_timeout=30s;\n"
    done

    # Process template
    cat "${APP_CONFIG_DIR}/nginx.conf.template" | \
        sed "s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g" | \
        sed "s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|g" | \
        sed "s|{{DOMAIN}}|${DOMAIN}|g" | \
        sed "s|{{APP_NAME}}|${APP_NAME}|g" | \
        sudo tee "$NGINX_CONF" > /dev/null

    # Enable site
    if [ ! -L "$NGINX_ENABLED" ]; then
        sudo ln -s "$NGINX_CONF" "$NGINX_ENABLED"
        log_success "Nginx site enabled"
    fi

    # Test Nginx configuration
    sudo nginx -t

    if [ $? -eq 0 ]; then
        log_success "Nginx configuration is valid"
        sudo systemctl reload nginx
        log_success "Nginx reloaded"
    else
        log_error "Nginx configuration test failed"
        return 1
    fi

    return 0
}

# Function: Create deployment info file
create_deployment_info() {
    cat > "${APP_DIR}/deployment-info.txt" << EOF
Application: ${APP_DISPLAY_NAME}
App Name: ${APP_NAME}
Repository: ${REPO_URL}
Branch: ${REPO_BRANCH}
Deploy User: ${DEPLOY_USER}
App Directory: ${APP_DIR}
Environment File: ${ENV_FILE}
Database: ${DB_NAME}
Redis DB: ${REDIS_DB_NUMBER}
Domain: ${DOMAIN}
Base Port: ${BASE_PORT}
Port Range: ${BASE_PORT}-${PORT_RANGE_END}
Default Scale: ${DEFAULT_SCALE}
Nginx Config: ${NGINX_CONF}
DevOps Config: ${APP_CONFIG_DIR}/config.sh

Setup completed: $(date)
EOF

    log_success "Deployment info saved to ${APP_DIR}/deployment-info.txt"
    return 0
}

# Function: Send setup notification
send_setup_notification() {
    send_mailgun_notification \
        "${APP_DISPLAY_NAME} - Initial Setup Completed" \
        "Application ${APP_NAME} has been set up successfully on $(hostname).

Repository: ${REPO_URL}
Domain: ${DOMAIN}
Database: ${DB_NAME}
Redis DB: ${REDIS_DB_NUMBER}

Next steps:
1. Edit ${ENV_FILE} and update credentials
2. Run deployment: ${SCRIPT_DIR}/deploy.sh deploy

Setup completed at: $(date)" \
        "$MAILGUN_API_KEY" \
        "$MAILGUN_DOMAIN" \
        "$NOTIFICATION_EMAIL"

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

    # Ensure Dockerfile exists in repo and matches template
    cd "$REPO_DIR"

    # Always update Dockerfile from template to ensure it's correct
    log_info "Updating Dockerfile from template..."

    # Copy Dockerfile template
    if [ -f "${DEVOPS_DIR}/common/rails/Dockerfile.template" ]; then
        cp "${DEVOPS_DIR}/common/rails/Dockerfile.template" Dockerfile
        log_success "Dockerfile updated from template"
    else
        log_error "Dockerfile template not found"
        exit 1
    fi

    # Copy .dockerignore template
    if [ -f "${DEVOPS_DIR}/common/rails/.dockerignore.template" ]; then
        cp "${DEVOPS_DIR}/common/rails/.dockerignore.template" .dockerignore
        log_success ".dockerignore updated from template"
    fi

    # Commit and push to app repo
    git add Dockerfile .dockerignore
    if git diff --staged --quiet; then
        log_info "Dockerfile already up to date"
    else
        git commit -m "Update production Dockerfile and .dockerignore

- Multi-stage build for optimized image
- Uses .env for asset precompilation
- Removes .env from final image
- Runs as non-root user
- Uses .bundle/vendor for gems

Generated by DevOps setup"

        git push origin "$REPO_BRANCH"
        log_success "Dockerfile committed and pushed"
    fi

    # Run Rails setup workflow
    # This includes: prerequisites check, database setup, env file creation,
    # native environment setup, asset precompilation, Docker build, and migrations
    rails_setup_workflow || exit 1

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
