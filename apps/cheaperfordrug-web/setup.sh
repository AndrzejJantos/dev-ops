#!/bin/bash

# CheaperForDrug Web Setup Script
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

    log_success ".env.production created"
    log_warning "IMPORTANT: Review and update $ENV_FILE with your actual values"
else
    log_info ".env.production already exists"
fi

# Copy Dockerfile and .dockerignore from DevOps template
log_info "Copying Docker files from template..."
cp "$DEVOPS_DIR/common/nextjs/Dockerfile.template" "$REPO_DIR/Dockerfile"
cp "$DEVOPS_DIR/common/nextjs/.dockerignore.template" "$REPO_DIR/.dockerignore"

# Check if next.config.js has standalone output configured
log_info "Checking Next.js configuration..."
if [ -f "$REPO_DIR/next.config.js" ] || [ -f "$REPO_DIR/next.config.mjs" ]; then
    log_warning "Please ensure your next.config.js has output: 'standalone' configured:"
    echo ""
    echo "  module.exports = {"
    echo "    output: 'standalone',"
    echo "    // ... other config"
    echo "  }"
    echo ""
else
    log_warning "next.config.js not found. You may need to create it with standalone output."
fi

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

# Setup automated cleanup
log_info "Setting up automated cleanup..."

# Create cleanup script
cat > "$APP_DIR/cleanup.sh" << 'CLEANUP_SCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../../DevOps" && pwd)"
source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/docker-utils.sh"
APP_CONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/cheaperfordrug-web"
source "$APP_CONFIG_DIR/config.sh"

# Cleanup old image backups (keep last ${MAX_IMAGE_BACKUPS})
if [ -d "$IMAGE_BACKUP_DIR" ]; then
    cleanup_old_image_backups "$IMAGE_BACKUP_DIR" "${MAX_IMAGE_BACKUPS:-20}"
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
log_info "Setting up SSL certificate..."

# Check if certbot is installed
if ! command -v certbot >/dev/null 2>&1; then
    log_info "Installing certbot..."
    sudo apt-get update -qq
    sudo apt-get install -y certbot python3-certbot-nginx
fi

# Check DNS configuration
log_info "Checking DNS configuration for ${DOMAIN}..."
# Get IPv4 address explicitly
server_ipv4=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org)
domain_ip=$(dig +short "$DOMAIN" A | tail -1)

if [ -z "$domain_ip" ]; then
    log_warning "DNS not configured for ${DOMAIN}"
    log_info "Please configure DNS A record: ${DOMAIN} -> ${server_ipv4}"
    log_info "You can setup SSL later by running: sudo certbot --nginx -d ${DOMAIN}"
elif [ "$domain_ip" != "$server_ipv4" ]; then
    log_warning "DNS mismatch: ${DOMAIN} points to ${domain_ip}, but server IPv4 is ${server_ipv4}"
    log_info "Please update DNS A record: ${DOMAIN} -> ${server_ipv4}"
    log_info "You can setup SSL later by running: sudo certbot --nginx -d ${DOMAIN}"
else
    log_success "DNS correctly configured: ${DOMAIN} -> ${server_ipv4}"

    # Check if certificate already exists
    if sudo certbot certificates 2>/dev/null | grep -q "Certificate Name: ${DOMAIN}"; then
        log_info "SSL certificate already exists for ${DOMAIN}"
    else
        # Obtain SSL certificate
        log_info "Obtaining SSL certificate from Let's Encrypt..."
        if sudo certbot --nginx \
            -d "$DOMAIN" \
            --non-interactive \
            --agree-tos \
            --redirect 2>/dev/null; then
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
        fi
    fi
fi

# Create deployment info file
cat > "$APP_DIR/deployment-info.txt" << INFO
CheaperForDrug Web Deployment Information
==========================================

Application: ${APP_DISPLAY_NAME}
Domain: ${DOMAIN}
Repository: ${REPO_URL}
Type: Next.js Frontend

Container Architecture:
- Web containers: ${DEFAULT_SCALE} (ports ${BASE_PORT}-$((BASE_PORT + DEFAULT_SCALE - 1)))
- No workers or scheduler (frontend only)

Directories:
- Application: ${APP_DIR}
- Repository: ${REPO_DIR}
- Logs: ${LOG_DIR}
- Docker Images: ${IMAGE_BACKUP_DIR}

Files:
- Environment: ${ENV_FILE}
- Deploy script: ${SCRIPT_DIR}/deploy.sh

Next Steps:
===========

1. Review and update environment variables:
   nano ${ENV_FILE}

2. Ensure Next.js is configured for standalone output:
   Edit next.config.js and add: output: 'standalone'

3. Update API URLs and keys in .env.production:
   - NEXT_PUBLIC_API_URL
   - NEXT_PUBLIC_GOOGLE_MAPS_API_KEY
   - NEXT_PUBLIC_GA_MEASUREMENT_ID

4. Deploy the application:
   cd ${SCRIPT_DIR}
   ./deploy.sh deploy

5. Check status:
   ./deploy.sh status

6. View logs:
   ./deploy.sh logs

Management Commands:
====================
./deploy.sh deploy          - Deploy latest code
./deploy.sh restart         - Restart all containers
./deploy.sh stop            - Stop all containers
./deploy.sh scale <N>       - Scale web containers
./deploy.sh status          - Show container status
./deploy.sh logs [name]     - View logs
./deploy.sh ssl-setup       - Setup SSL certificates

INFO

log_success "Setup completed successfully!"
echo ""
cat "$APP_DIR/deployment-info.txt"
