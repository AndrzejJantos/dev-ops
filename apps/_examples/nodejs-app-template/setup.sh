#!/bin/bash

# Application-specific setup script for Node.js application
# Location: /home/andrzej/DevOps/apps/<your-nodejs-app>/setup.sh
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

# Load Node.js-specific functions
source "${DEVOPS_DIR}/common/nodejs/setup.sh"

# ============================================================================
# CUSTOMIZATION SECTION
# ============================================================================
# Override or extend functions here if needed

# Example: Add custom pre-setup validation
pre_setup_hook() {
    log_info "Running pre-setup validations for ${APP_DISPLAY_NAME}..."

    # Add any app-specific checks here
    # Example: Check for required Node.js version
    REQUIRED_NODE_VERSION="18"
    CURRENT_NODE_VERSION=$(node -v | grep -oP '\d+' | head -1)

    if [ "$CURRENT_NODE_VERSION" -lt "$REQUIRED_NODE_VERSION" ]; then
        log_error "Node.js version $REQUIRED_NODE_VERSION or higher required"
        log_error "Current version: $CURRENT_NODE_VERSION"
        return 1
    fi

    log_success "Node.js version check passed"
    return 0
}

# Example: Override build function for custom build process
# Uncomment and customize if needed
# nodejs_build_application() {
#     log_info "Custom build process..."
#     cd "$REPO_DIR"
#
#     # Install dependencies
#     npm ci
#
#     # Run custom build steps
#     npm run lint
#     npm run test
#     npm run build
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

    # Create Nginx config (or use template if exists)
    if [ -f "${APP_CONFIG_DIR}/nginx.conf.template" ]; then
        cat "${APP_CONFIG_DIR}/nginx.conf.template" | \
            sed "s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g" | \
            sed "s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|g" | \
            sed "s|{{DOMAIN}}|${DOMAIN}|g" | \
            sed "s|{{APP_NAME}}|${APP_NAME}|g" | \
            sudo tee "$NGINX_CONF" > /dev/null
    else
        # Generate basic config if template doesn't exist
        sudo tee "$NGINX_CONF" > /dev/null << EOF
upstream ${NGINX_UPSTREAM_NAME} {
    least_conn;
$(echo -e "$UPSTREAM_SERVERS")
}

server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://${NGINX_UPSTREAM_NAME};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    fi

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
Framework: Node.js
Repository: ${REPO_URL}
Branch: ${REPO_BRANCH}
Deploy User: ${DEPLOY_USER}
App Directory: ${APP_DIR}
Environment File: ${ENV_FILE}
Domain: ${DOMAIN}
Base Port: ${BASE_PORT}
Port Range: ${BASE_PORT}-${PORT_RANGE_END}
Default Scale: ${DEFAULT_SCALE}
Nginx Config: ${NGINX_CONF}
DevOps Config: ${APP_CONFIG_DIR}/config.sh

Features:
- PostgreSQL: ${NEEDS_POSTGRES:-false}
- Redis: ${NEEDS_REDIS:-false}
- Mailgun: ${NEEDS_MAILGUN:-false}
- Migrations: ${NEEDS_MIGRATIONS:-false}

Setup completed: $(date)
EOF

    log_success "Deployment info saved to ${APP_DIR}/deployment-info.txt"
    return 0
}

# Function: Send setup notification
send_setup_notification() {
    if [ "${NEEDS_MAILGUN:-false}" != "true" ]; then
        log_info "Mailgun not configured, skipping notification"
        return 0
    fi

    send_mailgun_notification \
        "${APP_DISPLAY_NAME} - Initial Setup Completed" \
        "Node.js application ${APP_NAME} has been set up successfully on $(hostname).

Repository: ${REPO_URL}
Domain: ${DOMAIN}
$(if [ "${NEEDS_POSTGRES:-false}" = "true" ]; then echo "Database: ${DB_NAME}"; fi)
$(if [ "${NEEDS_REDIS:-false}" = "true" ]; then echo "Redis DB: ${REDIS_DB_NUMBER}"; fi)

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

    # Run Node.js setup workflow
    # This includes: prerequisites check, database setup (if needed),
    # env file creation, npm install, build, Docker build, and migrations
    nodejs_setup_workflow || exit 1

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
