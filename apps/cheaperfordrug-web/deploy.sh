#!/bin/bash

# CheaperForDrug Web Deployment Script
# Domain: premiera.taniejpolek.pl
# Type: Next.js Frontend Application

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG="$SCRIPT_DIR/config.sh"

# Source common configuration and utilities
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/docker-utils.sh"

# Load application-specific configuration
if [ -f "$APP_CONFIG" ]; then
    source "$APP_CONFIG"
    log_success "Environment loaded from $APP_CONFIG"
else
    log_error "Configuration file not found: $APP_CONFIG"
    exit 1
fi

# Node.js/Next.js specific deployment functions

# Function: Pull latest code from repository
pull_code() {
    log_info "Pulling latest code from repository..."
    cd "$REPO_DIR"

    # Get current commit hash before pull
    local old_commit=$(git rev-parse HEAD)

    git fetch origin "$REPO_BRANCH"
    git reset --hard origin/"$REPO_BRANCH"

    local new_commit=$(git rev-parse HEAD)

    if [ "$old_commit" = "$new_commit" ]; then
        log_info "No new changes detected"
    else
        log_success "Updated from ${old_commit:0:7} to ${new_commit:0:7}"
    fi

    # Export commit for use in notifications
    export CURRENT_COMMIT="$new_commit"
    return 0
}

# Function: Build Next.js Docker image
build_image() {
    local image_tag="$1"

    log_info "Building Docker image with tag: ${image_tag}"

    # Ensure Dockerfile from DevOps template is used
    if [ -f "${DEVOPS_DIR}/common/nextjs/Dockerfile.template" ]; then
        log_info "Copying Dockerfile from DevOps template..."
        cp "${DEVOPS_DIR}/common/nextjs/Dockerfile.template" "${REPO_DIR}/Dockerfile"
        cp "${DEVOPS_DIR}/common/nextjs/.dockerignore.template" "${REPO_DIR}/.dockerignore"
    fi

    # Copy .env.production for Docker build
    log_info "Creating temporary .env.production file for Docker build..."
    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "${REPO_DIR}/.env.production"
        log_info "Copied environment file for Docker build"
    else
        log_error "Environment file not found: $ENV_FILE"
        return 1
    fi

    # Build Docker image
    build_docker_image "$DOCKER_IMAGE_NAME" "$REPO_DIR" "$image_tag"

    # Remove temporary .env.production after build
    rm -f "${REPO_DIR}/.env.production"
    log_info "Removed temporary build environment file"

    if [ $? -ne 0 ]; then
        log_error "Docker build failed"
        return 1
    fi

    # Tag as latest
    docker tag "${DOCKER_IMAGE_NAME}:${image_tag}" "${DOCKER_IMAGE_NAME}:latest"

    log_success "Docker image built and tagged successfully"

    # Save image as tar file backup if enabled
    if [ "${SAVE_IMAGE_BACKUPS:-false}" = "true" ] && [ -n "${IMAGE_BACKUP_DIR:-}" ]; then
        save_docker_image "$DOCKER_IMAGE_NAME" "$image_tag" "$IMAGE_BACKUP_DIR"
        cleanup_old_image_backups "$IMAGE_BACKUP_DIR" "${MAX_IMAGE_BACKUPS:-5}"
    fi

    return 0
}

# Function: Deploy fresh (no existing containers)
deploy_fresh() {
    local scale="$1"
    local image_tag="$2"

    log_info "No existing containers found, deploying fresh with ${scale} container(s)"

    # Start web containers
    for i in $(seq 1 $scale); do
        local port=$((BASE_PORT + i - 1))
        local container_name="${APP_NAME}_web_${i}"

        start_container "$container_name" "${DOCKER_IMAGE_NAME}:${image_tag}" "$port" "$ENV_FILE"

        if [ $? -ne 0 ]; then
            log_error "Failed to start container ${container_name}"
            return 1
        fi

        # Wait for container to be ready
        check_container_health "$container_name" "$HEALTH_CHECK_TIMEOUT"

        if [ $? -ne 0 ]; then
            log_error "Container ${container_name} failed health check"
            return 1
        fi
    done

    log_success "Fresh deployment completed successfully"
    return 0
}

