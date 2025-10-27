#!/bin/bash

# CheaperForDrug API Setup Script
# This script initializes the deployment environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$DEVOPS_DIR/common/utils.sh"
source "$SCRIPT_DIR/config.sh"

log_info "Starting setup for ${APP_DISPLAY_NAME}"
log_info "Domain: ${DOMAIN}"

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

# Setup environment file
if [ ! -f "$ENV_FILE" ]; then
    log_info "Creating .env.production file..."
    cp "$SCRIPT_DIR/.env.production.template" "$ENV_FILE"

    # Generate SECRET_KEY_BASE
    log_info "Generating SECRET_KEY_BASE..."
    SECRET_KEY=$(openssl rand -hex 64)
    sed -i "s|SECRET_KEY_BASE=CHANGE_ME_IN_PRODUCTION|SECRET_KEY_BASE=${SECRET_KEY}|g" "$ENV_FILE"

    # Generate JWT_SECRET_KEY
    log_info "Generating JWT_SECRET_KEY..."
    JWT_SECRET=$(openssl rand -hex 64)
    sed -i "s|JWT_SECRET_KEY=CHANGE_ME_IN_PRODUCTION|JWT_SECRET_KEY=${JWT_SECRET}|g" "$ENV_FILE"

    # Generate database password
    log_info "Generating database password..."
    DB_PASSWORD=$(openssl rand -hex 32)
    sed -i "s|CHANGE_DB_PASSWORD|${DB_PASSWORD}|g" "$ENV_FILE"

    log_success ".env.production created"
    log_warning "IMPORTANT: Review and update $ENV_FILE with your actual credentials"
else
    log_info ".env.production already exists"
fi

# Setup PostgreSQL database
log_info "Setting up PostgreSQL database..."

if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    log_info "Database $DB_NAME already exists"
else
    create_database "$DB_NAME" "$DB_USER"
fi

# Setup Redis database
log_info "Checking Redis..."
if systemctl is-active --quiet redis || systemctl is-active --quiet redis-server; then
    log_success "Redis is running"
else
    log_warning "Redis is not running. Please install and start Redis:"
    echo "  sudo apt-get install redis-server"
    echo "  sudo systemctl enable redis-server"
    echo "  sudo systemctl start redis-server"
fi

# Setup native Rails environment for console access
log_info "Setting up native Rails environment for console access..."
cd "$REPO_DIR"

# Install gems locally
if [ ! -d "vendor/bundle" ]; then
    log_info "Installing gems natively..."
    bundle install --path vendor/bundle --jobs 4 --retry 3
    log_success "Gems installed to vendor/bundle"
else
    log_info "Native gems already installed"
fi

# Create binstubs for easy access
bundle binstubs --all 2>/dev/null || true

log_success "Native Rails environment ready"
log_info "You can now use: cd $REPO_DIR && bundle exec rails console"

# Copy Dockerfile and .dockerignore from DevOps template
log_info "Copying Docker files from template..."
cp "$DEVOPS_DIR/common/rails/Dockerfile.template" "$REPO_DIR/Dockerfile"
cp "$DEVOPS_DIR/common/rails/.dockerignore.template" "$REPO_DIR/.dockerignore"

# Setup nginx configuration
log_info "Setting up Nginx configuration..."
nginx_template="$SCRIPT_DIR/nginx.conf.template"
nginx_config="/etc/nginx/sites-available/$APP_NAME"

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

# Enable site
sudo ln -sf "$nginx_config" "/etc/nginx/sites-enabled/$APP_NAME"

# Test and reload nginx
if sudo nginx -t 2>&1 | grep -q "successful"; then
    sudo systemctl reload nginx
    log_success "Nginx configuration created and loaded"
else
    log_error "Nginx configuration test failed"
    exit 1
fi

# Setup default catch-all server (security)
log_info "Setting up default catch-all server..."
default_server_config="/etc/nginx/sites-available/000-default"
if [ ! -f "$default_server_config" ]; then
    sudo cp "$DEVOPS_DIR/common/nginx/default-server.conf" "$default_server_config"
    sudo ln -sf "$default_server_config" "/etc/nginx/sites-enabled/000-default"

    if sudo nginx -t 2>&1 | grep -q "successful"; then
        sudo systemctl reload nginx
        log_success "Default catch-all server configured (rejects unknown domains)"
    else
        log_error "Default server configuration test failed"
        exit 1
    fi
else
    log_info "Default catch-all server already configured"
fi

# Setup automated backups
log_info "Setting up automated database backups..."

# Create backup script
cat > "$APP_DIR/backup.sh" << 'BACKUP_SCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../../DevOps" && pwd)"
source "$DEVOPS_DIR/common/utils.sh"
APP_CONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/cheaperfordrug-api"
source "$APP_CONFIG_DIR/config.sh"

