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
source "$DEVOPS_DIR/common/db-utils.sh"

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

# Setup automated backups
log_info "Setting up automated database backups..."

# Create backup script
cat > "$APP_DIR/backup.sh" << 'BACKUP_SCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../../DevOps" && pwd)"
source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/db-utils.sh"
source "$SCRIPT_DIR/../config.sh"

backup_database "$DB_NAME" "$BACKUP_DIR"
cleanup_old_backups "$BACKUP_DIR" "$BACKUP_RETENTION_DAYS"
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
source "$DEVOPS_DIR/common/db-utils.sh"
source "$SCRIPT_DIR/../config.sh"

if [ -z "$1" ]; then
    list_backups "$BACKUP_DIR"
    echo ""
    echo "Usage: $0 <backup_file>"
    exit 1
fi

restore_database "$DB_NAME" "$1"
RESTORE_SCRIPT

chmod +x "$APP_DIR/restore.sh"

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

3. Setup SSL certificates (only works if DNS is configured):
   cd ${SCRIPT_DIR}
   ./deploy.sh ssl-setup

4. Deploy the application:
   cd ${SCRIPT_DIR}
   ./deploy.sh deploy

5. Check status:
   ./deploy.sh status

6. View logs:
   ./deploy.sh logs
   ./deploy.sh logs worker_1
   ./deploy.sh logs scheduler

7. Access Rails console:
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
