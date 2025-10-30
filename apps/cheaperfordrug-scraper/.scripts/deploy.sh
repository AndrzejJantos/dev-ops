#!/bin/bash

# CheaperForDrug Scraper Deployment Script
# Handles deployment of multi-container scraper system with NordVPN

set -e

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common utilities
source "$DEVOPS_DIR/common/utils.sh"

# Load app configuration
APP_CONFIG="$SCRIPT_DIR/config.sh"
if [ -f "$APP_CONFIG" ]; then
    source "$APP_CONFIG"
    log_success "Configuration loaded from $APP_CONFIG"
else
    log_error "Configuration file not found: $APP_CONFIG"
    exit 1
fi

# ============================================================================
# Deployment Functions
# ============================================================================

# Pull latest code from repository
pull_latest_code() {
    log_info "Pulling latest code from repository..."

    cd "$REPO_DIR"

    # Fetch latest changes
    git fetch origin "$REPO_BRANCH"

    # Get current and latest commit hashes
    CURRENT_COMMIT=$(git rev-parse HEAD)
    LATEST_COMMIT=$(git rev-parse origin/"$REPO_BRANCH")

    if [ "$CURRENT_COMMIT" = "$LATEST_COMMIT" ]; then
        log_info "Already at latest commit: $CURRENT_COMMIT"
        return 0
    fi

    log_info "Current commit: $CURRENT_COMMIT"
    log_info "Latest commit:  $LATEST_COMMIT"

    # Pull changes
    git pull origin "$REPO_BRANCH"

    log_success "Code updated to latest version"
}

# Build Docker image
build_docker_image() {
    log_info "Building Docker image..."

    cd "$REPO_DIR"

    # Generate image tag with timestamp
    IMAGE_TAG="$(date +%Y%m%d-%H%M%S)"
    export IMAGE_TAG

    # Copy docker scripts to repo for build context
    log_info "Copying Docker scripts to build context..."
    cp -r "$SCRIPT_DIR/../.docker/"* "$REPO_DIR/"

    # Build image
    log_info "Building image: ${DOCKER_IMAGE_NAME}:${IMAGE_TAG}"

    if docker build \
        -t "${DOCKER_IMAGE_NAME}:${IMAGE_TAG}" \
        -t "${DOCKER_IMAGE_NAME}:latest" \
        -f "$SCRIPT_DIR/../.docker/Dockerfile" \
        .; then
        log_success "Docker image built successfully"
    else
        log_error "Failed to build Docker image"
        return 1
    fi

    # Save image backup if enabled
    if [ "$SAVE_IMAGE_BACKUPS" = "true" ]; then
        save_image_backup
    fi
}

# Save Docker image backup
save_image_backup() {
    log_info "Saving Docker image backup..."

    mkdir -p "$IMAGE_BACKUP_DIR"

    local backup_file="$IMAGE_BACKUP_DIR/${DOCKER_IMAGE_NAME}_${IMAGE_TAG}.tar.gz"

    docker save "${DOCKER_IMAGE_NAME}:${IMAGE_TAG}" | gzip > "$backup_file"

    log_success "Image backup saved: $backup_file"

    # Cleanup old backups
    cleanup_old_image_backups
}

# Cleanup old image backups
cleanup_old_image_backups() {
    if [ -z "$MAX_IMAGE_BACKUPS" ]; then
        return 0
    fi

    log_info "Cleaning up old image backups (keeping last $MAX_IMAGE_BACKUPS)..."

    cd "$IMAGE_BACKUP_DIR"

    local backup_count=$(ls -1 "${DOCKER_IMAGE_NAME}"_*.tar.gz 2>/dev/null | wc -l)

    if [ "$backup_count" -gt "$MAX_IMAGE_BACKUPS" ]; then
        ls -1t "${DOCKER_IMAGE_NAME}"_*.tar.gz | tail -n +$((MAX_IMAGE_BACKUPS + 1)) | xargs rm -f
        log_success "Removed old backups"
    fi
}

# Stop containers
stop_containers() {
    log_info "Stopping containers..."

    cd "$REPO_DIR"

    if docker-compose -f "$SCRIPT_DIR/../docker-compose.yml" \
        --env-file "$ENV_FILE" \
        down --timeout 30; then
        log_success "Containers stopped"
    else
        log_warning "Some containers may not have stopped cleanly"
    fi
}

# Start containers
start_containers() {
    log_info "Starting containers..."

    cd "$REPO_DIR"

    # Export required variables for docker-compose
    export DOCKER_IMAGE_NAME
    export IMAGE_TAG
    export APP_DIR
    export DEVOPS_DIR

    # Start with docker-compose
    if docker-compose -f "$SCRIPT_DIR/../docker-compose.yml" \
        --env-file "$ENV_FILE" \
        up -d; then
        log_success "Containers started"
    else
        log_error "Failed to start containers"
        return 1
    fi
}