backup_database "$DB_NAME" "$BACKUP_DIR"
cleanup_old_backups "$BACKUP_DIR" "${BACKUP_RETENTION_DAYS:-30}"
BACKUP_SCRIPT

chmod +x "$APP_DIR/backup.sh"

# Setup cron job for backups (every 30 minutes)
(crontab -l 2>/dev/null | grep -v "$APP_DIR/backup.sh"; echo "*/30 * * * * $APP_DIR/backup.sh >> $LOG_DIR/backup.log 2>&1") | crontab -

log_success "Automated backups configured (every 30 minutes)"

# Create restore script
log_info "Creating database restore script..."
cat > "$APP_DIR/restore.sh" << 'RESTORE_SCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../../DevOps" && pwd)"
source "$DEVOPS_DIR/common/utils.sh"
APP_CONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/cheaperfordrug-api"
source "$APP_CONFIG_DIR/config.sh"

if [ -z "$1" ]; then
    list_backups "$BACKUP_DIR"
    echo ""
    echo "Usage: $0 <backup_file>"
    exit 1
fi

restore_database "$DB_NAME" "$1"
RESTORE_SCRIPT

chmod +x "$APP_DIR/restore.sh"

# Setup automated cleanup
log_info "Setting up automated cleanup..."

# Create cleanup script
cat > "$APP_DIR/cleanup.sh" << 'CLEANUP_SCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../../DevOps" && pwd)"
source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/docker-utils.sh"
APP_CONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/cheaperfordrug-api"
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

chmod +x "$APP_DIR/cleanup.sh"

# Setup cron job for cleanup (daily at 2 AM)
(crontab -l 2>/dev/null | grep -v "$APP_DIR/cleanup.sh"; echo "0 2 * * * $APP_DIR/cleanup.sh >> $LOG_DIR/cleanup.log 2>&1") | crontab -

log_success "Automated cleanup configured (daily at 2 AM)"

# Setup SSL certificate (automatic if DNS is configured)
log_info "Setting up SSL certificates..."

# Check if certbot is installed
if ! command -v certbot >/dev/null 2>&1; then
    log_info "Installing certbot..."
    sudo apt-get update -qq
    sudo apt-get install -y certbot python3-certbot-nginx
fi

# Check DNS configuration
log_info "Checking DNS configuration..."
# Get IPv4 address explicitly
server_ipv4=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org)

# Check both subdomains
dns_ok=true
for domain in "$DOMAIN_PUBLIC" "$DOMAIN_INTERNAL"; do
    domain_ip=$(dig +short "$domain" A | tail -1)

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
    log_info "DNS configured correctly for both subdomains. Obtaining SSL certificates..."

    # Check if certificates already exist
    if sudo certbot certificates 2>/dev/null | grep -q "Certificate Name: ${DOMAIN_PUBLIC}"; then
        log_info "SSL certificate already exists for ${DOMAIN_PUBLIC}"
    else
        if sudo certbot --nginx \
            -d "$DOMAIN_PUBLIC" -d "$DOMAIN_INTERNAL" \
            --non-interactive \
            --agree-tos \
            --redirect 2>/dev/null; then
            log_success "SSL certificates obtained successfully for both API subdomains"

            # Setup auto-renewal
            if ! sudo systemctl is-active --quiet certbot.timer; then
                sudo systemctl enable certbot.timer
                sudo systemctl start certbot.timer
                log_success "SSL auto-renewal enabled"
            fi
        else
            log_warning "Failed to obtain SSL certificates automatically"
            log_info "You can setup SSL later by running:"
            echo "  sudo certbot --nginx -d ${DOMAIN_PUBLIC} -d ${DOMAIN_INTERNAL}"
        fi
    fi
else
    log_warning "DNS not fully configured. Skipping SSL setup."
    log_info "After DNS is configured, run:"
    echo "  sudo certbot --nginx -d ${DOMAIN_PUBLIC} -d ${DOMAIN_INTERNAL}"
fi

# Create deployment info file
cat > "$APP_DIR/deployment-info.txt" << INFO
CheaperForDrug API Deployment Information
==========================================

Application: ${APP_DISPLAY_NAME}
Domain: ${DOMAIN}
Repository: ${REPO_URL}

Container Architecture:
- Web containers: ${DEFAULT_SCALE} (ports ${BASE_PORT}-$((BASE_PORT + DEFAULT_SCALE - 1)))
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
- Deploy script: ${SCRIPT_DIR}/deploy.sh
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
   cd ${SCRIPT_DIR}
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

log_success "Setup completed successfully!"
echo ""
cat "$APP_DIR/deployment-info.txt"
