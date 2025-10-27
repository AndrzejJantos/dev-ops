#!/bin/bash

# Rails Setup Helper Functions
# Location: /home/andrzej/DevOps/common/rails/setup-helpers.sh
# This file provides common setup functions for Rails applications

# This file should be sourced by app-specific setup.sh scripts AFTER:
# - common/utils.sh
# - common/docker-utils.sh
# - common/rails/setup.sh
# - app-specific config.sh

# ============================================================================
# NGINX CONFIGURATION
# ============================================================================

# Function: Generate Nginx configuration
# Uses perl for reliable multiline substitution
# Supports both single domain and multi-domain setups
rails_generate_nginx_config() {
    log_info "Generating Nginx configuration..."

    local nginx_template="${APP_CONFIG_DIR}/nginx.conf.template"
    local nginx_config="/etc/nginx/sites-available/${APP_NAME}"

    if [ ! -f "$nginx_template" ]; then
        log_error "Nginx template not found: ${nginx_template}"
        return 1
    fi

    # Generate upstream servers for default scale
    UPSTREAM_SERVERS=""
    for i in $(seq 1 $DEFAULT_SCALE); do
        PORT=$((BASE_PORT + i - 1))
        UPSTREAM_SERVERS="${UPSTREAM_SERVERS}    server localhost:${PORT} max_fails=3 fail_timeout=30s;
"
    done

    # Determine domain(s) for nginx config
    # If DOMAIN_PUBLIC exists, use it; otherwise use DOMAIN
    local PRIMARY_DOMAIN="${DOMAIN_PUBLIC:-$DOMAIN}"

    # Generate nginx config using perl for safer multiline substitution
    perl -pe "
        s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g;
        s|{{DOMAIN}}|${PRIMARY_DOMAIN}|g;
        s|{{APP_NAME}}|${APP_NAME}|g;
    " "$nginx_template" | \
    perl -pe "BEGIN{undef $/;} s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|gs" | \
    sudo tee "$nginx_config" > /dev/null

    if [ $? -ne 0 ]; then
        log_error "Failed to generate nginx configuration"
        return 1
    fi

    # Enable site
    sudo ln -sf "$nginx_config" "/etc/nginx/sites-enabled/${APP_NAME}"

    # Test and reload nginx
    if sudo nginx -t 2>&1 | grep -q "successful"; then
        sudo systemctl reload nginx
        log_success "Nginx configuration created and loaded"
    else
        log_error "Nginx configuration test failed"
        return 1
    fi

    return 0
}

# Function: Setup default catch-all server (security)
rails_setup_default_nginx_server() {
    log_info "Setting up default catch-all server..."

    local default_server_config="/etc/nginx/sites-available/000-default"

    if [ ! -f "$default_server_config" ]; then
        if [ -f "${DEVOPS_DIR}/common/nginx/default-server.conf" ]; then
            sudo cp "${DEVOPS_DIR}/common/nginx/default-server.conf" "$default_server_config"
            sudo ln -sf "$default_server_config" "/etc/nginx/sites-enabled/000-default"

            if sudo nginx -t 2>&1 | grep -q "successful"; then
                sudo systemctl reload nginx
                log_success "Default catch-all server configured (rejects unknown domains)"
            else
                log_error "Default server configuration test failed"
                return 1
            fi
        else
            log_warning "Default server template not found at ${DEVOPS_DIR}/common/nginx/default-server.conf"
        fi
    else
        log_info "Default catch-all server already configured"
    fi

    return 0
}

# ============================================================================
# SSL CERTIFICATE SETUP
# ============================================================================

