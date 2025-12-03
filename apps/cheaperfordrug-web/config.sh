#!/bin/bash

# Application Configuration for CheaperForDrug Web
# This is a Next.js frontend application

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="nextjs"
export APP_NAME="cheaperfordrug-web"
export APP_DISPLAY_NAME="CheaperForDrug Web"
export DOMAIN="taniejpolek.pl"
export DOMAIN_WWW="www.taniejpolek.pl"

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================
export REPO_URL="git@github.com:AndrzejJantos/cheaperfordrug-web.git"
export REPO_BRANCH="master"

# ============================================================================
# CONTAINER ARCHITECTURE
# ============================================================================
# Frontend doesn't need workers or schedulers (all handled by backend API)
export DEFAULT_SCALE=3              # 3 web containers for frontend
export WORKER_COUNT=0               # No workers needed
export SCHEDULER_ENABLED=false      # No scheduler needed

# Architecture note:
# - 3 web containers serve the Next.js frontend with load balancing
# - All API calls go to api-*.cheaperfordrug.com backend
# - No background processing needed in frontend

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================
export DOCKER_IMAGE_NAME="$APP_NAME"
export BASE_PORT=3055              # Ports 3055-3057 for web containers (host side)
export CONTAINER_PORT=3000          # Port inside container (Next.js uses 3000)

# ============================================================================
# DEPLOYMENT CONFIGURATION
# ============================================================================
export ZERO_DOWNTIME_ENABLED=true
export HEALTH_CHECK_PATH="/"
export HEALTH_CHECK_TIMEOUT=60

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================
export BACKUP_ENABLED=false         # No database backups (frontend only)
export MIGRATION_BACKUP_ENABLED=false

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
