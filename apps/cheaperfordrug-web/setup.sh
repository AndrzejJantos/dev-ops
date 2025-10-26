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
    UPSTREAM_SERVERS="${UPSTREAM_SERVERS}    server localhost:${PORT} max_fails=3 fail_timeout=30s;\n"
done

# Remove trailing newline
UPSTREAM_SERVERS=$(echo -e "$UPSTREAM_SERVERS" | sed '$ s/\\n$//')

# Generate nginx config
cat "$nginx_template" | \
    sed "s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g" | \
    sed "s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|g" | \
    sed "s|{{DOMAIN}}|${DOMAIN}|g" | \
    sed "s|{{APP_NAME}}|${APP_NAME}|g" | \
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

4. Setup SSL certificates (only works if DNS is configured):
   cd ${SCRIPT_DIR}
   ./deploy.sh ssl-setup

5. Deploy the application:
   cd ${SCRIPT_DIR}
   ./deploy.sh deploy

6. Check status:
   ./deploy.sh status

7. View logs:
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