# Check container health
check_container_health() {
    local container_name="$1"
    local max_attempts="${2:-30}"
    local attempt=0

    log_info "Checking health of container: $container_name"

    while [ $attempt -lt $max_attempts ]; do
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "unknown")

        case "$health_status" in
            healthy)
                log_success "Container $container_name is healthy"
                return 0
                ;;
            unhealthy)
                log_error "Container $container_name is unhealthy"
                return 1
                ;;
            starting|unknown)
                log_info "Container $container_name is starting... (attempt $((attempt + 1))/$max_attempts)"
                ;;
        esac

        attempt=$((attempt + 1))
        sleep 5
    done

    log_error "Container $container_name health check timeout"
    return 1
}

# Wait for all containers to be healthy
wait_for_containers() {
    log_info "Waiting for all containers to become healthy..."

    local containers=(
        "$CONTAINER_POLAND"
        "$CONTAINER_GERMANY"
        "$CONTAINER_CZECH"
    )

    local all_healthy=true

    for container in "${containers[@]}"; do
        if ! check_container_health "$container" 30; then
            log_error "Container $container failed health check"
            all_healthy=false
        fi
    done

    if [ "$all_healthy" = true ]; then
        log_success "All containers are healthy"
        return 0
    else
        log_error "Some containers are not healthy"
        return 1
    fi
}

# Show container status
show_status() {
    log_info "Container Status:"
    echo ""

    docker-compose -f "$SCRIPT_DIR/../docker-compose.yml" ps

    echo ""
    log_info "Container Health:"
    echo ""

    for container in "$CONTAINER_POLAND" "$CONTAINER_GERMANY" "$CONTAINER_CZECH"; do
        if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no healthcheck")
            local status=$(docker inspect --format='{{.State.Status}}' "$container")
            echo "  $container: $status ($health)"
        else
            echo "  $container: not running"
        fi
    done

    echo ""
}

# Show logs for all containers
show_logs() {
    local follow="${1:-false}"

    if [ "$follow" = "true" ]; then
        log_info "Following logs for all containers (Ctrl+C to stop)..."
        docker-compose -f "$SCRIPT_DIR/../docker-compose.yml" logs -f
    else
        log_info "Recent logs for all containers:"
        docker-compose -f "$SCRIPT_DIR/../docker-compose.yml" logs --tail=50
    fi
}

# Main deployment function
deploy() {
    log_info "================================================================"
    log_info "Starting deployment of $APP_DISPLAY_NAME"
    log_info "================================================================"

    # Pull latest code
    pull_latest_code

    # Build Docker image
    build_docker_image

    # Stop existing containers
    stop_containers

    # Start new containers
    start_containers

    # Wait for containers to be healthy
    if wait_for_containers; then
        log_success "================================================================"
        log_success "Deployment completed successfully!"
        log_success "================================================================"

        show_status

        # Prompt to setup cron jobs
        setup_cron_prompt
    else
        log_error "================================================================"
        log_error "Deployment completed with errors"
        log_error "================================================================"

        show_logs false
        exit 1
    fi
}

# Prompt to setup cron jobs
setup_cron_prompt() {
    echo ""
    log_info "================================================================"
    log_info "Cron Job Setup"
    log_info "================================================================"
    echo ""

    # Check if cron is already installed
    if crontab -l 2>/dev/null | grep -q "cheaperfordrug-scraper"; then
        log_info "Cron jobs are already installed"
        echo ""
        crontab -l 2>/dev/null | grep "cheaperfordrug-scraper"
        echo ""
        log_info "To reinstall, run: npm run cron:setup"
    else
        log_warning "Cron jobs are NOT installed"
        echo ""
        log_info "Scrapers can be scheduled to run automatically every Monday and Thursday at 7:00 AM"
        echo ""
        read -p "Would you like to setup cron jobs now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [[ -f "$SCRIPT_DIR/setup-cron.sh" ]]; then
                bash "$SCRIPT_DIR/setup-cron.sh" --install
            else
                log_warning "setup-cron.sh not found, skipping automatic setup"
                log_info "Run manually: npm run cron:setup"
            fi
        else
            log_info "Skipping cron setup"
            log_info "To setup later, run: npm run cron:setup"
        fi
    fi
    echo ""
}

# ============================================================================
# Command Handler
# ============================================================================

handle_command() {
    case "${1:-deploy}" in
        deploy)
            deploy
            ;;
        build)
            pull_latest_code
            build_docker_image
            ;;
        start)
            start_containers
            wait_for_containers
            show_status
            ;;
        stop)
            stop_containers
            ;;
        restart)
            stop_containers
            start_containers
            wait_for_containers
            show_status
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "${2:-false}"
            ;;
        health)
            wait_for_containers
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  deploy    - Full deployment (pull, build, restart)"
            echo "  build     - Build Docker image only"
            echo "  start     - Start containers"
            echo "  stop      - Stop containers"
            echo "  restart   - Restart containers"
            echo "  status    - Show container status"
            echo "  logs      - Show recent logs"
            echo "  logs true - Follow logs"
            echo "  health    - Check container health"
            echo ""
            exit 1
            ;;
    esac
}

# Run command handler
handle_command "$@"
