#!/bin/bash

# CheaperForDrug API Setup Script
# This script initializes the deployment environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common utilities
source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/docker-utils.sh"

# Source Rails-specific setup functions
source "$DEVOPS_DIR/common/rails/setup.sh"
source "$DEVOPS_DIR/common/rails/setup-helpers.sh"

# Load app-specific configuration
APP_CONFIG_DIR="$SCRIPT_DIR"
source "$APP_CONFIG_DIR/config.sh"

# ============================================================================
# PRE-SETUP HOOKS
# ============================================================================
# Override or extend functions here if needed

pre_setup_hook() {
    log_info "Running pre-setup validations for ${APP_DISPLAY_NAME}..."

    # API-specific validation can go here
    # Example: Check for required API keys, validate domain, etc.

    return 0
}

# ============================================================================
# POST-SETUP HOOKS
# ============================================================================

post_setup_hook() {
    log_info "Running post-setup tasks for ${APP_DISPLAY_NAME}..."

    # Any API-specific post-setup tasks can go here
    # Example: Initialize search index, warm up cache, etc.

    return 0
}

# ============================================================================
# MAIN SETUP EXECUTION
# ============================================================================

main() {
    log_info "Starting setup for ${APP_DISPLAY_NAME}"
    log_info "Domain: ${DOMAIN}"

    # Run pre-setup hook
    pre_setup_hook || exit 1

    # Run common Rails setup workflow
    # This handles: directories, repo, database, env, Docker, nginx, SSL, cron, etc.
    rails_common_setup_workflow || exit 1

    # Run post-setup hook
    post_setup_hook || exit 1

    # Display completion message
    log_success "Setup completed successfully!"
    echo ""
    cat "$APP_DIR/deployment-info.txt"
}

# Run main function
main "$@"
