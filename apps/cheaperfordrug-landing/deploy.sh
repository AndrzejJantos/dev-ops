#!/bin/bash

# CheaperForDrug Landing Deployment Script
# This is a thin wrapper that uses the common deployment infrastructure

set -e

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common utilities
source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/docker-utils.sh"

# Load app configuration
APP_CONFIG="$SCRIPT_DIR/config.sh"
if [ -f "$APP_CONFIG" ]; then
    source "$APP_CONFIG"
    log_success "Environment loaded from $APP_CONFIG"
else
    log_error "Configuration file not found: $APP_CONFIG"
    exit 1
fi

# Load generic deployment script
source "$DEVOPS_DIR/common/deploy-app.sh"

# Handle command-line arguments
handle_deploy_command "$@"
