#!/bin/bash

# Configuration for Node.js application template
# Location: /home/andrzej/DevOps/apps/<your-nodejs-app>/config.sh
# Copy this file and customize for your Node.js application

# Application identification
export APP_NAME="my-nodejs-app"
export APP_DISPLAY_NAME="My Node.js Application"

# Repository configuration
export REPO_URL="https://github.com/user/my-nodejs-app.git"
export REPO_BRANCH="main"

# Server paths
export DEPLOY_USER="andrzej"
export DEPLOY_HOME="/home/${DEPLOY_USER}"
export APP_BASE_DIR="${DEPLOY_HOME}/apps"
export APP_DIR="${APP_BASE_DIR}/${APP_NAME}"
export REPO_DIR="${APP_DIR}/repo"
export ENV_FILE="${APP_DIR}/.env.production"
export BACKUP_DIR="${APP_DIR}/backups"
export LOG_DIR="${APP_DIR}/logs"

# Node.js Feature Flags
# Set these based on your application's needs
export NEEDS_POSTGRES=true      # Does your app need PostgreSQL?
export NEEDS_REDIS=true          # Does your app need Redis?
export NEEDS_MAILGUN=false       # Does your app use Mailgun for emails?
export NEEDS_MIGRATIONS=true     # Does your app have database migrations?

# Database configuration (only if NEEDS_POSTGRES=true)
export DB_NAME="${APP_NAME//-/_}_production"
export DB_USER="postgres"
export DB_PASSWORD=""  # Leave empty for peer authentication

# Redis configuration (only if NEEDS_REDIS=true)
export REDIS_DB_NUMBER=5  # Use unique number per app (1-15)
export REDIS_URL="redis://localhost:6379/${REDIS_DB_NUMBER}"

# Mailgun configuration (only if NEEDS_MAILGUN=true)
export MAILGUN_API_KEY="your-mailgun-api-key"
export MAILGUN_DOMAIN="mg.example.com"
export MAILGUN_FROM_EMAIL="noreply@mg.example.com"
export NOTIFICATION_EMAIL="admin@example.com"

# Network configuration
export DOMAIN="myapp.example.com"
export BASE_PORT=3050      # Starting port for containers (must be unique!)
export PORT_RANGE_END=3059 # Ending port (supports 10 instances)
export DEFAULT_SCALE=2     # Default number of container instances

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
    "NODE_ENV=production"
    "API_KEY=your_api_key_here"
    "JWT_SECRET=your_jwt_secret_here"
    "CORS_ORIGIN=https://example.com"
)

# Health check configuration
export HEALTH_CHECK_PATH="/health"  # Node.js apps often use /health instead of /up
export HEALTH_CHECK_TIMEOUT=60
export HEALTH_CHECK_INTERVAL=2

# Backup configuration
export BACKUP_RETENTION_DAYS=30
export MAX_IMAGE_VERSIONS=3

# Deployment configuration
export MIGRATION_BACKUP_ENABLED=true   # Only matters if NEEDS_MIGRATIONS=true
export ZERO_DOWNTIME_ENABLED=true
export AUTO_CLEANUP_ENABLED=true
