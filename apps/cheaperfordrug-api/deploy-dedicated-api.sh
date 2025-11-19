#!/bin/bash

# Dedicated API Containers Deployment Script
# Manages 4 specialized API containers for CheaperForDrug scraper system
#
# Containers:
# - api-product-read (port 4201) - Read-only product queries
# - api-product-write (port 4202) + sidekiq worker - Product updates
# - api-normalizer (port 4203) - Drug name normalization
# - api-scraper (port 4204) + sidekiq worker - Full scraping operations

set -euo pipefail

# Get script directory and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load utilities
source "$DEVOPS_DIR/common/utils.sh"

# Load main app configuration for shared settings
APP_CONFIG="$SCRIPT_DIR/config.sh"
if [ -f "$APP_CONFIG" ]; then
    source "$APP_CONFIG"
else
    log_error "Configuration file not found: $APP_CONFIG"
    exit 1
fi

# Docker Compose file for dedicated API containers
COMPOSE_FILE="$SCRIPT_DIR/docker-compose-dedicated-api.yml"

# Check if compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "Docker Compose file not found: $COMPOSE_FILE"
    exit 1
fi

# Export required environment variables for docker-compose
export LOG_DIR="${LOG_DIR:-$HOME/apps/$APP_NAME/logs}"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Function: Check if main API image exists
check_image_exists() {
    local image_name="${DOCKER_IMAGE_NAME}:latest"

    if ! docker image inspect "$image_name" > /dev/null 2>&1; then
        log_error "Docker image not found: $image_name"
        log_error "Please deploy the main API first: cd $SCRIPT_DIR && ./deploy.sh deploy"
        return 1
    fi

    log_success "Using existing image: $image_name"
    return 0
}

# Function: Check container health
check_container_health() {
    local container_name="$1"
    local port="$2"
    local max_attempts=30
    local attempt=0

    log_info "Checking health of $container_name on port $port..."

    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "http://localhost:${port}/up" > /dev/null 2>&1; then
            log_success "$container_name is healthy"
            return 0
        fi

        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            sleep 2
        fi
    done

    log_error "$container_name failed health check after ${max_attempts} attempts"
    return 1
}

# Function: Show container status
show_status() {
    log_header "Dedicated API Containers Status"

    local containers=(
        "cheaperfordrug-api-product-read:4201"
        "cheaperfordrug-api-product-write:4202"
        "cheaperfordrug-api-product-write-sidekiq:worker"
        "cheaperfordrug-api-normalizer:4203"
        "cheaperfordrug-api-scraper:4204"
        "cheaperfordrug-api-scraper-sidekiq:worker"
        "cheaperfordrug-api-scheduler:scheduler"
    )

    echo ""
    printf "%-45s %-15s %-10s %-15s\n" "CONTAINER" "STATUS" "PORT" "UPTIME"
    echo "---------------------------------------------------------------------------------"

    for item in "${containers[@]}"; do
        IFS=':' read -r container_name port <<< "$item"

        if docker ps --filter "name=^${container_name}$" --format "{{.Names}}" | grep -q "^${container_name}$"; then
            local status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
            local started=$(docker inspect -f '{{.State.StartedAt}}' "$container_name" 2>/dev/null)
            local now_ts=$(date +%s)
            local started_ts=$(date -d "$started" +%s 2>/dev/null || echo "$now_ts")
            local seconds=$(( now_ts - started_ts ))

            # Format uptime
            if [ $seconds -lt 60 ]; then
                uptime="${seconds}s"
            elif [ $seconds -lt 3600 ]; then
                uptime="$(($seconds / 60))m"
            elif [ $seconds -lt 86400 ]; then
                uptime="$(($seconds / 3600))h $(($seconds % 3600 / 60))m"
            else
                uptime="$(($seconds / 86400))d $(($seconds % 86400 / 3600))h"
            fi

            if [ "$status" = "running" ]; then
                printf "%-45s \033[32m%-15s\033[0m %-10s %-15s\n" "$container_name" "$status" "$port" "$uptime"
            else
                printf "%-45s \033[31m%-15s\033[0m %-10s %-15s\n" "$container_name" "$status" "$port" "-"
            fi
        else
            printf "%-45s \033[90m%-15s\033[0m %-10s %-15s\n" "$container_name" "not found" "$port" "-"
        fi
    done

    echo ""
    echo "Container Endpoints:"
    echo "  - Product Read:    http://localhost:4201/up"
    echo "  - Product Write:   http://localhost:4202/up"
    echo "  - Normalizer:      http://localhost:4203/up"
    echo "  - Scraper:         http://localhost:4204/up"
    echo ""
    echo "Useful Commands:"
    echo "  Start all:         $0 start"
    echo "  Stop all:          $0 stop"
    echo "  Restart all:       $0 restart"
    echo "  View logs:         $0 logs [container-name]"
    echo "  Health check:      $0 health"
    echo ""
}

