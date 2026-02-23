#!/bin/bash

# Disaster Recovery Configuration Example
# Copy this file to disaster-recovery-config.sh and customize for your environment

# ==============================================================================
# SYSTEM CONFIGURATION
# ==============================================================================

# User to run deployments (usually your main user account)
RECOVERY_USER="andrzej"

# Home directory for the recovery user
RECOVERY_HOME="/home/andrzej"

# DevOps repository URL
DEVOPS_REPO_URL="git@github.com:AndrzejJantos/DevOps.git"

# DevOps repository branch
DEVOPS_REPO_BRANCH="master"

# ==============================================================================
# RECOVERY OPTIONS
# ==============================================================================

# Install system dependencies (Docker, Nginx, PostgreSQL, Redis, etc.)
INSTALL_DEPENDENCIES=true

# Setup SSL certificates during recovery
SETUP_SSL=true

# ==============================================================================
# APPLICATIONS TO DEPLOY
# ==============================================================================

# List all applications to setup and deploy
# These must match directory names in DevOps/apps/
APPS_TO_DEPLOY=(
    "cheaperfordrug-api"
    "cheaperfordrug-web"
)

# ==============================================================================
# APPLICATION-SPECIFIC NOTES
# ==============================================================================

# After running disaster recovery, you'll need to:
#
# 1. Configure environment variables for each app:
#    nano ~/apps/cheaperfordrug-api/.env.production
#    nano ~/apps/cheaperfordrug-web/.env.production
#
# 2. For Rails apps, you may need to run migrations:
#    cd ~/DevOps/apps/cheaperfordrug-api
#    ./deploy.sh deploy
#
# 3. For database restoration (if recovering from backup):
#    cd ~/apps/cheaperfordrug-api
#    ./restore.sh <backup-file>
#
# 4. Verify DNS records are pointing to the new server
#
# 5. Test all applications:
#    curl https://api-public.cheaperfordrug.com/up
#    curl https://premiera.taniejpolek.pl
