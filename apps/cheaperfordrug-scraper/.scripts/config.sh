#!/bin/bash

# Application Configuration for CheaperForDrug Scraper
# This is a Node.js scraper application with NordVPN integration
# Deploys 3 containers, one per country (Poland, Germany, Czech Republic)

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="nodejs-scraper"
export APP_NAME="cheaperfordrug-scraper"
export APP_DISPLAY_NAME="CheaperForDrug Scraper"

# No public domain - this is an internal scraper service
export DOMAIN=""

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================
export REPO_URL="git@github.com:AndrzejJantos/cheaperfordrug-scraper.git"
export REPO_BRANCH="master"

# ============================================================================
# CONTAINER ARCHITECTURE
# ============================================================================
# Scraper uses docker-compose with 3 country-specific containers
export DEPLOYMENT_MODE="docker-compose"
export DOCKER_COMPOSE_FILE="docker-compose.yml"

# Container names (managed by docker-compose)
export CONTAINER_POLAND="cheaperfordrug-scraper-poland"
export CONTAINER_GERMANY="cheaperfordrug-scraper-germany"
export CONTAINER_CZECH="cheaperfordrug-scraper-czech"

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================
export DOCKER_IMAGE_NAME="$APP_NAME"

# No port mapping needed - scrapers make outbound connections only
export BASE_PORT=""
export CONTAINER_PORT=""

# ============================================================================
# API CONFIGURATION
# ============================================================================
# Scrapers send data to the CheaperForDrug API
export API_ENDPOINT="http://api-scraper.localtest.me:4200/api/scraper/online_pharmacy_drugs"

# ============================================================================
# NORDVPN CONFIGURATION
# ============================================================================
export VPN_ROTATE_INTERVAL="15"  # Minutes between IP rotation

# Country-specific VPN settings (used by docker-compose)
export VPN_COUNTRY_POLAND="Poland"
export VPN_COUNTRY_GERMANY="Germany"
export VPN_COUNTRY_CZECH="Czech_Republic"

# ============================================================================
# SCRAPER CONFIGURATION
# ============================================================================
export HEADLESS="true"
export SEND_TO_API="true"
export LOG_LEVEL="info"
export SCRAPER_MODE="manager"  # manager, continuous, or once

# ============================================================================
# DEPLOYMENT CONFIGURATION
# ============================================================================
export ZERO_DOWNTIME_ENABLED=false  # Not applicable for scrapers
export HEALTH_CHECK_ENABLED=true
export HEALTH_CHECK_TIMEOUT=120

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================
export BACKUP_ENABLED=false         # No database backups needed
export MIGRATION_BACKUP_ENABLED=false

# ============================================================================
# IMAGE BACKUP CONFIGURATION
# ============================================================================
export SAVE_IMAGE_BACKUPS=true
export MAX_IMAGE_BACKUPS=10         # Keep last 10 versions

# ============================================================================
# AUTO CLEANUP
# ============================================================================
export AUTO_CLEANUP_ENABLED=true
export MAX_IMAGE_VERSIONS=10

# Keep old logs and outputs
export LOG_RETENTION_DAYS=30
export OUTPUT_RETENTION_DAYS=30

# ============================================================================
# PATHS (Auto-configured)
# ============================================================================
export APP_DIR="$HOME/apps/$APP_NAME"
export REPO_DIR="$APP_DIR/repo"
export ENV_FILE="$APP_DIR/.env.production"
export BACKUP_DIR="$APP_DIR/backups"
export LOG_DIR="$APP_DIR/logs"
export IMAGE_BACKUP_DIR="$APP_DIR/docker-images"

# Country-specific directories
export POLAND_LOG_DIR="$LOG_DIR/poland"
export GERMANY_LOG_DIR="$LOG_DIR/germany"
export CZECH_LOG_DIR="$LOG_DIR/czech"

export POLAND_OUTPUT_DIR="$APP_DIR/outputs/poland"
export GERMANY_OUTPUT_DIR="$APP_DIR/outputs/germany"
export CZECH_OUTPUT_DIR="$APP_DIR/outputs/czech"

export POLAND_STATE_DIR="$APP_DIR/state/poland"
export GERMANY_STATE_DIR="$APP_DIR/state/germany"
export CZECH_STATE_DIR="$APP_DIR/state/czech"

# ============================================================================
# DEVOPS CONFIGURATION
# ============================================================================
# Path to DevOps directory (for docker scripts)
export DEVOPS_DIR="$HOME/DevOps"

# ============================================================================
# NOTIFICATION CONFIGURATION
# ============================================================================
# Mailgun configuration for deployment notifications (optional)
export MAILGUN_API_KEY=""           # Set during setup
export MAILGUN_DOMAIN=""            # Set during setup
export NOTIFICATION_EMAIL=""        # Set during setup

# ============================================================================
# MONITORING CONFIGURATION
# ============================================================================
export ENABLE_MONITORING=true
export MONITORING_INTERVAL=300      # Check status every 5 minutes