# Function: Deploy/start containers
start_containers() {
    log_header "Starting Dedicated API Containers"

    # Check if main API image exists
    if ! check_image_exists; then
        exit 1
    fi

    # Display scaling configuration
    log_info "Scaling configuration from config.sh:"
    log_info "  - Product Read:      ${SCRAPER_PRODUCT_READ_SCALE} instances"
    log_info "  - Product Write:     ${SCRAPER_PRODUCT_WRITE_SCALE} instance(s) + worker"
    log_info "  - Normalizer:        ${SCRAPER_NORMALIZER_SCALE} instances"
    log_info "  - General Scraper:   ${SCRAPER_GENERAL_SCALE} instances + worker"

    # Start containers using docker compose with scaling
    log_info "Starting containers with docker compose..."
    cd "$SCRIPT_DIR"
    docker compose -f "$COMPOSE_FILE" up -d \
        --scale api-product-read=${SCRAPER_PRODUCT_READ_SCALE} \
        --scale api-product-write=${SCRAPER_PRODUCT_WRITE_SCALE} \
        --scale api-normalizer=${SCRAPER_NORMALIZER_SCALE} \
        --scale api-scraper=${SCRAPER_GENERAL_SCALE}

    if [ $? -ne 0 ]; then
        log_error "Failed to start containers"
        exit 1
    fi

    log_success "Containers started successfully"

    # Wait a bit for containers to initialize
    sleep 5

    # Health check for web containers
    log_info "Performing health checks..."

    local health_failed=false

    if ! check_container_health "cheaperfordrug-api-product-read" 4201; then
        health_failed=true
    fi

    if ! check_container_health "cheaperfordrug-api-product-write" 4202; then
        health_failed=true
    fi

    if ! check_container_health "cheaperfordrug-api-normalizer" 4203; then
        health_failed=true
    fi

    if ! check_container_health "cheaperfordrug-api-scraper" 4204; then
        health_failed=true
    fi

    # Check if workers are running
    if ! docker ps --filter "name=cheaperfordrug-api-product-write-sidekiq" --format "{{.Names}}" | grep -q "sidekiq"; then
        log_warning "Product write worker may not be running"
        health_failed=true
    else
        log_success "Product write worker is running"
    fi

    if ! docker ps --filter "name=cheaperfordrug-api-scraper-sidekiq" --format "{{.Names}}" | grep -q "sidekiq"; then
        log_warning "Scraper worker may not be running"
        health_failed=true
    else
        log_success "Scraper worker is running"
    fi

    # Check if scheduler is running
    if ! docker ps --filter "name=cheaperfordrug-api-scheduler" --format "{{.Names}}" | grep -q "scheduler"; then
        log_warning "Scheduler may not be running"
        health_failed=true
    else
        log_success "Scheduler is running"
    fi

    if [ "$health_failed" = true ]; then
        log_warning "Some containers failed health checks. Check logs with: $0 logs"
        echo ""
        show_status
        exit 1
    fi

    log_success "All containers are healthy!"
    echo ""
    show_status
}

# Function: Stop containers
stop_containers() {
    log_header "Stopping Dedicated API Containers"

    cd "$SCRIPT_DIR"
    docker compose -f "$COMPOSE_FILE" down

    if [ $? -eq 0 ]; then
        log_success "Containers stopped successfully"
    else
        log_error "Failed to stop containers"
        exit 1
    fi
}

# Function: Restart containers
restart_containers() {
    log_header "Restarting Dedicated API Containers"

    stop_containers
    sleep 2
    start_containers
}

# Function: View logs
view_logs() {
    local container="${1:-}"

    if [ -z "$container" ]; then
        log_info "Showing logs for all containers (Ctrl+C to exit)"
        cd "$SCRIPT_DIR"
        docker compose -f "$COMPOSE_FILE" logs -f
    else
        # Try to match container name
        local full_name=""
        if [[ "$container" == "product-read" ]]; then
            full_name="cheaperfordrug-api-product-read"
        elif [[ "$container" == "product-write" ]]; then
            full_name="cheaperfordrug-api-product-write"
        elif [[ "$container" == "product-write-sidekiq" ]] || [[ "$container" == "product-write-worker" ]]; then
            full_name="cheaperfordrug-api-product-write-sidekiq"
        elif [[ "$container" == "normalizer" ]]; then
            full_name="cheaperfordrug-api-normalizer"
        elif [[ "$container" == "scraper" ]]; then
            full_name="cheaperfordrug-api-scraper"
        elif [[ "$container" == "scraper-sidekiq" ]] || [[ "$container" == "scraper-worker" ]]; then
            full_name="cheaperfordrug-api-scraper-sidekiq"
        elif [[ "$container" == "scheduler" ]]; then
            full_name="cheaperfordrug-api-scheduler"
        else
            full_name="$container"
        fi

        log_info "Showing logs for $full_name (Ctrl+C to exit)"
        docker logs -f "$full_name"
    fi
}