# Function: Setup SSL certificate with IPv4 checking
# Supports both single domain and multi-domain (DOMAIN_PUBLIC + DOMAIN_INTERNAL)
rails_setup_ssl_certificate() {
    log_info "Setting up SSL certificates..."

    # Check if certbot is installed
    if ! command -v certbot >/dev/null 2>&1; then
        log_info "Installing certbot..."
        sudo apt-get update -qq
        sudo apt-get install -y certbot python3-certbot-nginx
    fi

    # Get IPv4 address explicitly
    log_info "Detecting server IPv4 address..."
    local server_ipv4=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org)

    if [ -z "$server_ipv4" ]; then
        log_error "Failed to detect server IP address"
        return 1
    fi

    log_info "Server IPv4: ${server_ipv4}"

    # Determine which domains to check
    local domains_to_check=()
    if [ -n "${DOMAIN_PUBLIC}" ] && [ -n "${DOMAIN_INTERNAL}" ]; then
        # API with two domains
        domains_to_check=("${DOMAIN_PUBLIC}" "${DOMAIN_INTERNAL}")
        log_info "Checking DNS for API domains: ${DOMAIN_PUBLIC}, ${DOMAIN_INTERNAL}"
    else
        # Single domain
        domains_to_check=("${DOMAIN}")
        log_info "Checking DNS for domain: ${DOMAIN}"
    fi

    # Check DNS configuration for all domains
    local dns_ok=true
    for domain in "${domains_to_check[@]}"; do
        local domain_ip=$(dig +short "$domain" A | tail -1)

        if [ -z "$domain_ip" ]; then
            log_warning "DNS not configured for ${domain}"
            log_info "Please configure DNS A record: ${domain} -> ${server_ipv4}"
            dns_ok=false
        elif [ "$domain_ip" != "$server_ipv4" ]; then
            log_warning "DNS mismatch for ${domain}: points to ${domain_ip}, but server IPv4 is ${server_ipv4}"
            dns_ok=false
        else
            log_success "DNS correctly configured: ${domain} -> ${server_ipv4}"
        fi
    done

    # Try to obtain SSL certificates if DNS is configured
    if [ "$dns_ok" = true ]; then
        log_info "DNS configured correctly. Obtaining SSL certificates..."

        # Check if certificate already exists for primary domain
        local primary_cert_domain="${DOMAIN_PUBLIC:-$DOMAIN}"
        if sudo certbot certificates 2>/dev/null | grep -q "Certificate Name: ${primary_cert_domain}"; then
            log_info "SSL certificate already exists for ${primary_cert_domain}"
        else
            # Build certbot command with domain arguments
            local certbot_cmd="sudo certbot --nginx"
            for domain in "${domains_to_check[@]}"; do
                certbot_cmd="${certbot_cmd} -d ${domain}"
            done
            certbot_cmd="${certbot_cmd} --non-interactive --agree-tos --redirect"

            # Obtain certificate
            if ${certbot_cmd} 2>/dev/null; then
                if [ "${#domains_to_check[@]}" -gt 1 ]; then
                    log_success "SSL certificates obtained successfully for all domains"
                else
                    log_success "SSL certificate obtained successfully for ${DOMAIN}"
                fi

                # Setup auto-renewal
                if ! sudo systemctl is-active --quiet certbot.timer; then
                    sudo systemctl enable certbot.timer
                    sudo systemctl start certbot.timer
                    log_success "SSL auto-renewal enabled"
                fi
            else
                log_warning "Failed to obtain SSL certificates automatically"
                log_info "You can setup SSL later by running:"
                echo "  sudo certbot --nginx $(printf -- "-d %s " "${domains_to_check[@]}")"
            fi
        fi
    else
        log_warning "DNS not fully configured. Skipping SSL setup."
        log_info "After DNS is configured, run:"
        echo "  sudo certbot --nginx $(printf -- "-d %s " "${domains_to_check[@]}")"
    fi

    return 0
}

# ============================================================================
# CRON JOBS FOR BACKUP AND CLEANUP
# ============================================================================

