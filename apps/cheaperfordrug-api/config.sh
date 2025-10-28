#!/bin/bash

# Application Configuration for CheaperForDrug API
# This is a Rails API backend with full background processing capabilities

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="rails"
export APP_NAME="cheaperfordrug-api"
export APP_DISPLAY_NAME="CheaperForDrug API"

# API uses two subdomains (both point to same backend containers)
export DOMAIN_PUBLIC="api-public.cheaperfordrug.com"
export DOMAIN_INTERNAL="api-internal.cheaperfordrug.com"

# Primary domain for SSL setup (will include both subdomains)
export DOMAIN="api-public.cheaperfordrug.com"

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================
export REPO_URL="git@github.com:AndrzejJantos/cheaperfordrug-api.git"
export REPO_BRANCH="master"

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
export BASE_PORT=3020              # Ports 3020-3022 for web containers (host side)
export CONTAINER_PORT=3000          # Port inside container (consistent across Rails and Next.js)

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================
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
# NOTIFICATION CONFIGURATION
# ============================================================================
# Mailgun configuration for deployment notifications
export MAILGUN_API_KEY=""           # Set during setup
export MAILGUN_DOMAIN=""            # Set during setup
export NOTIFICATION_EMAIL=""        # Set during setup
