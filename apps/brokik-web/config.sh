#!/bin/bash

# Application Configuration for Brokik Web
# This is a Next.js frontend application

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="nextjs"
export APP_NAME="brokik-web"
export APP_DISPLAY_NAME="Brokik Web"
export DOMAIN="www.brokik.com"

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================
export REPO_URL="git@github.com:AndrzejJantos/brokik-web.git"
export REPO_BRANCH="main"

# ============================================================================
# CONTAINER ARCHITECTURE
# ============================================================================
# Frontend doesn't need workers or schedulers (all handled by backend API)
export DEFAULT_SCALE=3              # 3 web containers for frontend
export WORKER_COUNT=0               # No workers needed
export SCHEDULER_ENABLED=false      # No scheduler needed

# Architecture note:
# - 3 web containers serve the Next.js frontend with load balancing
# - All API calls go to api-*.brokik.com backend
# - No background processing needed in frontend

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================
export DOCKER_IMAGE_NAME="$APP_NAME"
export BASE_PORT=3050              # Ports 3050-3052 for web containers (host side)
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
# NOTIFICATION CONFIGURATION
# ============================================================================
# Mailgun configuration for deployment notifications
export MAILGUN_API_KEY=""           # Set during setup
export MAILGUN_DOMAIN=""            # Set during setup
export NOTIFICATION_EMAIL=""        # Set during setup

# ============================================================================
# CDN CONFIGURATION
# ============================================================================
# CDN is typically not needed for frontend apps (static assets served by Next.js)
# Enable only if you need to serve media files through nginx CDN
export CDN_ENABLED=false
export CDN_DOMAIN=""

# CDN notes:
# - Frontend apps usually don't need CDN (Next.js serves static assets efficiently)
# - Enable only if you have specific media hosting requirements
# - Most projects should leave this disabled and use the backend API's CDN