# Function: Setup automated backup and cleanup cron jobs
rails_setup_cron_jobs() {
    log_info "Setting up automated cron jobs..."

    # Determine if this app has a database (check BACKUP_DIR config)
    local has_database=true
    if [ "${WORKER_COUNT:-0}" -eq 0 ] && [ "${SCHEDULER_ENABLED:-false}" = "false" ]; then
        # Simple apps might not need database backups
        if [ -n "${SKIP_DB_BACKUP}" ] && [ "${SKIP_DB_BACKUP}" = "true" ]; then
            has_database=false
        fi
    fi

    # Create backup script (if app has database)
    if [ "$has_database" = true ]; then
        local backup_script="${APP_DIR}/backup.sh"
        cat > "$backup_script" << 'BACKUP_SCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../../DevOps" && pwd)"
source "$DEVOPS_DIR/common/utils.sh"
APP_CONFIG_DIR="$(cd "$SCRIPT_DIR/.."; pwd)/APP_NAME_PLACEHOLDER"
source "$APP_CONFIG_DIR/config.sh"

backup_database "$DB_NAME" "$BACKUP_DIR"
cleanup_old_backups "$BACKUP_DIR" "${BACKUP_RETENTION_DAYS:-30}"
BACKUP_SCRIPT

        # Replace placeholder with actual app name
        sed -i "s|APP_NAME_PLACEHOLDER|${APP_NAME}|g" "$backup_script"
        chmod +x "$backup_script"

        # Setup cron job for backups (every 30 minutes)
        (crontab -l 2>/dev/null | grep -v "$backup_script"; echo "*/30 * * * * $backup_script >> $LOG_DIR/backup.log 2>&1") | crontab -

        log_success "Automated backups configured (every 30 minutes)"
    else
        log_info "Skipping database backup setup (not needed for this app)"
    fi

    # Create restore script (if app has database)
    if [ "$has_database" = true ]; then
        local restore_script="${APP_DIR}/restore.sh"
        cat > "$restore_script" << 'RESTORE_SCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../../DevOps" && pwd)"
source "$DEVOPS_DIR/common/utils.sh"
APP_CONFIG_DIR="$(cd "$SCRIPT_DIR/.."; pwd)/APP_NAME_PLACEHOLDER"
source "$APP_CONFIG_DIR/config.sh"

if [ -z "$1" ]; then
    list_backups "$BACKUP_DIR"
    echo ""
    echo "Usage: $0 <backup_file>"
    exit 1
fi

restore_database "$DB_NAME" "$1"
RESTORE_SCRIPT

        # Replace placeholder with actual app name
        sed -i "s|APP_NAME_PLACEHOLDER|${APP_NAME}|g" "$restore_script"
        chmod +x "$restore_script"
    fi

    # Create cleanup script (all apps need this for Docker images)
    local cleanup_script="${APP_DIR}/cleanup.sh"
    cat > "$cleanup_script" << 'CLEANUP_SCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../../DevOps" && pwd)"
source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/docker-utils.sh"
APP_CONFIG_DIR="$(cd "$SCRIPT_DIR/.."; pwd)/APP_NAME_PLACEHOLDER"
source "$APP_CONFIG_DIR/config.sh"

# Cleanup old image backups (keep last ${MAX_IMAGE_BACKUPS})
if [ -d "$IMAGE_BACKUP_DIR" ]; then
    cleanup_old_image_backups "$IMAGE_BACKUP_DIR" "${MAX_IMAGE_BACKUPS:-20}"
fi

# Cleanup old database backups (older than ${BACKUP_RETENTION_DAYS} days)
if [ -d "$BACKUP_DIR" ]; then
    cleanup_old_backups "$BACKUP_DIR" "${BACKUP_RETENTION_DAYS:-30}"
fi

# Cleanup old Docker images (keep last ${MAX_IMAGE_VERSIONS})
cleanup_old_images "$DOCKER_IMAGE_NAME" "${MAX_IMAGE_VERSIONS:-20}"

echo "[$(date)] Cleanup completed for ${APP_NAME}"
CLEANUP_SCRIPT

    # Replace placeholder with actual app name
    sed -i "s|APP_NAME_PLACEHOLDER|${APP_NAME}|g" "$cleanup_script"
    chmod +x "$cleanup_script"

    # Setup cron job for cleanup (daily at 2 AM)
    (crontab -l 2>/dev/null | grep -v "$cleanup_script"; echo "0 2 * * * $cleanup_script >> $LOG_DIR/cleanup.log 2>&1") | crontab -

    log_success "Automated cleanup configured (daily at 2 AM)"

    return 0
}

# ============================================================================
# DEPLOYMENT INFO
# ============================================================================

