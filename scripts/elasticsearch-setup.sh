#!/bin/bash
set -e

# Elasticsearch Setup and Health Check Script
# This script verifies Elasticsearch connection, checks cluster health,
# and validates environment variables for CheaperForDrug API
#
# Usage: ./elasticsearch-setup.sh
# Location: /home/andrzej/DevOps/scripts/elasticsearch-setup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
source "$SCRIPT_DIR/../common/elasticsearch-check.sh"

APP_DIR="$HOME/apps/cheaperfordrug-api"
ENV_FILE="$APP_DIR/.env.production"

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log_header "Elasticsearch Setup and Health Check"

# Check if environment file exists
if [ ! -f "$ENV_FILE" ]; then
    log_error "Environment file not found: $ENV_FILE"
    log_error "Please create the environment file first"
    exit 1
fi

log_info "Loading environment variables from $ENV_FILE"
set -a
source "$ENV_FILE"
set +a

# ============================================================================
# VALIDATE REQUIRED ENVIRONMENT VARIABLES
# ============================================================================

log_info "Validating Elasticsearch configuration..."

if [ -z "$ELASTICSEARCH_URL" ]; then
    log_error "ELASTICSEARCH_URL is not set in $ENV_FILE"
    exit 1
fi

log_success "ELASTICSEARCH_URL is configured: $ELASTICSEARCH_URL"

# Check if authentication is configured
if [ -n "$ELASTICSEARCH_USERNAME" ] && [ -n "$ELASTICSEARCH_PASSWORD" ]; then
    log_success "Elasticsearch authentication is configured"
    USE_AUTH=true
else
    log_warning "Elasticsearch authentication is not configured (optional)"
    USE_AUTH=false
fi

# Check optional configuration
if [ -n "$ELASTICSEARCH_TIMEOUT" ]; then
    log_info "Elasticsearch timeout: ${ELASTICSEARCH_TIMEOUT}s"
fi

if [ -n "$ELASTICSEARCH_SEARCH_TIMEOUT" ]; then
    log_info "Elasticsearch search timeout: ${ELASTICSEARCH_SEARCH_TIMEOUT}s"
fi

# ============================================================================
# TEST ELASTICSEARCH CONNECTION
# ============================================================================

echo ""
log_header "Testing Elasticsearch Connection"

if [ "$USE_AUTH" = true ]; then
    display_elasticsearch_info "$ELASTICSEARCH_URL" "$ELASTICSEARCH_USERNAME" "$ELASTICSEARCH_PASSWORD"
else
    display_elasticsearch_info "$ELASTICSEARCH_URL" "" ""
fi

if [ $? -eq 0 ]; then
    log_success "Elasticsearch is ready for use"

    # Get cluster health
    if [ "$USE_AUTH" = true ]; then
        CLUSTER_HEALTH=$(get_elasticsearch_cluster_health "$ELASTICSEARCH_URL" "$ELASTICSEARCH_USERNAME" "$ELASTICSEARCH_PASSWORD")
    else
        CLUSTER_HEALTH=$(get_elasticsearch_cluster_health "$ELASTICSEARCH_URL" "" "")
    fi

    # Warning for non-green status
    if [ "$CLUSTER_HEALTH" != "green" ]; then
        log_warning "Cluster health is not 'green' - this may affect performance"
        log_warning "Current status: $CLUSTER_HEALTH"
    fi

    echo ""
    log_header "Next Steps"
    echo "1. Deploy your application: cd ~/DevOps && ./scripts/deploy-app.sh cheaperfordrug-api"
    echo "2. Reindex data in production: cd ~/DevOps && ./scripts/elasticsearch-migrate.sh"
    echo "3. Monitor Elasticsearch: Check AWS OpenSearch dashboard or use curl commands"
    echo ""

    exit 0
else
    log_error "Elasticsearch connection failed"
    log_error "Please verify:"
    echo "  1. ELASTICSEARCH_URL is correct"
    echo "  2. Network connectivity to Elasticsearch cluster"
    echo "  3. Authentication credentials (if required)"
    echo "  4. Security groups/firewall rules allow access"
    echo ""
    exit 1
fi
