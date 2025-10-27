#!/bin/bash

# Disaster Recovery Script
# Location: /home/andrzej/DevOps/scripts/disaster-recovery.sh
# This script rebuilds the entire server from scratch
#
# Usage:
#   ./disaster-recovery.sh [config-file]
#
# If no config file is provided, it will use disaster-recovery-config.sh
# in the same directory

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo "========================================================================"
    echo -e "${GREEN}STEP $1: $2${NC}"
    echo "========================================================================"
    echo ""
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
CONFIG_FILE="${1:-$SCRIPT_DIR/disaster-recovery-config.sh}"

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    echo ""
    echo "Usage: $0 [config-file]"
    echo ""
    echo "Create a configuration file with the following variables:"
    echo "  RECOVERY_USER          - User to run deployments (default: current user)"
    echo "  RECOVERY_HOME          - Home directory (default: /home/\$RECOVERY_USER)"
    echo "  DEVOPS_REPO_URL        - DevOps repository URL"
    echo "  DEVOPS_REPO_BRANCH     - DevOps repository branch (default: master)"
    echo "  INSTALL_DEPENDENCIES   - Install system dependencies (default: true)"
    echo "  SETUP_SSL              - Setup SSL certificates (default: true)"
    echo "  APPS_TO_DEPLOY         - Array of app names to deploy"
    echo ""
    echo "Example: see disaster-recovery-config.example.sh"
    exit 1
fi

log_info "Loading configuration from: $CONFIG_FILE"
source "$CONFIG_FILE"

# Set defaults
RECOVERY_USER="${RECOVERY_USER:-$USER}"
RECOVERY_HOME="${RECOVERY_HOME:-$HOME}"
DEVOPS_REPO_BRANCH="${DEVOPS_REPO_BRANCH:-master}"
INSTALL_DEPENDENCIES="${INSTALL_DEPENDENCIES:-true}"
SETUP_SSL="${SETUP_SSL:-true}"

log_success "Configuration loaded"
echo "  User: $RECOVERY_USER"
echo "  Home: $RECOVERY_HOME"
echo "  DevOps Repo: $DEVOPS_REPO_URL"
echo "  DevOps Branch: $DEVOPS_REPO_BRANCH"
echo "  Apps to deploy: ${#APPS_TO_DEPLOY[@]}"

# Confirm before starting
echo ""
log_warning "This script will rebuild the entire server from scratch."
log_warning "This is a potentially destructive operation."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    log_info "Disaster recovery cancelled"
    exit 0
fi

# ==============================================================================
# STEP 1: Install System Dependencies
# ==============================================================================

if [ "$INSTALL_DEPENDENCIES" = "true" ]; then
    log_step "1" "Installing System Dependencies"

    log_info "Updating package lists..."
    sudo apt-get update -qq

    log_info "Installing core dependencies..."
    sudo apt-get install -y \
        curl \
        wget \
        git \
        build-essential \
        ca-certificates \
        gnupg \
        lsb-release

    # Install Docker
    log_info "Installing Docker..."
    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sudo sh /tmp/get-docker.sh
        sudo usermod -aG docker "$RECOVERY_USER"
        sudo systemctl enable docker
        sudo systemctl start docker
        log_success "Docker installed"
    else
        log_info "Docker already installed"
    fi

    # Install Nginx
    log_info "Installing Nginx..."
    if ! command -v nginx >/dev/null 2>&1; then
        sudo apt-get install -y nginx
        sudo systemctl enable nginx
        sudo systemctl start nginx
        log_success "Nginx installed"
    else
        log_info "Nginx already installed"
    fi

    # Install PostgreSQL
    log_info "Installing PostgreSQL..."
    if ! command -v psql >/dev/null 2>&1; then
        sudo apt-get install -y postgresql postgresql-contrib
        sudo systemctl enable postgresql
        sudo systemctl start postgresql
        log_success "PostgreSQL installed"
    else
        log_info "PostgreSQL already installed"
    fi

    # Install Redis
    log_info "Installing Redis..."
    if ! command -v redis-cli >/dev/null 2>&1; then
        sudo apt-get install -y redis-server
        sudo systemctl enable redis-server
        sudo systemctl start redis-server
        log_success "Redis installed"
    else
        log_info "Redis already installed"
    fi

    # Install Certbot (for SSL)
    log_info "Installing Certbot..."
    if ! command -v certbot >/dev/null 2>&1; then
        sudo apt-get install -y certbot python3-certbot-nginx
        sudo systemctl enable certbot.timer
        sudo systemctl start certbot.timer
        log_success "Certbot installed and auto-renewal enabled"
    else
        log_info "Certbot already installed"
    fi

    # Install Ruby (for Rails apps)
    log_info "Installing Ruby..."
    if ! command -v ruby >/dev/null 2>&1; then
        sudo apt-get install -y ruby ruby-dev
        log_success "Ruby installed"
    else
        log_info "Ruby already installed"
    fi

    # Install Node.js (for asset compilation)
    log_info "Installing Node.js..."
    if ! command -v node >/dev/null 2>&1; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt-get install -y nodejs
        log_success "Node.js installed"
    else
        log_info "Node.js already installed"
    fi

    log_success "All system dependencies installed"
