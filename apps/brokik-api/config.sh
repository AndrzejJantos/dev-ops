#!/bin/bash

# Application Configuration for Brokik API
# This is a Rails API backend with full background processing capabilities

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="rails"
export APP_NAME="brokik-api"
export APP_DISPLAY_NAME="Brokik API"

# API uses two subdomains (both point to same backend containers)
export DOMAIN_PUBLIC="api-public.brokik.com"
export DOMAIN_INTERNAL="api-internal.brokik.com"

# Primary domain for SSL setup (will include both subdomains)
export DOMAIN="api-public.brokik.com"

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================
export REPO_URL="git@github.com:AndrzejJantos/brokik-api.git"
export REPO_BRANCH="main"

# ============================================================================
# CONTAINER ARCHITECTURE
# ============================================================================
# API needs workers for background processing and scheduler for recurring tasks
export DEFAULT_SCALE=2              # 2 web containers for API
export WORKER_COUNT=1               # 1 worker container for background jobs
export SCHEDULER_ENABLED=true       # Enable Clockwork scheduler for recurring tasks
export WORKER_SHUTDOWN_TIMEOUT=90   # Seconds to wait for workers to finish jobs during deployment

# Architecture note:
# - 2 web containers handle API requests with load balancing
# - 1 worker processes background jobs (emails, data processing, external API calls)
# - 1 scheduler enqueues recurring tasks (cleanup, reports, notifications)

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================
export DOCKER_IMAGE_NAME="$APP_NAME"
export BASE_PORT=3040              # Ports 3040-3042 for web containers (host side)
export CONTAINER_PORT=3000          # Port inside container (consistent across Rails and Next.js)

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================
# Database connection settings
# Uses localhost because containers run in --network host mode
export DB_NAME="brokik_production"
export DB_USER="brokik_user"
export DB_HOST="localhost"
export DB_PORT="5432"

# ============================================================================
# REDIS CONFIGURATION
# ============================================================================
export REDIS_DB_NUMBER=3               # Dedicated Redis database for API
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
export BACKUP_RETENTION_DAYS=7
export BACKUP_MAX_COUNT=48

# ============================================================================
# IMAGE BACKUP CONFIGURATION
# ============================================================================
export SAVE_IMAGE_BACKUPS=true
export MAX_IMAGE_BACKUPS=5          # Keep last 5 versions for rollback

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
# ERROR TRACKING CONFIGURATION
# ============================================================================
export ROLLBAR_ACCESS_TOKEN="${ROLLBAR_ACCESS_TOKEN:-}"  # Set via environment variable

# ============================================================================
# CDN CONFIGURATION
# ============================================================================
# Enable CDN for Active Storage files (images, uploads, etc.)
export CDN_ENABLED=true
export CDN_DOMAIN="cdn.webet.pl"

# CDN notes:
# - When enabled, setup script will automatically deploy CDN configuration
# - CDN serves Active Storage files via nginx (faster, reduced app server load)
# - Domain must have DNS configured and SSL certificate obtained
# - Storage path: /var/storage/${APP_NAME}/active_storage
