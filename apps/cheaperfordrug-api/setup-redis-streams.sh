#!/bin/bash

# ==============================================================================
# REDIS STREAMS SETUP FOR CHEAPERFORDRUG-API
# ==============================================================================
# This script integrates Redis Streams configuration into the DevOps workflow
#
# Usage:
#   ./setup-redis-streams.sh          # Configure Redis Streams for API
#
# This script:
#   1. Sources the app configuration
#   2. Sets up Redis for Streams usage
#   3. Enables Redis Streams in the API environment
#   4. Provides deployment instructions
#
# Can be run:
#   - During initial API setup
#   - As a post-setup configuration step
#   - To enable Redis Streams on existing installation
# ==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source common utilities
source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/redis-setup.sh"

# Source app configuration
source "$SCRIPT_DIR/config.sh"

# ==============================================================================
# MAIN SETUP FLOW
# ==============================================================================

main() {
    echo ""
    echo "=============================================================================="
    echo "  Redis Streams Setup for ${APP_DISPLAY_NAME}"
    echo "=============================================================================="
    echo ""

    # Step 1: Verify prerequisites
    log_info "Step 1: Checking prerequisites..."

    if ! redis_check_installed; then
        log_error "Redis is not installed"
        log_info "Install Redis first by running:"
        log_info "  sudo apt-get update && sudo apt-get install redis-server"
        exit 1
    fi

    if ! redis_check_running; then
        log_error "Redis is not running"
        log_info "Start Redis with:"
        log_info "  sudo systemctl start redis-server"
        exit 1
    fi

    log_success "Redis is installed and running"
    echo ""

    # Step 2: Configure Redis for Streams
    log_info "Step 2: Configuring Redis for Streams..."

    if ! setup_redis_for_streams; then
        log_error "Failed to configure Redis"
        exit 1
    fi

    echo ""

    # Step 3: Check if app is set up
    log_info "Step 3: Checking API setup..."

    if [ ! -d "$APP_DIR" ]; then
        log_error "App directory not found: $APP_DIR"
        log_info "Run the main setup first:"
        log_info "  cd $SCRIPT_DIR && ./setup.sh"
        exit 1
    fi

    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file not found: $ENV_FILE"
        log_info "Run the main setup first:"
        log_info "  cd $SCRIPT_DIR && ./setup.sh"
        exit 1
    fi

    log_success "API is set up"
    echo ""

    # Step 4: Enable Redis Streams in environment
    log_info "Step 4: Enabling Redis Streams in API environment..."

    # Check if already enabled
    if grep -q "ENABLE_REDIS_STREAM_CONSUMERS=true" "$ENV_FILE"; then
        log_info "Redis Streams already enabled"
    else
        # Update the environment file
        if grep -q "ENABLE_REDIS_STREAM_CONSUMERS" "$ENV_FILE"; then
            # Update existing setting
            sed -i.bak "s/ENABLE_REDIS_STREAM_CONSUMERS=.*/ENABLE_REDIS_STREAM_CONSUMERS=true/" "$ENV_FILE"
            log_success "Updated ENABLE_REDIS_STREAM_CONSUMERS to true"
        else
            log_warning "Redis Streams configuration not found in $ENV_FILE"
            log_info "The configuration should be added automatically during deployment"
        fi
    fi

    echo ""

    # Step 5: Verify configuration
    log_info "Step 5: Verifying configuration..."

    local config_ok=true

    # Check Redis Streams URL
    if grep -q "REDIS_STREAMS_URL" "$ENV_FILE"; then
        local streams_url=$(grep "REDIS_STREAMS_URL" "$ENV_FILE" | cut -d= -f2)
        log_info "  Redis Streams URL: $streams_url"
    else
        log_warning "  Redis Streams URL not configured"
        config_ok=false
    fi

    # Check consumer count
    if grep -q "REDIS_STREAM_CONSUMER_COUNT" "$ENV_FILE"; then
        local consumer_count=$(grep "REDIS_STREAM_CONSUMER_COUNT" "$ENV_FILE" | cut -d= -f2)
        log_info "  Consumer count: $consumer_count"
    else
        log_warning "  Consumer count not configured"
        config_ok=false
    fi

    echo ""

    # Step 6: Show next steps
    echo ""
    echo "=============================================================================="
    echo "  Setup Complete!"
    echo "=============================================================================="
    echo ""

    if [ "$config_ok" = true ]; then
        log_success "Redis Streams is configured and ready"
    else
        log_warning "Some configuration may be missing"
        log_info "This will be added automatically during the next deployment"
    fi

    echo ""
    log_info "Next Steps:"
    echo ""
    echo "  1. Deploy the API to apply changes:"
    echo "     cd $SCRIPT_DIR && ./deploy.sh deploy"
    echo ""
    echo "  2. Verify Redis Streams consumers are running:"
    echo "     docker ps | grep scheduler"
    echo "     redis-cli -n 3 XINFO GROUPS cheaperfordrug:products:batch"
    echo ""
    echo "  3. Check health endpoint:"
    echo "     curl http://localhost:3000/admin/redis_streams/health"
    echo ""
    echo "  4. Monitor Redis Streams:"
    echo "     redis-cli -n 3 XLEN cheaperfordrug:products:batch"
    echo ""

    log_info "Configuration files:"
    echo "  - App config: $SCRIPT_DIR/config.sh"
    echo "  - Environment: $ENV_FILE"
    echo "  - Redis config: /etc/redis/redis.conf"
    echo ""

    log_success "Redis Streams setup complete!"
}

# Run main function
main "$@"
