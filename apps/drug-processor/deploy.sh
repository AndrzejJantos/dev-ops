#!/bin/bash

# Drug Processor Deployment Script
# This uses the common cron-job deployment infrastructure
#
# Usage:
#   ./deploy.sh deploy    # Build and deploy
#   ./deploy.sh build     # Build image only
#   ./deploy.sh start     # Start container
#   ./deploy.sh stop      # Stop container
#   ./deploy.sh status    # Show status
#   ./deploy.sh logs      # View logs
#   ./deploy.sh test      # Run pipeline manually

set -e

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors (in case utils.sh not loaded)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load common utilities if available
if [ -f "$DEVOPS_DIR/common/utils.sh" ]; then
    source "$DEVOPS_DIR/common/utils.sh"
fi

# Load app configuration
APP_CONFIG="$SCRIPT_DIR/config.sh"
if [ -f "$APP_CONFIG" ]; then
    source "$APP_CONFIG"
else
    log_error "Configuration file not found: $APP_CONFIG"
    exit 1
fi

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

check_requirements() {
    log_info "Checking requirements..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed"
        exit 1
    fi

    log_success "Requirements OK"
}

pull_and_sync_repos() {
    log_info "=== Syncing Source Repositories ==="

    # Create build context directory
    mkdir -p "$BUILD_CONTEXT_DIR"

    # Sync API repository
    if [ -d "$API_REPO_DIR" ]; then
        log_info "Pulling API code from ${API_REPO_DIR}..."
        cd "$API_REPO_DIR"
        if [ -d ".git" ]; then
            git fetch origin "${API_REPO_BRANCH:-master}" 2>/dev/null || true
            git reset --hard origin/"${API_REPO_BRANCH:-master}" 2>/dev/null || true
        fi

        log_info "Copying API to build context..."
        rm -rf "$BUILD_CONTEXT_DIR/$API_SOURCE_DIR"
        cp -r "$API_REPO_DIR" "$BUILD_CONTEXT_DIR/$API_SOURCE_DIR"
        log_success "API synced"
    else
        log_error "API repository not found: $API_REPO_DIR"
        return 1
    fi

    # Sync Scraper repository
    if [ -d "$SCRAPER_REPO_DIR" ]; then
        log_info "Pulling Scraper code from ${SCRAPER_REPO_DIR}..."
        cd "$SCRAPER_REPO_DIR"
        if [ -d ".git" ]; then
            git fetch origin "${SCRAPER_REPO_BRANCH:-master}" 2>/dev/null || true
            git reset --hard origin/"${SCRAPER_REPO_BRANCH:-master}" 2>/dev/null || true
        fi

        log_info "Copying Scraper to build context..."
        rm -rf "$BUILD_CONTEXT_DIR/$SCRAPER_SOURCE_DIR"
        cp -r "$SCRAPER_REPO_DIR" "$BUILD_CONTEXT_DIR/$SCRAPER_SOURCE_DIR"
        log_success "Scraper synced"
    else
        log_error "Scraper repository not found: $SCRAPER_REPO_DIR"
        return 1
    fi

    # Copy DevOps app configuration to build context
    log_info "Copying DevOps configuration to build context..."
    rm -rf "$BUILD_CONTEXT_DIR/DevOps"
    mkdir -p "$BUILD_CONTEXT_DIR/DevOps/apps"
    cp -r "$SCRIPT_DIR" "$BUILD_CONTEXT_DIR/DevOps/apps/$APP_NAME"

    log_success "All repositories synced to build context"
    return 0
}