# Function: Deploy with zero downtime (rolling restart)
deploy_rolling() {
    local scale="$1"
    local image_tag="$2"

    log_info "Running containers detected, performing zero-downtime deployment"

    # Perform rolling restart for web containers
    if [ "$ZERO_DOWNTIME_ENABLED" = "true" ]; then
        rolling_restart "$APP_NAME" "${DOCKER_IMAGE_NAME}:${image_tag}" "$ENV_FILE" "$BASE_PORT" "$scale"

        if [ $? -ne 0 ]; then
            log_error "Rolling restart failed"
            return 1
        fi

        log_success "Zero-downtime deployment completed successfully"
    fi

    return 0
}

# Function: Main deployment workflow
deploy_application() {
    local scale="$1"
    local image_tag="$(date +%Y%m%d_%H%M%S)"

    log_info "Starting deployment of ${APP_DISPLAY_NAME}"

    # Pull latest code
    pull_code || return 1

    # Build Docker image
    build_image "$image_tag" || return 1

    # Check if any containers are running
    local current_count=$(get_container_count "$APP_NAME")

    if [ $current_count -eq 0 ]; then
        # No containers running - use provided scale for fresh deployment
        deploy_fresh "$scale" "$image_tag" || return 1
        actual_scale="$scale"
    else
        # Containers already running - restart ALL of them
        log_info "Found ${current_count} running container(s), will restart all of them"
        deploy_rolling "$current_count" "$image_tag" || return 1
        actual_scale="$current_count"
    fi

    # Clean up old images
    if [ "$AUTO_CLEANUP_ENABLED" = "true" ]; then
        cleanup_old_images "$DOCKER_IMAGE_NAME" "$MAX_IMAGE_VERSIONS"
    fi

    # Log deployment
    echo "[$(date)] Deployed ${DOCKER_IMAGE_NAME}:${image_tag} with scale=${actual_scale}" >> "${LOG_DIR}/deployments.log"

    log_success "Deployment completed successfully!"

    # Display summary
    display_deployment_summary "$actual_scale" "$image_tag"

    return 0
}

