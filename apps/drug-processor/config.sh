#!/bin/bash

# Application Configuration for Drug Processor
# This is a cron-based job runner (not a web application)

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="cron-job"
export APP_NAME="drug-processor"
export APP_DISPLAY_NAME="Drug Processor Pipeline"

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================
export DOCKER_IMAGE_NAME="$APP_NAME"
export DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-latest}"

# ============================================================================
# SOURCE REPOSITORIES
# ============================================================================
# Paths to the repositories that this app depends on (on the server)
# These are pulled/synced during deployment
export API_REPO_DIR="$HOME/apps/cheaperfordrug-api/repo"
export API_REPO_BRANCH="master"
export SCRAPER_REPO_DIR="$HOME/apps/cheaperfordrug-scraper/repo"
export SCRAPER_REPO_BRANCH="master"

# Source directory names in build context
export API_SOURCE_DIR="cheaperfordrug-api"
export SCRAPER_SOURCE_DIR="cheaperfordrug-scraper"

# ============================================================================
# BUILD CONFIGURATION
# ============================================================================
export BUILD_CONTEXT_DIR="$HOME/apps/$APP_NAME/build-context"
export DOCKERFILE_PATH="DevOps/apps/drug-processor/Dockerfile"

# ============================================================================
# CONTAINER CONFIGURATION
# ============================================================================
export CONTAINER_NAME="drug-processor"
export NETWORK_MODE="host"  # Same network as API for database access

# ============================================================================
# PATHS
# ============================================================================
export APP_DIR="$HOME/apps/$APP_NAME"
export ENV_FILE="$APP_DIR/.env"
export LOG_DIR="/var/log/drug-processor"
export IMAGE_BACKUP_DIR="$APP_DIR/docker-images"

# ============================================================================
# SCHEDULE
# ============================================================================
export CRON_SCHEDULE="0 2 * * 0,3,4,5,6"  # 2 AM on Wed, Thu, Fri, Sat, Sun

# ============================================================================
# EMAIL NOTIFICATION CONFIGURATION
# ============================================================================
export DEPLOYMENT_EMAIL_ENABLED=true
export DEPLOYMENT_EMAIL_FROM="biuro@webet.pl"
export DEPLOYMENT_EMAIL_TO="andrzej@webet.pl"

# ============================================================================
# IMAGE BACKUP CONFIGURATION
# ============================================================================
export SAVE_IMAGE_BACKUPS=true
export MAX_IMAGE_BACKUPS=5
