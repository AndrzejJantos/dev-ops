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

# Function: Setup SSL certificate
setup_ssl_certificate() {
    log_info "Setting up SSL certificate for ${DOMAIN}..."

    # Check if certbot is installed
    if ! command -v certbot >/dev/null 2>&1; then
        log_info "Installing certbot..."
        sudo apt-get update -qq
        sudo apt-get install -y certbot python3-certbot-nginx
    fi

    # Check if DNS is configured
    log_info "Checking DNS configuration for ${DOMAIN}..."
    local server_ip=$(curl -s ifconfig.me)
    local domain_ip=$(dig +short "$DOMAIN" | tail -1)

    if [ -z "$domain_ip" ]; then
        log_warning "DNS not configured for ${DOMAIN}"
        log_info "Please configure DNS A record: ${DOMAIN} -> ${server_ip}"
        log_info "You can setup SSL later by running: sudo certbot --nginx -d ${DOMAIN}"
        return 0
    fi

    if [ "$domain_ip" != "$server_ip" ]; then
        log_warning "DNS mismatch: ${DOMAIN} points to ${domain_ip}, but server IP is ${server_ip}"
        log_info "Please update DNS A record: ${DOMAIN} -> ${server_ip}"
        log_info "You can setup SSL later by running: sudo certbot --nginx -d ${DOMAIN}"
        return 0
    fi

    log_success "DNS correctly configured: ${DOMAIN} -> ${server_ip}"

    # Check if certificate already exists
    if sudo certbot certificates 2>/dev/null | grep -q "Certificate Name: ${DOMAIN}"; then
        log_info "SSL certificate already exists for ${DOMAIN}"
        return 0
    fi

    # Obtain SSL certificate
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
    else
        log_warning "Failed to obtain SSL certificate"
        log_info "You can try manually: sudo certbot --nginx -d ${DOMAIN}"
        return 0
    fi

    return 0
}

# Custom post-setup tasks
post_setup_hook() {
    log_info "Running post-setup tasks for ${APP_DISPLAY_NAME}..."

    # Generate Nginx configuration
    generate_nginx_config

    # Setup SSL certificate (optional, checks DNS first)
    setup_ssl_certificate

    # Setup automated cron jobs (backup & cleanup)
    setup_cron_jobs

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

    # Create symlink to nginx config in app directory for easy access
    local nginx_link="${APP_DIR}/nginx.conf"
    if [ ! -L "$nginx_link" ]; then
        ln -s "$NGINX_CONF" "$nginx_link"
        chown -h "${DEPLOY_USER}:${DEPLOY_USER}" "$nginx_link" 2>/dev/null || true
        log_success "Created symlink: ${nginx_link} -> ${NGINX_CONF}"
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

Directories:
  App Directory: ${APP_DIR}
  Repository: ${APP_DIR}/repo
  Backups: ${APP_DIR}/backups
  Logs: ${APP_DIR}/logs
  Docker Images: ${APP_DIR}/docker-images

Configuration Files:
  Environment: ${ENV_FILE}
  Nginx Config: ${NGINX_CONF}
  Nginx Symlink: ${APP_DIR}/nginx.conf -> ${NGINX_CONF}
  DevOps Config: ${APP_CONFIG_DIR}/config.sh

Database:
  Name: ${DB_NAME}
  Redis DB: ${REDIS_DB_NUMBER}

Network:
  Domain: ${DOMAIN}
  Base Port: ${BASE_PORT}
  Port Range: ${BASE_PORT}-${PORT_RANGE_END}
  Default Scale: ${DEFAULT_SCALE}

Automated Tasks:
  Database Backup:  Every 30 minutes
  Cleanup:          Daily at 2 AM
  Backup Location:  ${BACKUP_DIR}
  Retention:        ${BACKUP_RETENTION_DAYS} days

Useful Commands:
  Edit Nginx:       sudo vim ${APP_DIR}/nginx.conf
  Edit Env Vars:    vim ${ENV_FILE}
  Deploy:           ${APP_CONFIG_DIR}/deploy.sh deploy
  Rollback App:     ${APP_CONFIG_DIR}/deploy.sh rollback -1
  Restore DB:       ${APP_CONFIG_DIR}/restore.sh
  View Logs:        docker logs ${APP_NAME}_web_1 -f
  Rails Console:    docker exec -it ${APP_NAME}_web_1 rails console
  Manual Backup:    ${APP_DIR}/backup-db.sh
  View Backups:     ls -lh ${BACKUP_DIR}

Cron Jobs:
  Check status:     crontab -l
  Backup logs:      tail -f ${LOG_DIR}/backup.log
  Cleanup logs:     tail -f ${LOG_DIR}/cleanup.log
  Restore logs:     tail -f ${LOG_DIR}/restore.log

Setup completed: $(date)
EOF

    log_success "Deployment info saved to ${APP_DIR}/deployment-info.txt"
    return 0
}