# Function: Display deployment summary
display_deployment_summary() {
    local scale="$1"
    local image_tag="$2"

    echo ""
    echo "================================================================================"
    echo "                     DEPLOYMENT SUMMARY"
    echo "================================================================================"
    echo ""
    echo "APPLICATION:"
    echo "  Name: ${APP_DISPLAY_NAME}"
    echo "  App ID: ${APP_NAME}"
    echo "  Git Commit: ${CURRENT_COMMIT:0:7}"
    echo "  Image Tag: ${image_tag}"
    echo ""
    echo "DEPLOYMENT STATUS:"
    echo "  Status: SUCCESS ✓"
    echo "  Timestamp: $(date)"
    echo ""
    echo "AVAILABILITY:"
    echo "  Primary URL: https://${DOMAIN}"
    if [[ "$DOMAIN" != www.* ]]; then
        echo "  Alternative: https://www.${DOMAIN}"
    fi
    echo ""
    echo "WEB CONTAINERS:"
    local containers=($(get_running_containers "$APP_NAME"))
    echo "  Count: ${#containers[@]} instances"
    echo "  Containers:"
    for container in "${containers[@]}"; do
        local port=$(docker port "$container" 3000 2>/dev/null | cut -d ':' -f2)
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
        echo "    - ${container} (port ${port}, status: ${status})"
    done
    echo ""
    echo "IMAGE BACKUPS:"
    if [ -d "$IMAGE_BACKUP_DIR" ]; then
        local backup_count=$(ls -1 "${IMAGE_BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        echo "  Available: ${backup_count} backups"
        echo "  Location: ${IMAGE_BACKUP_DIR}"
        echo "  Latest: ${APP_NAME}_${image_tag}.tar.gz"
    else
        echo "  Status: Disabled"
    fi
    echo ""
    echo "USEFUL COMMANDS:"
    echo "  View logs:        docker logs ${APP_NAME}_web_1 -f"
    echo "  Check health:     curl https://${DOMAIN}"
    echo "  Scale up:         ./deploy.sh scale $((scale + 1))"
    echo "  Scale down:       ./deploy.sh scale $((scale - 1))"
    echo "  Restart:          ./deploy.sh restart"
    echo "  Stop:             ./deploy.sh stop"
    echo ""
    echo "================================================================================"
    echo ""
}

# Function: Restart application
restart_application() {
    local scale="$1"

    log_info "Restarting ${APP_DISPLAY_NAME} with scale=${scale}"

    # Get current image
    local current_image="${DOCKER_IMAGE_NAME}:latest"

    # Check if image exists
    if ! docker image inspect "$current_image" > /dev/null 2>&1; then
        log_error "Image ${current_image} not found. Please run deploy first."
        return 1
    fi

    # Perform rolling restart
    rolling_restart "$APP_NAME" "$current_image" "$ENV_FILE" "$BASE_PORT" "$scale"

    if [ $? -ne 0 ]; then
        log_error "Restart failed"
        return 1
    fi

    log_success "Restart completed successfully"
    return 0
}

# Function: Scale application
scale_application_web() {
    local target_scale="$1"

    log_info "Scaling ${APP_DISPLAY_NAME} to ${target_scale} instances"

    # Get current image
    local current_image="${DOCKER_IMAGE_NAME}:latest"

    # Check if image exists
    if ! docker image inspect "$current_image" > /dev/null 2>&1; then
        log_error "Image ${current_image} not found. Please run deploy first."
        return 1
    fi

    local old_scale=$(get_container_count "$APP_NAME")

    # Perform scaling
    scale_application "$APP_NAME" "$current_image" "$ENV_FILE" "$BASE_PORT" "$target_scale"

    if [ $? -ne 0 ]; then
        log_error "Scaling failed"
        return 1
    fi

    log_success "Scaling completed successfully (${old_scale} -> ${target_scale})"
    return 0
}

# Function: Stop application
stop_application() {
    log_info "Stopping all ${APP_NAME} containers"

    local containers=($(docker ps --filter "name=${APP_NAME}" --format "{{.Names}}" 2>/dev/null))

    if [ ${#containers[@]} -eq 0 ]; then
        log_info "No running containers found"
        return 0
    fi

    log_info "Found ${#containers[@]} running containers"

    for container in "${containers[@]}"; do
        stop_container "$container" 30
    done

    log_success "All containers stopped successfully"
    return 0
}

# Function: Show status
handle_status() {
    log_info "Checking status of ${APP_DISPLAY_NAME} containers"

    local all_containers=($(docker ps -a --filter "name=${APP_NAME}" --format "{{.Names}}" 2>/dev/null))

    if [ ${#all_containers[@]} -eq 0 ]; then
        log_warning "No containers found for ${APP_NAME}"
        echo ""
        echo "To deploy the application, run:"
        echo "  ./deploy.sh deploy"
        exit 0
    fi

    # Print table header
    echo ""
    printf "%-35s %-15s %-20s %-20s %-15s\n" "CONTAINER NAME" "STATUS" "PORTS" "STARTED" "UPTIME"
    echo "---------------------------------------------------------------------------------------------------"

    for container in "${all_containers[@]}"; do
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
        local ports=$(docker port "$container" 2>/dev/null | grep -oP '\d+:\d+' | head -1 || echo "-")

        if [ "$status" = "running" ]; then
            local started=$(docker inspect -f '{{.State.StartedAt}}' "$container" 2>/dev/null)
            local now_ts=$(date +%s)
            local started_ts=$(date -d "$started" +%s 2>/dev/null || echo "$now_ts")
            local seconds=$(( now_ts - started_ts ))

            # Format start time
            started_time=$(date -d "$started" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "-")

            # Format uptime
            if [ $seconds -lt 0 ] || [ $seconds -gt 31536000 ]; then
                running_time="?"
            elif [ $seconds -lt 60 ]; then
                running_time="${seconds}s"
            elif [ $seconds -lt 3600 ]; then
                running_time="$(($seconds / 60))m"
            elif [ $seconds -lt 86400 ]; then
                running_time="$(($seconds / 3600))h $(($seconds % 3600 / 60))m"
            else
                running_time="$(($seconds / 86400))d $(($seconds % 86400 / 3600))h"
            fi

            printf "%-35s \033[32m%-15s\033[0m %-20s %-20s %-15s\n" "$container" "$status" "$ports" "$started_time" "$running_time"
        else
            printf "%-35s \033[31m%-15s\033[0m %-20s %-20s %-15s\n" "$container" "$status" "$ports" "-" "-"
        fi
    done

    echo ""
    echo "Summary:"
    echo "  Running containers: $(docker ps --filter "name=${APP_NAME}" --format "{{.Names}}" | wc -l | tr -d ' ')"
    echo ""
    echo "Useful commands:"
    echo "  View logs:     docker logs ${APP_NAME}_web_1 -f"
    echo "  Check health:  curl https://${DOMAIN}"
    echo "  Scale:         ./deploy.sh scale <number>"
    echo "  Deploy:        ./deploy.sh deploy"
    echo ""

    exit 0
}

# Update nginx upstream configuration when scaling
update_nginx_upstream() {
    local new_scale="$1"

    log_info "Updating Nginx upstream configuration for ${new_scale} web containers..."

    local nginx_template="$SCRIPT_DIR/nginx.conf.template"
    local nginx_config="/etc/nginx/sites-available/$APP_NAME"

    # Backup current config
    sudo cp "$nginx_config" "${nginx_config}.backup" 2>/dev/null || true

    # Generate new upstream servers list
    local UPSTREAM_SERVERS=""
    for i in $(seq 1 $new_scale); do
        local PORT=$((BASE_PORT + i - 1))
        UPSTREAM_SERVERS="${UPSTREAM_SERVERS}    server localhost:${PORT} max_fails=3 fail_timeout=30s;\n"
    done

    # Remove trailing newline
    UPSTREAM_SERVERS=$(echo -e "$UPSTREAM_SERVERS" | sed '$ s/\\n$//')

    # Generate nginx config from template
    cat "$nginx_template" | \
        sed "s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g" | \
        sed "s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|g" | \
        sed "s|{{DOMAIN}}|${DOMAIN}|g" | \
        sed "s|{{APP_NAME}}|${APP_NAME}|g" | \
        sudo tee "$nginx_config" > /dev/null

    # Test nginx configuration
    if sudo nginx -t 2>&1 | grep -q "successful"; then
        sudo systemctl reload nginx
        log_success "Nginx configuration updated successfully"
        log_info "Nginx now routing to ${new_scale} containers (ports ${BASE_PORT}-$((BASE_PORT + new_scale - 1)))"
        return 0
    else
        log_error "Nginx configuration test failed, restoring backup"
        sudo mv "${nginx_config}.backup" "$nginx_config"
        sudo systemctl reload nginx
        return 1
    fi
}

# Handle commands
case "${1:-help}" in
    deploy)
        deploy_application "$DEFAULT_SCALE"
        ;;
    restart)
        local current_count=$(get_container_count "$APP_NAME")
        if [ $current_count -eq 0 ]; then
            log_error "No containers running. Use 'deploy' instead of 'restart'"
            exit 1
        fi
        restart_application "$current_count"
        ;;
    stop)
        stop_application
        ;;
    scale)
        if [ -z "$2" ]; then
            log_error "Usage: $0 scale <number>"
            exit 1
        fi
        if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 10 ]; then
            log_error "Scale must be a number between 1 and 10"
            exit 1
        fi
        scale_application_web "$2"
        update_nginx_upstream "$2"
        if [ $? -eq 0 ]; then
            log_success "Scaled to $2 containers successfully"
            exit 0
        fi
        ;;
    status)
        handle_status
        ;;
    logs)
        local container="${2:-${APP_NAME}_web_1}"
        log_info "Showing logs for $container (Ctrl+C to exit)"
        docker logs -f "$container"
        ;;
    ssl-setup)
        log_info "Setting up SSL certificates for ${DOMAIN}"
        sudo certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN"
        ;;
    help|*)
        echo "CheaperForDrug Web Deployment Script"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  deploy              Pull latest code, build, and deploy application"
        echo "  restart             Restart all running containers with current image"
        echo "  stop                Stop all containers"
        echo "  scale <N>           Scale web containers to N instances (1-10)"
        echo "  status              Show status of all containers"
        echo "  logs [container]    Show logs (default: ${APP_NAME}_web_1)"
        echo "  ssl-setup           Setup SSL certificates with Let's Encrypt"
        echo "  help                Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 deploy           # Deploy latest code"
        echo "  $0 scale 3          # Scale to 3 web containers"
        echo "  $0 status           # Show container status"
        echo "  $0 logs web_2       # Show logs for web_2"
        echo ""
        exit 0
        ;;
esac
