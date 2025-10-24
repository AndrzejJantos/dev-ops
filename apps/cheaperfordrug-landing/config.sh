#!/bin/bash

# Configuration for cheaperfordrug-landing application
# Location: /home/andrzej/DevOps/apps/cheaperfordrug-landing/config.sh
# This file is sourced by setup and deployment scripts

# Application identification
export APP_NAME="cheaperfordrug-landing"
export APP_DISPLAY_NAME="CheaperForDrug Landing Page"

# Repository configuration
export REPO_URL="https://github.com/AndrzejJantos/cheaperfordrug-landing.git"
export REPO_BRANCH="master"

# Server paths
export DEPLOY_USER="andrzej"
export DEPLOY_HOME="/home/${DEPLOY_USER}"
export APP_BASE_DIR="${DEPLOY_HOME}/apps"
export APP_DIR="${APP_BASE_DIR}/${APP_NAME}"
export REPO_DIR="${APP_DIR}/repo"
export ENV_FILE="${APP_DIR}/.env.production"
export BACKUP_DIR="${APP_DIR}/backups"
export LOG_DIR="${APP_DIR}/logs"

# Database configuration
export DB_NAME="${APP_NAME//-/_}_production"
export DB_USER="postgres"
export DB_PASSWORD=""  # Leave empty for peer authentication

# Redis configuration
export REDIS_DB_NUMBER=1  # Dedicated Redis database for this app
export REDIS_URL="redis://localhost:6379/${REDIS_DB_NUMBER}"

# Network configuration
export DOMAIN="presale.taniejpolek.pl"
export BASE_PORT=3010      # Starting port for containers
export PORT_RANGE_END=3019 # Ending port (supports 10 instances)
export DEFAULT_SCALE=2     # Default number of container instances

# Mailgun configuration for notifications
export MAILGUN_API_KEY="your_mailgun_api_key_here"
export MAILGUN_DOMAIN="mg.taniejpolek.pl"
export MAILGUN_FROM_EMAIL="noreply@${MAILGUN_DOMAIN}"
export NOTIFICATION_EMAIL="andrzej@webet.pl"

# Nginx configuration
export NGINX_CONF="/etc/nginx/sites-available/${APP_NAME}"
export NGINX_ENABLED="/etc/nginx/sites-enabled/${APP_NAME}"
export NGINX_UPSTREAM_NAME="${APP_NAME//-/_}_backend"

# Docker configuration
export DOCKER_IMAGE_NAME="${APP_NAME}"
export DOCKER_NETWORK="bridge"

# Application-specific environment variables
# These will be written to .env.production during setup
export APP_ENV_VARS=(
    "STRIPE_PUBLISHABLE_KEY=pk_live_your_production_publishable_key"
    "STRIPE_SECRET_KEY=sk_live_your_production_secret_key"
    "GOOGLE_ANALYTICS_ID=G-XXXXXXXXXX"
    "GOOGLE_TAG_MANAGER_ID=GTM-XXXXXXX"
    "FACEBOOK_PIXEL_ID=1234567890123456"
    "ROLLBAR_ACCESS_TOKEN=your_rollbar_token_here"
    "ADMIN_EMAIL=andrzej@webet.pl"
)

# Health check configuration
export HEALTH_CHECK_PATH="/up"
export HEALTH_CHECK_TIMEOUT=60
export HEALTH_CHECK_INTERVAL=2

# Backup configuration
export BACKUP_RETENTION_DAYS=30
export MAX_IMAGE_VERSIONS=3

# Deployment configuration
export MIGRATION_BACKUP_ENABLED=true
export ZERO_DOWNTIME_ENABLED=true
export AUTO_CLEANUP_ENABLED=true