# Function: Setup cron jobs for backup and cleanup
setup_cron_jobs() {
    log_info "Setting up automated cron jobs..."

    # Create database backup script
    local backup_script="${APP_DIR}/backup-db.sh"
    cat > "$backup_script" << EOF
#!/bin/bash
# Database backup script for ${APP_NAME}
# Auto-generated by setup - do not edit manually

# Source common utilities
source "${DEVOPS_DIR}/common/utils.sh"

# Load app config
source "${APP_CONFIG_DIR}/config.sh"

# Backup database
backup_database "${DB_NAME}" "${BACKUP_DIR}" >> "${LOG_DIR}/backup.log" 2>&1
EOF

    chmod +x "$backup_script"
    chown "${DEPLOY_USER}:${DEPLOY_USER}" "$backup_script"

    # Create cleanup script
    local cleanup_script="${APP_DIR}/cleanup.sh"
    cat > "$cleanup_script" << EOF
#!/bin/bash
# Daily cleanup script for ${APP_NAME}
# Auto-generated by setup - do not edit manually

# Source common utilities
source "${DEVOPS_DIR}/common/utils.sh"
source "${DEVOPS_DIR}/common/docker-utils.sh"

# Load app config
source "${APP_CONFIG_DIR}/config.sh"

# Cleanup old image backups (keep last ${MAX_IMAGE_BACKUPS})
cleanup_old_image_backups "${IMAGE_BACKUP_DIR}" "${MAX_IMAGE_BACKUPS}"

# Cleanup old database backups (older than ${BACKUP_RETENTION_DAYS} days)
if [ -d "${BACKUP_DIR}" ]; then
    find "${BACKUP_DIR}" -name "*.sql.gz" -mtime +${BACKUP_RETENTION_DAYS} -delete
    echo "[$(date)] Cleaned up database backups older than ${BACKUP_RETENTION_DAYS} days"
fi

# Cleanup old Docker images (keep last ${MAX_IMAGE_VERSIONS})
cleanup_old_images "${DOCKER_IMAGE_NAME}" "${MAX_IMAGE_VERSIONS}"

echo "[$(date)] Cleanup completed for ${APP_NAME}"
EOF

    chmod +x "$cleanup_script"
    chown "${DEPLOY_USER}:${DEPLOY_USER}" "$cleanup_script"

    # Prepare cron entries
    local backup_cron="*/30 * * * * ${backup_script}"
    local cleanup_cron="0 2 * * * ${cleanup_script} >> ${LOG_DIR}/cleanup.log 2>&1"

    # Get current crontab or empty
    local current_crontab=$(crontab -u "$DEPLOY_USER" -l 2>/dev/null || echo "")

    # Add backup cron if not exists
    if echo "$current_crontab" | grep -qF "$backup_script"; then
        log_info "Database backup cron job already exists"
    else
        current_crontab="${current_crontab}\n${backup_cron}"
        log_success "Database backup cron job added (runs every 30 minutes)"
    fi

    # Add cleanup cron if not exists
    if echo "$current_crontab" | grep -qF "$cleanup_script"; then
        log_info "Cleanup cron job already exists"
    else
        current_crontab="${current_crontab}\n${cleanup_cron}"
        log_success "Cleanup cron job added (runs daily at 2 AM)"
    fi

    # Update crontab
    echo -e "$current_crontab" | crontab -u "$DEPLOY_USER" -

    # Copy restore script to app directory
    if [ -f "${APP_CONFIG_DIR}/restore.sh" ]; then
        cp "${APP_CONFIG_DIR}/restore.sh" "${APP_DIR}/restore.sh"
        chmod +x "${APP_DIR}/restore.sh"
        chown "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}/restore.sh"
        log_success "Restore script installed: ${APP_DIR}/restore.sh"
    fi

    log_info "Backup script: ${backup_script}"
    log_info "Cleanup script: ${cleanup_script}"
    log_info "Restore script: ${APP_DIR}/restore.sh"
    log_info "Backup logs: ${LOG_DIR}/backup.log"
    log_info "Cleanup logs: ${LOG_DIR}/cleanup.log"

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
