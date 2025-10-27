#!/bin/bash

# Application Configuration for [Your Next.js App]
# This is a Next.js frontend application

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="nextjs"
export APP_NAME="your-nextjs-app"        # Change this to your app name (use lowercase, hyphens)
export APP_DISPLAY_NAME="Your Next.js App"  # Change this to your app display name
export DOMAIN="your-domain.com"          # Change this to your domain

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================
export REPO_URL="git@github.com:youruser/your-repo.git"  # Change this to your repository URL
export REPO_BRANCH="master"                               # Or "main" if that's your default branch

# ============================================================================
# CONTAINER ARCHITECTURE
# ============================================================================
# Frontend doesn't need workers or schedulers (all handled by backend API)
export DEFAULT_SCALE=3              # Number of web containers (3 recommended for HA)
export WORKER_COUNT=0               # No workers needed for frontend
export SCHEDULER_ENABLED=false      # No scheduler needed for frontend

# Architecture note:
# - Multiple web containers serve the Next.js frontend with load balancing
# - All API calls go to your backend API
# - No background processing needed in frontend

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================
export DOCKER_IMAGE_NAME="$APP_NAME"
export BASE_PORT=3030              # Starting port for containers (e.g., 3030, 3031, 3032)
export CONTAINER_PORT=3000          # Port inside container (Next.js uses 3000)

# ============================================================================
# DEPLOYMENT CONFIGURATION
# ============================================================================
export ZERO_DOWNTIME_ENABLED=true
export HEALTH_CHECK_PATH="/"        # Health check endpoint
export HEALTH_CHECK_TIMEOUT=60      # Seconds to wait for container to be healthy

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================
export BACKUP_ENABLED=false         # No database backups (frontend only)
export MIGRATION_BACKUP_ENABLED=false

# ============================================================================
# IMAGE BACKUP CONFIGURATION
# ============================================================================
export SAVE_IMAGE_BACKUPS=true      # Save Docker images for rollback
export MAX_IMAGE_BACKUPS=20         # Keep last 20 versions for rollback

# ============================================================================
# AUTO CLEANUP
# ============================================================================
export AUTO_CLEANUP_ENABLED=true
export MAX_IMAGE_VERSIONS=20        # Keep last 20 Docker image versions

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
# NOTIFICATION CONFIGURATION (Optional)
# ============================================================================
# Mailgun configuration for deployment notifications
export MAILGUN_API_KEY=""           # Set if you want email notifications
export MAILGUN_DOMAIN=""            # Set if you want email notifications
export NOTIFICATION_EMAIL=""        # Set if you want email notifications
