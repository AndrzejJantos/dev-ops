#!/bin/bash

# Configuration for cheaperfordrug-landing application
# Location: /home/andrzej/DevOps/apps/cheaperfordrug-landing/config.sh
# This file is sourced by setup and deployment scripts

# Application identification
export APP_TYPE="rails"
export APP_NAME="cheaperfordrug-landing"
export APP_DISPLAY_NAME="CheaperForDrug Landing Page"

# Repository configuration
export REPO_URL="git@github.com:AndrzejJantos/cheaperfordrug-landing.git"
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
export DOMAIN="taniejpolek.pl"
export DOMAIN_INTERNAL="presale.taniejpolek.pl"  # Additional domain (presale subdomain)
export BASE_PORT=3010          # Starting port for containers (host side)
export CONTAINER_PORT=3000     # Port inside container
export PORT_RANGE_END=3019     # Ending port (supports 10 instances)

# Container architecture configuration
# Landing page: Only web containers needed (no background jobs)
export DEFAULT_SCALE=2         # Default number of web container instances
export WORKER_COUNT=0          # Number of worker containers (0 = disabled)
export SCHEDULER_ENABLED=false # Enable Clockwork scheduler container (false = disabled)

# Architecture examples:
# Simple landing/marketing site:  DEFAULT_SCALE=2, WORKER_COUNT=0, SCHEDULER_ENABLED=false
# Full application with jobs:     DEFAULT_SCALE=2, WORKER_COUNT=1, SCHEDULER_ENABLED=true
# High-traffic app:               DEFAULT_SCALE=4, WORKER_COUNT=2, SCHEDULER_ENABLED=true

# SendGrid configuration for email notifications
# Note: Application uses SendGrid API (not SMTP) for email delivery
# API key must be configured in .env.production file
export SENDGRID_API_KEY="dummy_sendgrid_key_change_me"
export SENDGRID_FROM_EMAIL="noreply@${DOMAIN}"
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
    # Payment processing
    "STRIPE_PUBLISHABLE_KEY=pk_test_dummy_change_me"
    "STRIPE_SECRET_KEY=sk_test_dummy_change_me"
    # Email configuration (SendGrid API)
    "SENDGRID_API_KEY=${SENDGRID_API_KEY}"
    "SENDGRID_FROM_EMAIL=${SENDGRID_FROM_EMAIL}"
    "NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL}"
    # Analytics and tracking
    "GOOGLE_ANALYTICS_ID=G-DUMMY000000"
    "GOOGLE_TAG_MANAGER_ID=GTM-DUMMY00"
    "FACEBOOK_PIXEL_ID=000000000000000"
    # Error tracking
    "ROLLBAR_ACCESS_TOKEN=${ROLLBAR_ACCESS_TOKEN:-}"
    # Admin authentication
    "ADMIN_EMAIL=andrzej@webet.pl"
)

# Health check configuration
export HEALTH_CHECK_PATH="/up"
export HEALTH_CHECK_TIMEOUT=60
export HEALTH_CHECK_INTERVAL=2

# Backup configuration
export BACKUP_RETENTION_DAYS=30
export MAX_IMAGE_VERSIONS=3

# Docker image backup (save images as tar files in app directory)
export IMAGE_BACKUP_DIR="${APP_DIR}/docker-images"
export SAVE_IMAGE_BACKUPS=true  # Save each built image as .tar file
export MAX_IMAGE_BACKUPS=20     # Keep last 20 image tar files

# Deployment configuration
export MIGRATION_BACKUP_ENABLED=true
export ZERO_DOWNTIME_ENABLED=true
export AUTO_CLEANUP_ENABLED=true
