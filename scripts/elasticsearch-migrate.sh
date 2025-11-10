#!/bin/bash
set -e

# Elasticsearch Production Migration Script
# This script reindexes all searchable models in production
# Run this after deploying Elasticsearch configuration changes
#
# Usage: ./elasticsearch-migrate.sh
# Location: /home/andrzej/DevOps/scripts/elasticsearch-migrate.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
source "$SCRIPT_DIR/../common/elasticsearch-check.sh"

APP_NAME="cheaperfordrug-api"
APP_DIR="$HOME/apps/$APP_NAME"
REPO_DIR="$APP_DIR/repo"
ENV_FILE="$APP_DIR/.env.production"

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log_header "Elasticsearch Production Migration"

# Check if application directory exists
if [ ! -d "$REPO_DIR" ]; then
    log_error "Application repository not found: $REPO_DIR"
    log_error "Please deploy the application first"
    exit 1
fi

# Check if environment file exists
if [ ! -f "$ENV_FILE" ]; then
    log_error "Environment file not found: $ENV_FILE"
    exit 1
fi

log_info "Loading environment variables..."
set -a
source "$ENV_FILE"
set +a

# ============================================================================
# VERIFY ELASTICSEARCH CONNECTION
# ============================================================================

log_header "Verifying Elasticsearch Connection"

if [ -z "$ELASTICSEARCH_URL" ]; then
    log_error "ELASTICSEARCH_URL is not set in $ENV_FILE"
    exit 1
fi

# Check connection
if [ -n "$ELASTICSEARCH_USERNAME" ] && [ -n "$ELASTICSEARCH_PASSWORD" ]; then
    display_elasticsearch_info "$ELASTICSEARCH_URL" "$ELASTICSEARCH_USERNAME" "$ELASTICSEARCH_PASSWORD"
    USE_AUTH=true
else
    display_elasticsearch_info "$ELASTICSEARCH_URL" "" ""
    USE_AUTH=false
fi

if [ $? -ne 0 ]; then
    log_error "Cannot proceed with migration - Elasticsearch is not accessible"
    exit 1
fi

# Check cluster health
if [ "$USE_AUTH" = true ]; then
    CLUSTER_HEALTH=$(get_elasticsearch_cluster_health "$ELASTICSEARCH_URL" "$ELASTICSEARCH_USERNAME" "$ELASTICSEARCH_PASSWORD")
else
    CLUSTER_HEALTH=$(get_elasticsearch_cluster_health "$ELASTICSEARCH_URL" "" "")
fi

if [ "$CLUSTER_HEALTH" = "red" ]; then
    log_error "Cluster health is RED - migration may fail"
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Migration cancelled"
        exit 0
    fi
fi

# ============================================================================
# RUN REINDEXING
# ============================================================================

log_header "Starting Reindexing Process"

log_warning "This will reindex all searchable models in production"
log_warning "The process may take several minutes depending on data volume"
echo ""
read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Migration cancelled"
    exit 0
fi

echo ""
log_info "Changing to application directory: $REPO_DIR"
cd "$REPO_DIR"

log_info "Running Elasticsearch reindex task..."
echo ""

# Run the Rails task
if bundle exec rails elasticsearch:reindex_production; then
    echo ""
    log_success "Reindexing completed successfully"

    # Show index status
    log_header "Current Index Status"
    bundle exec rails elasticsearch:status

    echo ""
    log_success "Migration completed successfully"
    echo ""
    log_info "Next Steps:"
    echo "  1. Test search functionality in the application"
    echo "  2. Monitor Elasticsearch performance metrics"
    echo "  3. Check application logs for any search errors"
    echo ""
else
    echo ""
    log_error "Reindexing failed"
    log_error "Please check the error messages above"
    echo ""
    log_info "Troubleshooting:"
    echo "  1. Verify Elasticsearch connection: ./scripts/elasticsearch-setup.sh"
    echo "  2. Check application logs: journalctl -u ${APP_NAME}-web@1 -f"
    echo "  3. Verify Rails console can connect: cd $REPO_DIR && bundle exec rails c"
    echo ""
    exit 1
fi
