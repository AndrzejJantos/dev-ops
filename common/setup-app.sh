#!/bin/bash

# Generic Application Setup Script
# Location: /home/andrzej/DevOps/common/setup-app.sh
# This script handles initial setup for any application type using composition
#
# Usage:
#   1. Source this script from your app's setup.sh
#   2. Call setup_application() function
#
# Requirements:
#   - config.sh must be sourced first
#   - APP_TYPE must be set in config.sh (either "nextjs" or "rails")

set -e

# ==============================================================================
# GENERIC SETUP WORKFLOW
# ==============================================================================

# Function: Main setup workflow that works for any app type
setup_application() {
    log_info "Starting setup for ${APP_DISPLAY_NAME}"
    log_info "Application Type: ${APP_TYPE}"
    log_info "Domain: ${DOMAIN}"

    # Validate required variables
    if [ -z "$APP_TYPE" ]; then
        log_error "APP_TYPE not set in config.sh. Must be 'nextjs' or 'rails'"
        return 1
    fi

    if [ -z "$APP_NAME" ]; then
        log_error "APP_NAME not set in config.sh"
        return 1
    fi

    if [ -z "$DOMAIN" ]; then
        log_error "DOMAIN not set in config.sh"
        return 1
    fi

    # Load app-type specific module
    local app_type_module="$DEVOPS_DIR/common/app-types/${APP_TYPE}.sh"
    if [ ! -f "$app_type_module" ]; then
        log_error "App type module not found: ${app_type_module}"
        log_error "Supported types: nextjs, rails"
        return 1
    fi

    log_info "Loading ${APP_TYPE} module..."
    source "$app_type_module"

    # Step 1: Create directory structure
    setup_directories

    # Step 2: Clone repository
    setup_repository

    # Step 3: Check prerequisites (app-type specific)
    ${APP_TYPE}_check_prerequisites || return 1

    # Step 4: Setup database (if needed - app-type specific)
    ${APP_TYPE}_setup_database || return 1

    # Step 5: Create environment file (app-type specific)
    ${APP_TYPE}_create_env_file || return 1

    # Step 6: Setup app-specific requirements (app-type specific)
    ${APP_TYPE}_setup_requirements || return 1

    # Step 7: Setup nginx configuration
    setup_nginx

    # Step 8: Setup default catch-all server (security)
    setup_default_server

    # Step 9: Setup automated cleanup
    setup_cleanup

    # Step 10: Setup SSL certificate
    setup_ssl

    # Step 11: Create deployment info file
    create_deployment_info

    log_success "Setup completed successfully!"
    echo ""
    cat "$APP_DIR/deployment-info.txt"

    return 0
}

# ==============================================================================
# SETUP STEPS (Generic - work for all app types)
# ==============================================================================

# Step 1: Create directory structure
setup_directories() {
    log_info "Creating directory structure..."
    mkdir -p "$APP_DIR"
    mkdir -p "$REPO_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$IMAGE_BACKUP_DIR"

    # Create backup directory for Rails apps
    if [ "$APP_TYPE" = "rails" ]; then
        mkdir -p "$BACKUP_DIR"
    fi

    # Create convenience symlink from deployed app to config directory
    if [ ! -L "$APP_DIR/config" ]; then
        ln -sf "$DEVOPS_DIR/apps/$APP_NAME" "$APP_DIR/config"
        log_info "Created symlink: $APP_DIR/config -> $DEVOPS_DIR/apps/$APP_NAME"
    fi

    log_success "Directory structure created"
}

# Step 2: Clone repository
setup_repository() {
    if [ ! -d "$REPO_DIR/.git" ]; then
        log_info "Cloning repository from $REPO_URL..."
        git clone "$REPO_URL" "$REPO_DIR"
        log_success "Repository cloned"
    else
        log_info "Repository already cloned"
    fi

    # Checkout correct branch
    cd "$REPO_DIR"
    git checkout "$REPO_BRANCH"
    log_info "Using branch: $REPO_BRANCH"
}