# Function: Health check all containers
health_check() {
    log_header "Health Check for Dedicated API Containers"

    local all_healthy=true

    echo ""
    echo "Web Containers:"

    for port in 4201 4202 4203 4204; do
        local name=""
        case $port in
            4201) name="Product Read" ;;
            4202) name="Product Write" ;;
            4203) name="Normalizer" ;;
            4204) name="Scraper" ;;
        esac

        printf "  %-20s (port %d): " "$name" "$port"
        if curl -sf "http://localhost:${port}/up" > /dev/null 2>&1; then
            echo -e "\033[32mHealthy\033[0m"
        else
            echo -e "\033[31mUnhealthy\033[0m"
            all_healthy=false
        fi
    done

    echo ""
    echo "Worker Containers:"

    for worker in "cheaperfordrug-api-product-write-sidekiq:Product Write Worker" "cheaperfordrug-api-scraper-sidekiq:Scraper Worker"; do
        IFS=':' read -r container_name display_name <<< "$worker"
        printf "  %-20s: " "$display_name"

        if docker ps --filter "name=^${container_name}$" --format "{{.Names}}" | grep -q "^${container_name}$"; then
            local status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
            if [ "$status" = "running" ]; then
                echo -e "\033[32mRunning\033[0m"
            else
                echo -e "\033[31m$status\033[0m"
                all_healthy=false
            fi
        else
            echo -e "\033[31mNot found\033[0m"
            all_healthy=false
        fi
    done

    echo ""
    echo "Scheduler Container:"

    local scheduler_container="cheaperfordrug-api-scheduler"
    printf "  %-20s: " "Scheduler"

    if docker ps --filter "name=^${scheduler_container}$" --format "{{.Names}}" | grep -q "^${scheduler_container}$"; then
        local status=$(docker inspect -f '{{.State.Status}}' "$scheduler_container" 2>/dev/null)
        if [ "$status" = "running" ]; then
            echo -e "\033[32mRunning\033[0m"
        else
            echo -e "\033[31m$status\033[0m"
            all_healthy=false
        fi
    else
        echo -e "\033[31mNot found\033[0m"
        all_healthy=false
    fi

    echo ""
    if [ "$all_healthy" = true ]; then
        log_success "All containers are healthy"
        exit 0
    else
        log_error "Some containers are unhealthy"
        exit 1
    fi
}

# Function: Pull latest image from main API deployment
pull_latest() {
    log_header "Pulling Latest Image"

    log_info "The dedicated API containers use the same image as the main API"
    log_info "To update, deploy the main API first: cd $SCRIPT_DIR && ./deploy.sh deploy"
    log_info "Then restart these containers: $0 restart"

    check_image_exists
}

# ==============================================================================
# COMMAND HANDLER
# ==============================================================================

handle_command() {
    local command="${1:-status}"

    case "$command" in
        start|up)
            start_containers
            ;;
        stop|down)
            stop_containers
            ;;
        restart)
            restart_containers
            ;;
        status)
            show_status
            ;;
        logs)
            view_logs "${2:-}"
            ;;
        health)
            health_check
            ;;
        pull)
            pull_latest
            ;;
        help|*)
            echo "Dedicated API Containers Management Script"
            echo ""
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "Commands:"
            echo "  start               Start all dedicated API containers"
            echo "  stop                Stop all dedicated API containers"
            echo "  restart             Restart all dedicated API containers"
            echo "  status              Show status of all containers"
            echo "  logs [container]    Show logs (all or specific container)"
            echo "  health              Check health of all containers"
            echo "  pull                Check for latest image"
            echo "  help                Show this help message"
            echo ""
            echo "Container Shortcuts for logs:"
            echo "  product-read                API Product Read container"
            echo "  product-write               API Product Write container"
            echo "  product-write-sidekiq       API Product Write worker"
            echo "  normalizer                  API Normalizer container"
            echo "  scraper                     API Scraper container"
            echo "  scraper-sidekiq             API Scraper worker"
            echo "  scheduler                   Clockwork Scheduler (stale lock cleanup)"
            echo ""
            echo "Examples:"
            echo "  $0 start                    # Start all containers"
            echo "  $0 stop                     # Stop all containers"
            echo "  $0 status                   # Show container status"
            echo "  $0 logs product-read        # Show logs for product-read"
            echo "  $0 logs                     # Show logs for all containers"
            echo "  $0 health                   # Check health of all containers"
            echo ""
            echo "Notes:"
            echo "  - These containers use the main cheaperfordrug-api:latest image"
            echo "  - Deploy main API first: ./deploy.sh deploy"
            echo "  - Then start dedicated containers: $0 start"
            echo ""
            exit 0
            ;;
    esac
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

handle_command "$@"