else
    log_info "Skipping system dependencies installation"
fi

# ==============================================================================
# STEP 2: Clone DevOps Repository
# ==============================================================================

log_step "2" "Cloning DevOps Repository"

DEVOPS_DIR="$RECOVERY_HOME/DevOps"

if [ -d "$DEVOPS_DIR/.git" ]; then
    log_warning "DevOps directory already exists: $DEVOPS_DIR"
    log_info "Pulling latest changes..."
    cd "$DEVOPS_DIR"
    git fetch origin "$DEVOPS_REPO_BRANCH"
    git reset --hard origin/"$DEVOPS_REPO_BRANCH"
    log_success "DevOps repository updated"
else
    log_info "Cloning DevOps repository..."
    git clone "$DEVOPS_REPO_URL" "$DEVOPS_DIR"
    cd "$DEVOPS_DIR"
    git checkout "$DEVOPS_REPO_BRANCH"
    log_success "DevOps repository cloned"
fi

# Make scripts executable
chmod +x "$DEVOPS_DIR"/scripts/*.sh
chmod +x "$DEVOPS_DIR"/common/*.sh

log_success "DevOps repository ready"

# ==============================================================================
# STEP 3: Setup Applications
# ==============================================================================

log_step "3" "Setting Up Applications"

if [ ${#APPS_TO_DEPLOY[@]} -eq 0 ]; then
    log_warning "No apps configured for deployment"
    log_info "Add apps to APPS_TO_DEPLOY array in config file"
else
    for app_name in "${APPS_TO_DEPLOY[@]}"; do
        log_info "======== Setting up: $app_name ========"

        APP_DIR="$DEVOPS_DIR/apps/$app_name"

        if [ ! -d "$APP_DIR" ]; then
            log_error "App directory not found: $APP_DIR"
            log_warning "Skipping $app_name"
            continue
        fi

        if [ ! -f "$APP_DIR/setup.sh" ]; then
            log_error "Setup script not found: $APP_DIR/setup.sh"
            log_warning "Skipping $app_name"
            continue
        fi

        # Run setup script
        cd "$APP_DIR"
        bash setup.sh

        if [ $? -eq 0 ]; then
            log_success "Setup completed for $app_name"
        else
            log_error "Setup failed for $app_name"
            log_warning "Continuing with next app..."
        fi
    done

    log_success "All applications setup completed"
fi

# ==============================================================================
# STEP 4: Configure Environment Variables
# ==============================================================================

log_step "4" "Configuring Environment Variables"

log_warning "IMPORTANT: You need to manually configure environment variables for each app"
echo ""
echo "For each app, edit the .env.production file:"
echo ""

for app_name in "${APPS_TO_DEPLOY[@]}"; do
    ENV_FILE="$RECOVERY_HOME/apps/$app_name/.env.production"
    if [ -f "$ENV_FILE" ]; then
        echo "  nano $ENV_FILE"
    fi
done

echo ""
log_info "Press Enter when you've configured all environment variables..."
read -p ""

log_success "Environment variables configured"

# ==============================================================================
# STEP 5: Deploy Applications
# ==============================================================================

log_step "5" "Deploying Applications"

for app_name in "${APPS_TO_DEPLOY[@]}"; do
    log_info "======== Deploying: $app_name ========"

    APP_DIR="$DEVOPS_DIR/apps/$app_name"

    if [ ! -f "$APP_DIR/deploy.sh" ]; then
        log_error "Deploy script not found: $APP_DIR/deploy.sh"
        log_warning "Skipping $app_name"
        continue
    fi

    # Run deployment
    cd "$APP_DIR"
    ./deploy.sh deploy

    if [ $? -eq 0 ]; then
        log_success "Deployment completed for $app_name"
    else
        log_error "Deployment failed for $app_name"
        log_warning "Continuing with next app..."
    fi

    # Brief pause between deployments
    sleep 5
done

log_success "All applications deployed"

# ==============================================================================
# STEP 6: Setup SSL Certificates
# ==============================================================================

if [ "$SETUP_SSL" = "true" ]; then
    log_step "6" "Setting Up SSL Certificates"

    log_warning "SSL certificates need to be configured for each domain"
    echo ""
    echo "For each app, run:"
    echo "  cd \$DEVOPS_DIR/apps/<app-name>"
    echo "  ./deploy.sh ssl-setup"
    echo ""
    log_info "Or run manually with certbot:"
    echo "  sudo certbot --nginx -d example.com -d www.example.com"
    echo ""

    read -p "Do you want to setup SSL certificates now? (yes/no): " setup_ssl_now

    if [ "$setup_ssl_now" = "yes" ]; then
        for app_name in "${APPS_TO_DEPLOY[@]}"; do
            APP_DIR="$DEVOPS_DIR/apps/$app_name"
            cd "$APP_DIR"

            if [ -f "config.sh" ]; then
                source "config.sh"
                log_info "Setting up SSL for $DOMAIN..."
                sudo certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" || log_warning "SSL setup failed for $DOMAIN"
            fi
        done
    else
        log_info "Skipping SSL setup for now"
    fi
fi

# ==============================================================================
# STEP 7: Setup Centralized Cleanup
# ==============================================================================

log_step "7" "Setting Up Centralized Cleanup"

log_info "Installing centralized cleanup cron job..."

# Add cron job for cleanup
CLEANUP_SCRIPT="$DEVOPS_DIR/scripts/cleanup-all-apps.sh"
if [ -f "$CLEANUP_SCRIPT" ]; then
    chmod +x "$CLEANUP_SCRIPT"

    # Remove old app-specific cleanup jobs
    crontab -l 2>/dev/null | grep -v "/apps/.*/cleanup.sh" | crontab - || true

    # Add new centralized cleanup job
    (crontab -l 2>/dev/null | grep -v "cleanup-all-apps.sh"; echo "0 2 * * * $CLEANUP_SCRIPT >> $DEVOPS_DIR/logs/cleanup-all.log 2>&1") | crontab -

    log_success "Centralized cleanup configured (daily at 2 AM)"
