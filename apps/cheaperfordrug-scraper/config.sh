#!/bin/bash

# Application Configuration for CheaperForDrug Scraper
# Manages VPN catalog scrapers and product update workers

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="scraper"
export APP_NAME="cheaperfordrug-scraper"
export APP_DISPLAY_NAME="CheaperForDrug Scraper (VPN + Product Workers)"

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================
export DOCKER_IMAGE_NAME="$APP_NAME"
export DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-latest}"

# ============================================================================
# SOURCE REPOSITORY
# ============================================================================
export SCRAPER_REPO_DIR="$HOME/apps/cheaperfordrug-scraper"
export SCRAPER_REPO_BRANCH="master"

# ============================================================================
# PATHS
# ============================================================================
export APP_DIR="$SCRAPER_REPO_DIR"
export LOG_DIR="$SCRAPER_REPO_DIR/logs"