# Function: Create deployment info file
rails_create_deployment_info() {
    log_info "Creating deployment info file..."

    local info_file="${APP_DIR}/deployment-info.txt"

    # Determine domain display based on configuration
    local domain_display
    if [ -n "${DOMAIN_PUBLIC}" ] && [ -n "${DOMAIN_INTERNAL}" ]; then
        domain_display="Public: ${DOMAIN_PUBLIC}, Internal: ${DOMAIN_INTERNAL}"
    else
        domain_display="${DOMAIN}"
    fi

    # Calculate port range
    local port_range_end=$((BASE_PORT + DEFAULT_SCALE - 1))

    cat > "$info_file" << INFO
${APP_DISPLAY_NAME} Deployment Information
==========================================

Application: ${APP_DISPLAY_NAME}
Domain: ${domain_display}
Repository: ${REPO_URL}

Container Architecture:
- Web containers: ${DEFAULT_SCALE} (ports ${BASE_PORT}-${port_range_end})
- Worker containers: ${WORKER_COUNT}
- Scheduler: ${SCHEDULER_ENABLED}

Directories:
- Application: ${APP_DIR}
- Repository: ${REPO_DIR}
- Backups: ${BACKUP_DIR}
- Logs: ${LOG_DIR}
- Docker Images: ${IMAGE_BACKUP_DIR}

Database:
- Name: ${DB_NAME}
- User: ${DB_USER}

Files:
- Environment: ${ENV_FILE}
- Deploy script: ${APP_CONFIG_DIR}/deploy.sh
- Backup script: ${APP_DIR}/backup.sh
- Restore script: ${APP_DIR}/restore.sh

Next Steps:
===========

1. Review and update environment variables:
   nano ${ENV_FILE}

2. Configure your application secrets:
   - SMTP credentials for emails
   - External API keys
   - JWT secret (already generated)
   - Database password (already generated)

3. Deploy the application:
   cd ${APP_CONFIG_DIR}
   ./deploy.sh deploy

4. Check status:
   ./deploy.sh status

5. View logs:
   ./deploy.sh logs
   ./deploy.sh logs worker_1
   ./deploy.sh logs scheduler

6. Access Rails console:
   ./deploy.sh console

Management Commands:
====================
./deploy.sh deploy          - Deploy latest code
./deploy.sh restart         - Restart all containers
./deploy.sh stop            - Stop all containers
./deploy.sh scale <N>       - Scale web containers
./deploy.sh status          - Show container status
./deploy.sh console         - Rails console
./deploy.sh logs [name]     - View logs
./deploy.sh ssl-setup       - Setup SSL certificates

Restore database backup:
${APP_DIR}/restore.sh <backup_file>

INFO

    log_success "Deployment info saved to ${info_file}"
    return 0
}

# ============================================================================
# MAIN SETUP WORKFLOW
# ============================================================================

# Function: Rails common setup workflow
# This orchestrates all common setup tasks and can be called from app-specific setup.sh
# App-specific setup.sh should:
# 1. Source this file
# 2. Define pre_setup_hook and post_setup_hook
# 3. Call rails_common_setup_workflow
rails_common_setup_workflow() {
    log_info "Starting Rails common setup workflow for ${APP_DISPLAY_NAME}"

    # Create directory structure
    log_info "Creating directory structure..."
    mkdir -p "$APP_DIR"
    mkdir -p "$REPO_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$IMAGE_BACKUP_DIR"

    # Clone repository
    if [ ! -d "$REPO_DIR/.git" ]; then
        log_info "Cloning repository from $REPO_URL..."
        git clone "$REPO_URL" "$REPO_DIR"
    else
        log_info "Repository already cloned"
    fi

    # Copy Dockerfile and .dockerignore from DevOps template
    log_info "Copying Docker files from template..."
    cp "${DEVOPS_DIR}/common/rails/Dockerfile.template" "$REPO_DIR/Dockerfile"
    cp "${DEVOPS_DIR}/common/rails/.dockerignore.template" "$REPO_DIR/.dockerignore"

    # Run Rails setup workflow (from common/rails/setup.sh)
    rails_setup_workflow || return 1

    # Setup nginx configuration
    rails_generate_nginx_config || return 1

    # Setup default catch-all server
    rails_setup_default_nginx_server || return 1

    # Setup automated backups and cleanup
    rails_setup_cron_jobs || return 1

    # Setup SSL certificate (automatic if DNS is configured)
    rails_setup_ssl_certificate || return 1

    # Create deployment info file
    rails_create_deployment_info || return 1

    log_success "Rails common setup workflow completed"
    return 0
}
