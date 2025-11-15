#!/bin/bash

# Application Configuration for CheaperForDrug API
# This is a Rails API backend with full background processing capabilities

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="rails"
export APP_NAME="cheaperfordrug-api"
export APP_DISPLAY_NAME="CheaperForDrug API"

# API uses three subdomains (all point to same backend containers)
export DOMAIN_PUBLIC="api-public.cheaperfordrug.com"
export DOMAIN_INTERNAL="api-internal.cheaperfordrug.com"
export DOMAIN_ADMIN="admin.cheaperfordrug.com"

# Primary domain for SSL setup (will include all subdomains)
export DOMAIN="api-public.cheaperfordrug.com"

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================
export REPO_URL="git@github.com:AndrzejJantos/cheaperfordrug-api.git"
export REPO_BRANCH="master"

# ============================================================================
# CONTAINER ARCHITECTURE
# ============================================================================
# API needs workers for background processing
export DEFAULT_SCALE=2              # 2 web containers for API (internet traffic)
export WORKER_COUNT=2               # 2 worker containers for background jobs
export SCHEDULER_ENABLED=false      # No scheduled tasks configured (no config/clock.rb)
export WORKER_SHUTDOWN_TIMEOUT=90   # Seconds to wait for workers to finish jobs during deployment

# Architecture note:
# - 2 web containers handle API requests (serves public, internal, and admin domains)
# - 2 workers process background jobs (emails, data processing, external API calls)
# - No scheduler needed (no recurring tasks configured)

# ============================================================================
# DEDICATED SCRAPER API CONTAINERS
# ============================================================================
# Separate containers for scraper-specific workloads (docker-compose-dedicated-api.yml)
export SCRAPER_PRODUCT_READ_SCALE=2    # High-frequency polling endpoint
export SCRAPER_NORMALIZER_SCALE=2      # Drug normalization endpoint
export SCRAPER_PRODUCT_WRITE_SCALE=1   # Product updates (has dedicated worker)
export SCRAPER_GENERAL_SCALE=2         # General scraping operations (has dedicated worker)

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================
export DOCKER_IMAGE_NAME="$APP_NAME"
export BASE_PORT=3020              # Port 3020 for web container (host side)
export CONTAINER_PORT=3000          # Port inside container (consistent across Rails and Next.js)

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================
# Database connection settings
# Uses localhost because containers run in --network host mode
export DB_NAME="cheaperfordrug_production"
export DB_USER="cheaperfordrug_user"
export DB_HOST="localhost"
export DB_PORT="5432"

# ============================================================================
# REDIS CONFIGURATION
# ============================================================================
export REDIS_DB_NUMBER=2               # Dedicated Redis database for API
export REDIS_URL="redis://localhost:6379/${REDIS_DB_NUMBER}"

# ============================================================================
# DEPLOYMENT CONFIGURATION
# ============================================================================
export ZERO_DOWNTIME_ENABLED=true
export HEALTH_CHECK_PATH="/up"
export HEALTH_CHECK_TIMEOUT=60

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================
export BACKUP_ENABLED=true
export MIGRATION_BACKUP_ENABLED=true
export BACKUP_RETENTION_DAYS=30

# ============================================================================
# IMAGE BACKUP CONFIGURATION
# ============================================================================
export SAVE_IMAGE_BACKUPS=true
export MAX_IMAGE_BACKUPS=20         # Keep last 20 versions for rollback

# ============================================================================
# AUTO CLEANUP
# ============================================================================
export AUTO_CLEANUP_ENABLED=true
export MAX_IMAGE_VERSIONS=20

# ============================================================================
# NGINX CONFIGURATION
# ============================================================================
export NGINX_UPSTREAM_NAME="${APP_NAME}_backend"

# ============================================================================
# PATHS (Auto-configured)
# ============================================================================
export APP_DIR="$HOME/apps/$APP_NAME"
export REPO_DIR="$APP_DIR/repo"
export ENV_FILE="$APP_DIR/.env.production"
export BACKUP_DIR="$APP_DIR/backups"
export LOG_DIR="$APP_DIR/logs"
export IMAGE_BACKUP_DIR="$APP_DIR/docker-images"

# ============================================================================
# EMAIL NOTIFICATION CONFIGURATION
# ============================================================================
# Email notifications for deployments (success/failure) via SendGrid API
# Centralized configuration is in DevOps/common/email-config.sh
export DEPLOYMENT_EMAIL_ENABLED=true
export DEPLOYMENT_EMAIL_FROM="biuro@webet.pl"
export DEPLOYMENT_EMAIL_TO="andrzej@webet.pl"

# SendGrid API Key (can also be set in email-config.sh or environment)
# export SENDGRID_API_KEY="SG.xxxxxxxxxxxxxxxxxxxx"


# ============================================================================
# ELASTICSEARCH CONFIGURATION
# ============================================================================
export ELASTICSEARCH_ENABLED=true
export ELASTICSEARCH_PROVIDER="${ELASTICSEARCH_PROVIDER:-aws}"  # aws or docker

# ============================================================================
# ERROR TRACKING CONFIGURATION
# ============================================================================
export ROLLBAR_ACCESS_TOKEN="${ROLLBAR_ACCESS_TOKEN:-}"  # Set via environment variable