else
    log_warning "Cleanup script not found: $CLEANUP_SCRIPT"
fi

# ==============================================================================
# STEP 8: Verify Deployment
# ==============================================================================

log_step "8" "Verifying Deployment"

log_info "Checking container status..."
docker ps

echo ""
log_info "Checking nginx status..."
sudo nginx -t
sudo systemctl status nginx --no-pager

echo ""
log_info "Checking SSL certificate status..."
sudo certbot certificates

echo ""
log_success "Disaster recovery completed successfully!"
echo ""
echo "========================================================================"
echo "                     RECOVERY SUMMARY"
echo "========================================================================"
echo ""
echo "System Dependencies: Installed"
echo "DevOps Repository: Cloned"
echo "Applications Setup: Completed"
echo "Applications Deployed: ${#APPS_TO_DEPLOY[@]}"
echo "Cleanup Configured: Yes"
echo ""
echo "Next Steps:"
echo "  1. Verify all applications are running: docker ps"
echo "  2. Check application logs: docker logs <container-name>"
echo "  3. Test each application endpoint: curl https://<domain>"
echo "  4. Monitor system resources: htop"
echo "  5. Check cron jobs: crontab -l"
echo ""
echo "Useful Commands:"
echo "  cd \$DEVOPS_DIR/apps/<app-name>"
echo "  ./deploy.sh status       # Check app status"
echo "  ./deploy.sh logs         # View app logs"
echo "  ./deploy.sh scale N      # Scale containers"
echo ""
echo "========================================================================"
echo ""