build_image() {
    log_info "=== Building Docker Image ==="

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local image_tag="${DOCKER_IMAGE_NAME}:${timestamp}"
    local image_latest="${DOCKER_IMAGE_NAME}:latest"

    log_info "Building from: $BUILD_CONTEXT_DIR"
    log_info "Dockerfile: $DOCKERFILE_PATH"
    log_info "Image: $image_tag"

    cd "$BUILD_CONTEXT_DIR"

    if docker build \
        -f "$DOCKERFILE_PATH" \
        -t "$image_tag" \
        -t "$image_latest" \
        .; then
        log_success "Image built: $image_tag"

        # Save backup if enabled
        if [ "${SAVE_IMAGE_BACKUPS:-false}" = "true" ]; then
            save_image_backup "$image_tag"
        fi

        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

save_image_backup() {
    local image_tag="$1"
    mkdir -p "$IMAGE_BACKUP_DIR"

    local backup_file="$IMAGE_BACKUP_DIR/${DOCKER_IMAGE_NAME}_$(date +%Y%m%d_%H%M%S).tar"

    log_info "Saving image backup to: $backup_file"
    if docker save "$image_tag" -o "$backup_file"; then
        log_success "Image backup saved"

        # Cleanup old backups
        local max_backups="${MAX_IMAGE_BACKUPS:-5}"
        local backup_count=$(ls -1 "$IMAGE_BACKUP_DIR"/*.tar 2>/dev/null | wc -l)

        if [ "$backup_count" -gt "$max_backups" ]; then
            local to_delete=$((backup_count - max_backups))
            log_info "Cleaning up $to_delete old backup(s)..."
            ls -1t "$IMAGE_BACKUP_DIR"/*.tar | tail -n "$to_delete" | xargs rm -f
        fi
    else
        log_warning "Failed to save image backup"
    fi
}

start_container() {
    log_info "=== Starting Container ==="

    # Check env file
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file not found: $ENV_FILE"
        log_info "Create it from template or copy from existing deployment"
        return 1
    fi

    # Stop existing container if running
    if docker ps -q -f "name=${CONTAINER_NAME}" | grep -q .; then
        log_info "Stopping existing container..."
        docker stop "$CONTAINER_NAME" || true
        docker rm "$CONTAINER_NAME" || true
    fi

    # Remove dead container if exists
    if docker ps -aq -f "name=${CONTAINER_NAME}" | grep -q .; then
        docker rm "$CONTAINER_NAME" || true
    fi

    # Create log directory
    sudo mkdir -p "$LOG_DIR"
    sudo chown -R $(whoami):$(whoami) "$LOG_DIR" 2>/dev/null || true

    # Start container
    log_info "Starting container: $CONTAINER_NAME"
    docker run -d \
        --name "$CONTAINER_NAME" \
        --network host \
        --restart unless-stopped \
        --env-file "$ENV_FILE" \
        -v "$LOG_DIR:/var/log/drug-processor" \
        "${DOCKER_IMAGE_NAME}:latest"

    # Wait and check health
    sleep 5

    if docker ps -q -f "name=${CONTAINER_NAME}" | grep -q .; then
        log_success "Container started successfully"
        docker logs --tail 20 "$CONTAINER_NAME"
        return 0
    else
        log_error "Container failed to start"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -50
        return 1
    fi
}

stop_container() {
    log_info "=== Stopping Container ==="

    if docker ps -q -f "name=${CONTAINER_NAME}" | grep -q .; then
        docker stop "$CONTAINER_NAME"
        docker rm "$CONTAINER_NAME" || true
        log_success "Container stopped"
    else
        log_info "Container not running"
    fi
}

show_status() {
    echo ""
    echo "========================================"
    echo -e "  ${BLUE}Drug Processor Status${NC}"
    echo "========================================"
    echo ""

    # Container status
    echo "Container:"
    if docker ps -q -f "name=${CONTAINER_NAME}" | grep -q .; then
        docker ps -f "name=${CONTAINER_NAME}" --format "  Status: {{.Status}}"
        docker ps -f "name=${CONTAINER_NAME}" --format "  Image: {{.Image}}"
        docker ps -f "name=${CONTAINER_NAME}" --format "  Created: {{.CreatedAt}}"
    else
        echo "  Not running"
    fi

    # Schedule
    echo ""
    echo "Schedule:"
    echo "  Cron: $CRON_SCHEDULE"
    echo "  (2 AM on Wed, Thu, Fri, Sat, Sun)"

    # Logs
    echo ""
    echo "Recent logs:"
    if [ -f "$LOG_DIR/cron.log" ]; then
        tail -5 "$LOG_DIR/cron.log" 2>/dev/null | sed 's/^/  /'
    else
        echo "  No logs found"
    fi

    echo ""
}

show_logs() {
    if docker ps -q -f "name=${CONTAINER_NAME}" | grep -q .; then
        docker logs -f "$CONTAINER_NAME"
    else
        log_error "Container not running"
        if [ -f "$LOG_DIR/cron.log" ]; then
            log_info "Showing cron.log instead..."
            tail -100 "$LOG_DIR/cron.log"
        fi
    fi
}

run_test() {
    log_info "=== Running Manual Test ==="

    if ! docker ps -q -f "name=${CONTAINER_NAME}" | grep -q .; then
        log_error "Container not running. Start it first: ./deploy.sh start"
        return 1
    fi

    log_info "Executing pipeline manually..."
    docker exec -it "$CONTAINER_NAME" /app/scripts/run-drug-processor.sh
}

do_deploy() {
    log_info "=== Deploying Drug Processor ==="
    echo ""

    check_requirements

    # Sync source repositories
    if ! pull_and_sync_repos; then
        log_error "Failed to sync repositories"
        exit 1
    fi

    # Build image
    if ! build_image; then
        log_error "Build failed"
        exit 1
    fi

    # Start container
    if ! start_container; then
        log_error "Failed to start container"
        exit 1
    fi

    echo ""
    log_success "=== Deployment Complete ==="
    echo ""
    show_status
}

show_usage() {
    echo ""
    echo "Drug Processor Deployment"
    echo "========================="
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  deploy    Build and deploy (pulls latest code, builds image, starts container)"
    echo "  build     Build Docker image only (syncs repos and builds)"
    echo "  start     Start container (uses existing image)"
    echo "  stop      Stop container"
    echo "  status    Show status"
    echo "  logs      View logs (follow mode)"
    echo "  test      Run pipeline manually"
    echo "  help      Show this help"
    echo ""
    echo "Quick deploy from DevOps:"
    echo "  cd ~/DevOps && ./scripts/deploy.sh drug-processor"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

case "${1:-help}" in
    deploy)
        do_deploy
        ;;
    build)
        check_requirements
        pull_and_sync_repos
        build_image
        ;;
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    test)
        run_test
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