# Step 7: Setup nginx configuration
setup_nginx() {
    log_info "Setting up Nginx configuration..."

    local nginx_template="$SCRIPT_DIR/nginx.conf.template"
    local nginx_config="/etc/nginx/sites-available/$APP_NAME"

    # Check if nginx template exists
    if [ ! -f "$nginx_template" ]; then
        log_error "Nginx template not found: ${nginx_template}"
        log_error "Please create nginx.conf.template in your app directory"
        return 1
    fi

    # Check for domain conflicts in existing nginx configs
    log_info "Checking for domain conflicts in nginx configurations..."
    conflicting_configs=()
    for config in /etc/nginx/sites-enabled/*; do
        if [ -f "$config" ] && [ "$(basename $config)" != "${APP_NAME}" ]; then
            if sudo grep -q "server_name.*${DOMAIN}" "$config" 2>/dev/null; then
                conflicting_configs+=("$(basename $config)")
            fi
        fi
    done

    if [ ${#conflicting_configs[@]} -gt 0 ]; then
        log_error "Domain conflict detected!"
        log_error "The following nginx configs already claim ${DOMAIN}:"
        for config in "${conflicting_configs[@]}"; do
            echo "  - $config"
        done
        echo ""
        log_error "Please remove ${DOMAIN} from these configs before continuing."
        return 1
    fi

    log_success "No domain conflicts found"

    # Generate upstream servers for default scale
    UPSTREAM_SERVERS=""
    for i in $(seq 1 $DEFAULT_SCALE); do
        PORT=$((BASE_PORT + i - 1))
        UPSTREAM_SERVERS="${UPSTREAM_SERVERS}    server localhost:${PORT} max_fails=3 fail_timeout=30s;
"
    done

    # Generate nginx config using perl for safer multiline substitution
    perl -pe "
        s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g;
        s|{{DOMAIN}}|${DOMAIN}|g;
        s|{{APP_NAME}}|${APP_NAME}|g;
    " "$nginx_template" | \
    perl -pe "BEGIN{undef $/;} s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|gs" | \
    sudo tee "$nginx_config" > /dev/null

    # Test nginx configuration (but don't fail if SSL certificates don't exist yet)
    log_info "Testing nginx configuration..."
    nginx_test_output=$(sudo nginx -t 2>&1)

    if echo "$nginx_test_output" | grep -q "successful"; then
        # Config is good, enable it
        sudo ln -sf "$nginx_config" "/etc/nginx/sites-enabled/$APP_NAME"
        sudo systemctl reload nginx
        log_success "Nginx configuration created and loaded"
    elif echo "$nginx_test_output" | grep -q "cannot load certificate"; then
        # SSL certificates don't exist yet, this is expected during initial setup
        log_warning "Nginx config references SSL certificates that don't exist yet"
        log_info "SSL certificates will be created in the next step"
        log_info "Nginx will be enabled after SSL setup completes"
        # Don't enable the site yet, will be done after SSL setup
    else
        # Some other nginx error
        log_error "Nginx configuration test failed"
        echo "$nginx_test_output"
        return 1
    fi

    return 0
}

# Step 8: Setup default catch-all server (security)
setup_default_server() {
    log_info "Setting up default catch-all server..."
    local default_server_config="/etc/nginx/sites-available/000-default"

    if [ ! -f "$default_server_config" ]; then
        if [ -f "$DEVOPS_DIR/common/nginx/default-server.conf" ]; then
            sudo cp "$DEVOPS_DIR/common/nginx/default-server.conf" "$default_server_config"
            sudo ln -sf "$default_server_config" "/etc/nginx/sites-enabled/000-default"

            if sudo nginx -t 2>&1 | grep -q "successful"; then
                sudo systemctl reload nginx
                log_success "Default catch-all server configured (rejects unknown domains)"
            else
                log_error "Default server configuration test failed"
                return 1
            fi
        else
            log_warning "Default server template not found, skipping"
        fi
    else
        log_info "Default catch-all server already configured"
    fi

    return 0
}

# Step 9: Setup automated cleanup
setup_cleanup() {
    log_info "Setting up automated cleanup..."

    # Create cleanup script
    cat > "$APP_DIR/cleanup.sh" << 'CLEANUP_SCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="$(basename "$(dirname "$SCRIPT_DIR")")"
DEVOPS_DIR="$HOME/DevOps"

if [ ! -d "$DEVOPS_DIR" ]; then
    echo "[$(date)] ERROR: DevOps directory not found: $DEVOPS_DIR"
    exit 1
fi

source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/docker-utils.sh"

# Find config file
CONFIG_FILE=""
for config_location in "$DEVOPS_DIR/apps/$APP_NAME/config.sh" "$SCRIPT_DIR/../config.sh"; do
    if [ -f "$config_location" ]; then
        CONFIG_FILE="$config_location"
        break
    fi
done

if [ -z "$CONFIG_FILE" ]; then
    echo "[$(date)] ERROR: Could not find config.sh for $APP_NAME"
    exit 1
fi

source "$CONFIG_FILE"

# Cleanup old image backups (keep last N)
if [ -d "$IMAGE_BACKUP_DIR" ]; then
    cleanup_old_image_backups "$IMAGE_BACKUP_DIR" "${MAX_IMAGE_BACKUPS:-20}"
fi

# Cleanup old Docker images (keep last N)
cleanup_old_images "$DOCKER_IMAGE_NAME" "${MAX_IMAGE_VERSIONS:-20}"

# Cleanup database backups (Rails only)
if [ "$APP_TYPE" = "rails" ] && [ -d "$BACKUP_DIR" ]; then
    cleanup_old_backups "$BACKUP_DIR" "${BACKUP_RETENTION_DAYS:-30}"
fi

echo "[$(date)] Cleanup completed for ${APP_NAME}"
CLEANUP_SCRIPT

    chmod +x "$APP_DIR/cleanup.sh"

    # Setup cron job for cleanup (daily at 2 AM)
    (crontab -l 2>/dev/null | grep -v "$APP_DIR/cleanup.sh"; echo "0 2 * * * $APP_DIR/cleanup.sh >> $LOG_DIR/cleanup.log 2>&1") | crontab -

    log_success "Automated cleanup configured (daily at 2 AM)"
    return 0
}

# Step 10: Setup SSL certificate
setup_ssl() {
    log_info "Setting up SSL certificate..."

    # Check if certbot is installed
    if ! command -v certbot >/dev/null 2>&1; then
        log_info "Installing certbot..."
        sudo apt-get update -qq
        sudo apt-get install -y certbot python3-certbot-nginx
    fi

    # Build domain list for certbot
    local cert_domains="-d $DOMAIN"
    local all_domains="$DOMAIN"

    # Add www subdomain for non-API domains
    if [[ ! "$DOMAIN" =~ ^api ]]; then
        cert_domains="$cert_domains -d www.$DOMAIN"
    fi

    # Check if additional domains are defined (e.g., DOMAIN_INTERNAL)
    if [ -n "${DOMAIN_INTERNAL:-}" ]; then
        cert_domains="$cert_domains -d $DOMAIN_INTERNAL"
        all_domains="$all_domains, $DOMAIN_INTERNAL"
        log_info "Additional domain detected: ${DOMAIN_INTERNAL}"
    fi

    # Check DNS configuration for all domains
    log_info "Checking DNS configuration..."
    server_ipv4=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org)

    local dns_ok=true
    for domain in $DOMAIN ${DOMAIN_INTERNAL:-}; do
        domain_ip=$(dig +short "$domain" A | tail -1)
        echo "  ${domain}: ${domain_ip:-NOT CONFIGURED}"

        if [ -z "$domain_ip" ]; then
            log_warning "DNS not configured for ${domain}"
            dns_ok=false
        elif [ "$domain_ip" != "$server_ipv4" ]; then
            log_warning "DNS mismatch for ${domain}: points to ${domain_ip}, should be ${server_ipv4}"
            dns_ok=false
        fi
    done

    echo "  Server IP: ${server_ipv4}"

    if [ "$dns_ok" = false ]; then
        echo ""
        log_error "DNS not configured correctly. Please configure:"
        for domain in $DOMAIN ${DOMAIN_INTERNAL:-}; do
            echo "  ${domain}     A    ${server_ipv4}"
        done
        echo ""
        log_info "After DNS is configured, run: sudo certbot --nginx $cert_domains"
        return 1
    else
        log_success "DNS correctly configured for all domains"

        # Check if certificate already exists
        if sudo certbot certificates 2>/dev/null | grep -q "Certificate Name: ${DOMAIN}"; then
            log_success "SSL certificate already exists for ${DOMAIN}"
            expiry=$(sudo certbot certificates 2>/dev/null | grep -A 10 "Certificate Name: ${DOMAIN}" | grep "Expiry Date" | cut -d: -f2- | xargs)
            log_info "Certificate expires: ${expiry}"
        else
            # Try to get email from existing certbot registration
            existing_email=$(sudo certbot show_account 2>/dev/null | grep -oP 'Email contact: \K.*' || echo "")

            log_info "Obtaining SSL certificates for: ${all_domains}"

            # Attempt automatic certificate setup
            if [ -n "$existing_email" ]; then
                log_info "Using existing certbot account: ${existing_email}"
                if sudo certbot --nginx \
                    $cert_domains \
                    --email "${existing_email}" \
                    --non-interactive \
                    --agree-tos \
                    --redirect 2>&1 | tee /tmp/certbot-setup.log; then
                    log_success "SSL certificates obtained successfully"

                    # Enable nginx site if it wasn't enabled before (due to missing certificates)
                    local nginx_config="/etc/nginx/sites-available/$APP_NAME"
                    if [ -f "$nginx_config" ] && [ ! -L "/etc/nginx/sites-enabled/$APP_NAME" ]; then
                        log_info "Enabling nginx site..."
                        sudo ln -sf "$nginx_config" "/etc/nginx/sites-enabled/$APP_NAME"
                        if sudo nginx -t 2>&1 | grep -q "successful"; then
                            sudo systemctl reload nginx
                            log_success "Nginx site enabled and loaded"
                        fi
                    fi

                    log_success "Sites available at: https://${DOMAIN}$([ -n "${DOMAIN_INTERNAL:-}" ] && echo ", https://${DOMAIN_INTERNAL}" || echo "")"
                else
                    log_warning "Automatic SSL setup failed"
                    log_info "Run manually: sudo certbot --nginx $cert_domains"
                fi
            else
                log_warning "No existing certbot account found"
                log_info "Run manually: sudo certbot --nginx $cert_domains"
            fi
        fi

        # Setup auto-renewal (system-wide, once per server)
        if ! sudo systemctl is-active --quiet certbot.timer; then
            sudo systemctl enable certbot.timer
            sudo systemctl start certbot.timer
            log_success "SSL auto-renewal enabled (system-wide)"
        else
            log_info "SSL auto-renewal already enabled"
        fi
    fi

    return 0
}

# Step 11: Create deployment info file
create_deployment_info() {
    local extra_info=""

    if [ "$APP_TYPE" = "rails" ]; then
        extra_info="
Database: ${DB_NAME}
Redis Database: ${REDIS_DB_NUMBER:-0}

Container Architecture:
- Web containers: ${DEFAULT_SCALE} (ports ${BASE_PORT}-$((BASE_PORT + DEFAULT_SCALE - 1)))
- Worker containers: ${WORKER_COUNT:-0}
- Scheduler: $([ "${SCHEDULER_ENABLED:-false}" = "true" ] && echo "Enabled" || echo "Disabled")

Management Scripts:
- Console: \$DEVOPS_DIR/scripts/console.sh $APP_NAME
- Rails Task: \$DEVOPS_DIR/scripts/rails-task.sh $APP_NAME <task>
- Restore DB: $APP_DIR/restore.sh"
    else
        extra_info="
Container Architecture:
- Web containers: ${DEFAULT_SCALE} (ports ${BASE_PORT}-$((BASE_PORT + DEFAULT_SCALE - 1)))
- No workers or scheduler (frontend only)"
    fi

    cat > "$APP_DIR/deployment-info.txt" << INFO
${APP_DISPLAY_NAME} Deployment Information
==========================================

Application: ${APP_DISPLAY_NAME}
Type: ${APP_TYPE}
Domain: ${DOMAIN}
Repository: ${REPO_URL}
Branch: ${REPO_BRANCH}
${extra_info}

Directories:
- Application: ${APP_DIR}
- Repository: ${REPO_DIR}
- Logs: ${LOG_DIR}
- Docker Images: ${IMAGE_BACKUP_DIR}
$([ "$APP_TYPE" = "rails" ] && echo "- Backups: ${BACKUP_DIR}")

Files:
- Environment: ${ENV_FILE}
- Config: ${SCRIPT_DIR}/config.sh
- Deploy script: ${SCRIPT_DIR}/deploy.sh
- Setup script: ${SCRIPT_DIR}/setup.sh

Next Steps:
===========

1. Review and update environment variables:
   nano ${ENV_FILE}

$([ "$APP_TYPE" = "nextjs" ] && echo "2. Ensure Next.js is configured for standalone output:
   Edit next.config.js and add: output: 'standalone'

3. Update API URLs and keys in .env.production")

$([ "$APP_TYPE" = "rails" ] && echo "2. Update database credentials and API keys if needed")

3. Deploy the application:
   cd ${SCRIPT_DIR}
   ./deploy.sh deploy

4. Check status:
   ./deploy.sh status

5. View logs:
   ./deploy.sh logs

Management Commands:
====================
./deploy.sh deploy          - Deploy latest code
./deploy.sh restart         - Restart all containers
./deploy.sh stop            - Stop all containers
./deploy.sh scale <N>       - Scale web containers
./deploy.sh status          - Show container status
./deploy.sh logs [name]     - View logs
$([ "$APP_TYPE" = "rails" ] && echo "./deploy.sh console        - Open Rails console")

INFO

    log_success "Deployment info created: $APP_DIR/deployment-info.txt"
}
