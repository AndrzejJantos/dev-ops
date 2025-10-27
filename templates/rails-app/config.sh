#!/bin/bash

# Application Configuration for [Your Rails App]
# This is a Rails API backend with full background processing capabilities

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="rails"
export APP_NAME="your-rails-app"         # Change this to your app name (use lowercase, hyphens)
export APP_DISPLAY_NAME="Your Rails App"  # Change this to your app display name
export DOMAIN="api.your-domain.com"      # Change this to your domain

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================
export REPO_URL="git@github.com:youruser/your-repo.git"  # Change this to your repository URL
export REPO_BRANCH="master"                               # Or "main" if that's your default branch

# ============================================================================
# CONTAINER ARCHITECTURE
# ============================================================================
# Rails API needs workers for background processing and scheduler for recurring tasks
export DEFAULT_SCALE=2              # Number of web containers (2-3 recommended)
export WORKER_COUNT=1               # Number of Sidekiq worker containers
export SCHEDULER_ENABLED=true       # Enable Clockwork scheduler for recurring tasks

# Architecture note:
# - Web containers handle API requests with load balancing
# - Worker processes background jobs (emails, data processing, external API calls)
# - Scheduler enqueues recurring tasks (cleanup, reports, notifications)

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================
export DOCKER_IMAGE_NAME="$APP_NAME"
export BASE_PORT=3020              # Starting port for containers (e.g., 3020, 3021, 3022)
export CONTAINER_PORT=3000          # Port inside container (consistent across Rails and Next.js)

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================
export DB_NAME="${APP_NAME//-/_}_production"  # Auto-generated from APP_NAME
export DB_USER="${APP_NAME//-/_}_user"        # Auto-generated from APP_NAME
export DB_HOST="localhost"
export DB_PORT="5432"

# ============================================================================
# REDIS CONFIGURATION
# ============================================================================
export REDIS_DB_NUMBER=0               # Dedicated Redis database (0-15)
export REDIS_URL="redis://localhost:6379/${REDIS_DB_NUMBER}"

# ============================================================================
# DEPLOYMENT CONFIGURATION
# ============================================================================
export ZERO_DOWNTIME_ENABLED=true
export HEALTH_CHECK_PATH="/up"         # Rails 8 health check endpoint
export HEALTH_CHECK_TIMEOUT=60         # Seconds to wait for container to be healthy

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================
export BACKUP_ENABLED=true             # Enable database backups
export MIGRATION_BACKUP_ENABLED=true   # Backup before migrations
export BACKUP_RETENTION_DAYS=30        # Keep backups for 30 days

# ============================================================================
# IMAGE BACKUP CONFIGURATION
# ============================================================================
export SAVE_IMAGE_BACKUPS=true         # Save Docker images for rollback
export MAX_IMAGE_BACKUPS=20            # Keep last 20 versions for rollback

# ============================================================================
# AUTO CLEANUP
# ============================================================================
export AUTO_CLEANUP_ENABLED=true
export MAX_IMAGE_VERSIONS=20           # Keep last 20 Docker image versions

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
# NOTIFICATION CONFIGURATION (Optional)
# ============================================================================
# Mailgun configuration for deployment notifications
export MAILGUN_API_KEY=""           # Set if you want email notifications
export MAILGUN_DOMAIN=""            # Set if you want email notifications
export NOTIFICATION_EMAIL=""        # Set if you want email notifications
