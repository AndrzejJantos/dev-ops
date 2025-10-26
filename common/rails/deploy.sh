#!/bin/bash

# Rails-specific deployment functions
# Location: /home/andrzej/DevOps/common/rails/deploy.sh
# This file should be sourced by app-specific deploy.sh scripts

# This file provides Rails-specific deployment functionality that can be:
# 1. Used as-is by sourcing it
# 2. Overridden by defining functions with the same name AFTER sourcing
# 3. Extended with pre/post hooks

# Function: Pull latest code from repository
rails_pull_code() {
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

# Function: Build Rails Docker image
rails_build_image() {
    local image_tag="$1"

    log_info "Building Docker image with tag: ${image_tag}"

    # Ensure Dockerfile from DevOps template is used (in case git pull overwrote it)
    if [ -f "${DEVOPS_DIR}/common/rails/Dockerfile.template" ]; then
        log_info "Copying Dockerfile from DevOps template..."
        cp "${DEVOPS_DIR}/common/rails/Dockerfile.template" "${REPO_DIR}/Dockerfile"
        cp "${DEVOPS_DIR}/common/rails/.dockerignore.template" "${REPO_DIR}/.dockerignore"
    fi

    build_docker_image "$DOCKER_IMAGE_NAME" "$REPO_DIR" "$image_tag"

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

        # Cleanup old image backups
        cleanup_old_image_backups "$IMAGE_BACKUP_DIR" "${MAX_IMAGE_BACKUPS:-5}"
    fi

    return 0
}

# Function: Check for pending Rails migrations
rails_check_pending_migrations() {
    local test_container="$1"

    log_info "Checking for pending migrations..."

    if check_pending_migrations "$test_container"; then
        log_info "Pending migrations detected"
        return 0  # Migrations are pending
    else
        log_info "No pending migrations"
        return 1  # No migrations pending
    fi
}

# Function: Run Rails migrations with backup
rails_run_migrations_with_backup() {
    local test_container="$1"

    log_info "Running migrations with database backup..."

    # Backup database before migrations
    backup_database "$DB_NAME" "$BACKUP_DIR"

    # Run migrations
    run_migrations "$test_container"

    if [ $? -ne 0 ]; then
        log_error "Migrations failed"
        return 1
    fi

    log_success "Migrations completed successfully"
    return 0
}

# Function: Deploy Rails application (fresh deployment - no existing containers)
rails_deploy_fresh() {
    local scale="$1"
    local image_tag="$2"

    log_info "No running containers found, starting fresh deployment"

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

    # Run migrations after first container is up
    if [ "$MIGRATION_BACKUP_ENABLED" = "true" ]; then
        log_info "Running database migrations..."
        run_migrations "${APP_NAME}_web_1"
    fi

    # Start worker containers if configured
    local worker_count="${WORKER_COUNT:-0}"
    if [ $worker_count -gt 0 ]; then
        log_info "Starting ${worker_count} worker container(s)..."
        for i in $(seq 1 $worker_count); do
            local worker_name="${APP_NAME}_worker_${i}"
            start_worker_container "$worker_name" "${DOCKER_IMAGE_NAME}:${image_tag}" "$ENV_FILE"

            if [ $? -ne 0 ]; then
                log_error "Failed to start worker ${worker_name}"
                return 1
            fi
        done
        log_success "Worker containers started successfully"
    fi

    log_success "Fresh deployment completed successfully"
    return 0
}

# Function: Deploy Rails application with zero downtime (rolling restart)
rails_deploy_rolling() {
    local scale="$1"
    local image_tag="$2"

    log_info "Running containers detected, performing zero-downtime deployment"

    # Create a test container to check migrations
    local test_container="${APP_NAME}_migration_check"

    if [ "$MIGRATION_BACKUP_ENABLED" = "true" ]; then
        docker run -d \
            --name "$test_container" \
            --env-file "$ENV_FILE" \
            "${DOCKER_IMAGE_NAME}:${image_tag}" \
            sleep infinity

        sleep 5

        # Check if migrations are needed
        if rails_check_pending_migrations "$test_container"; then
            rails_run_migrations_with_backup "$test_container"

            if [ $? -ne 0 ]; then
                docker rm -f "$test_container"
                return 1
            fi
        fi

        docker rm -f "$test_container"
    fi

    # Perform rolling restart for web containers
    if [ "$ZERO_DOWNTIME_ENABLED" = "true" ]; then
        rolling_restart "$APP_NAME" "${DOCKER_IMAGE_NAME}:${image_tag}" "$ENV_FILE" "$BASE_PORT" "$scale"

        if [ $? -ne 0 ]; then
            log_error "Rolling restart failed"
            return 1
        fi

        log_success "Zero-downtime deployment completed successfully"
    fi

    # Restart worker containers if configured
    local worker_count="${WORKER_COUNT:-0}"
    if [ $worker_count -gt 0 ]; then
        log_info "Restarting ${worker_count} worker container(s)..."

        # Stop old workers
        for i in $(seq 1 $worker_count); do
            local worker_name="${APP_NAME}_worker_${i}"
            if docker ps -a --filter "name=${worker_name}" --format "{{.Names}}" | grep -q "^${worker_name}$"; then
                stop_container "$worker_name"
            fi
        done

        # Start new workers
        for i in $(seq 1 $worker_count); do
            local worker_name="${APP_NAME}_worker_${i}"
            start_worker_container "$worker_name" "${DOCKER_IMAGE_NAME}:${image_tag}" "$ENV_FILE"

            if [ $? -ne 0 ]; then
                log_error "Failed to start worker ${worker_name}"
                return 1
            fi
        done
        log_success "Worker containers restarted successfully"
    fi

    return 0
}

# Function: Display deployment summary
rails_display_deployment_summary() {
    local scale="$1"
    local image_tag="$2"
    local migrations_run="${3:-false}"

    echo ""
    echo "================================================================================"
    echo "                     DEPLOYMENT SUMMARY"
    echo "================================================================================"
    echo ""

    # Application Information
    echo "APPLICATION:"
    echo "  Name: ${APP_DISPLAY_NAME}"
    echo "  App ID: ${APP_NAME}"
    echo "  Git Commit: ${CURRENT_COMMIT:0:7}"
    echo "  Image Tag: ${image_tag}"
    echo ""

    # Deployment Status
    echo "DEPLOYMENT STATUS:"
    echo "  Status: SUCCESS ✓"
    echo "  Timestamp: $(date)"
    echo "  Migrations: $([ "$migrations_run" = "true" ] && echo "Executed ✓" || echo "Not needed")"
    echo ""

    # URLs and Access
    echo "AVAILABILITY:"
    echo "  Primary URL: https://${DOMAIN}"
    if [[ "$DOMAIN" != www.* ]]; then
        echo "  Alternative: https://www.${DOMAIN}"
    fi
    echo "  Health Check: https://${DOMAIN}${HEALTH_CHECK_PATH}"
    echo ""

    # Container Information
    echo "WEB CONTAINERS:"
    local containers=($(get_running_containers "$APP_NAME"))
    echo "  Count: ${#containers[@]} instances"
    echo "  Containers:"
    for container in "${containers[@]}"; do
        local port=$(docker port "$container" 80 2>/dev/null | cut -d ':' -f2)
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
        echo "    - ${container} (port ${port}, status: ${status})"
    done
    echo ""

    # Worker Information (if applicable)
    local worker_containers=($(docker ps --filter "name=${APP_NAME}_worker" --format "{{.Names}}" 2>/dev/null))
    if [ ${#worker_containers[@]} -gt 0 ]; then
        echo "WORKER CONTAINERS:"
        echo "  Count: ${#worker_containers[@]} instances"
        for worker in "${worker_containers[@]}"; do
            local status=$(docker inspect -f '{{.State.Status}}' "$worker" 2>/dev/null)
            echo "    - ${worker} (status: ${status})"
        done
        echo ""
    fi

    # Image Backups
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

    # Rollback Instructions
    echo "ROLLBACK:"
    echo "  To rollback to the previous version:"
    if [ -d "$IMAGE_BACKUP_DIR" ]; then
        local backup_count=$(ls -1 "${IMAGE_BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        if [ "$backup_count" -gt 1 ]; then
            echo "    ./deploy.sh rollback -1     # Rollback to previous version"
            echo "    ./deploy.sh rollback -2     # Rollback 2 versions back"
        else
            echo "    ./deploy.sh list-images     # List available versions"
        fi
    else
        echo "    Image backups not enabled"
    fi
    echo ""

    # Useful Commands
    echo "USEFUL COMMANDS:"
    echo "  View logs:        docker logs ${APP_NAME}_web_1 -f"
    echo "  Rails console:    docker exec -it ${APP_NAME}_web_1 rails console"
    echo "  Check health:     curl https://${DOMAIN}${HEALTH_CHECK_PATH}"
    echo "  Scale up:         ./deploy.sh scale $((scale + 1))"
    echo "  Scale down:       ./deploy.sh scale $((scale - 1))"
    echo "  Restart:          ./deploy.sh restart"
    echo "  Stop:             ./deploy.sh stop"
    echo "  Restore DB:       ${APP_DIR}/restore.sh"
    echo ""

    # Database Information
    echo "DATABASE:"
    echo "  Name: ${DB_NAME}"
    local backup_count=$(ls -1 ${BACKUP_DIR}/*.sql.gz 2>/dev/null | wc -l | tr -d ' ')
    echo "  Available Backups: ${backup_count}"
    echo "  Latest Backup: $(ls -t ${BACKUP_DIR}/*.sql.gz 2>/dev/null | head -1 | xargs -r basename)"
    echo "  Backup Location: ${BACKUP_DIR}"
    echo ""

    # Next Steps
    echo "NEXT STEPS:"
    echo "  1. Verify the application is working:"
    echo "     curl https://${DOMAIN}"
    echo ""
    echo "  2. Monitor the logs for any issues:"
    echo "     docker logs ${APP_NAME}_web_1 -f"
    echo ""
    echo "  3. If something went wrong, rollback immediately:"
    echo "     ./deploy.sh list-images"
    echo "     ./deploy.sh rollback <previous-image>"
    echo ""

    echo "================================================================================"
    echo ""
}

# Function: Main Rails deployment workflow
rails_deploy_application() {
    local scale="$1"
    local image_tag="$(date +%Y%m%d_%H%M%S)"
    local migrations_run="false"

    log_info "Starting Rails deployment of ${APP_DISPLAY_NAME} with scale=${scale}"

    # Pull latest code
    rails_pull_code || return 1

    # Build Docker image
    rails_build_image "$image_tag" || return 1

    # Check if any containers are running
    local current_count=$(get_container_count "$APP_NAME")

    if [ $current_count -eq 0 ]; then
        rails_deploy_fresh "$scale" "$image_tag" || return 1
        if [ "$MIGRATION_BACKUP_ENABLED" = "true" ]; then
            migrations_run="true"
        fi
    else
        # Check if migrations will run
        local test_container="${APP_NAME}_migration_check"
        if [ "$MIGRATION_BACKUP_ENABLED" = "true" ]; then
            docker run -d --name "$test_container" --env-file "$ENV_FILE" "${DOCKER_IMAGE_NAME}:${image_tag}" sleep infinity 2>/dev/null
            sleep 2
            if rails_check_pending_migrations "$test_container" 2>/dev/null; then
                migrations_run="true"
            fi
            docker rm -f "$test_container" 2>/dev/null
        fi

        rails_deploy_rolling "$scale" "$image_tag" || return 1
    fi

    # Clean up old images
    if [ "$AUTO_CLEANUP_ENABLED" = "true" ]; then
        cleanup_old_images "$DOCKER_IMAGE_NAME" "$MAX_IMAGE_VERSIONS"
    fi

    # Log deployment
    echo "[$(date)] Deployed ${DOCKER_IMAGE_NAME}:${image_tag} with scale=${scale}, migrations=${migrations_run}" >> "${LOG_DIR}/deployments.log"

    log_success "Rails deployment completed successfully!"

    # Display comprehensive summary
    rails_display_deployment_summary "$scale" "$image_tag" "$migrations_run"

    return 0
}

# Function: Restart Rails application
rails_restart_application() {
    local scale="$1"

    log_info "Restarting ${APP_DISPLAY_NAME} with scale=${scale}"

    # Get current image
    local current_image="${DOCKER_IMAGE_NAME}:latest"

    # Check if image exists
    if ! docker image inspect "$current_image" > /dev/null 2>&1; then
        log_error "Image ${current_image} not found. Please run deploy first."
        return 1
    fi

    # Perform rolling restart for web containers
    rolling_restart "$APP_NAME" "$current_image" "$ENV_FILE" "$BASE_PORT" "$scale"

    if [ $? -ne 0 ]; then
        log_error "Restart failed"
        return 1
    fi

    # Restart worker containers if configured
    local worker_count="${WORKER_COUNT:-0}"
    if [ $worker_count -gt 0 ]; then
        log_info "Restarting ${worker_count} worker container(s)..."

        # Stop old workers
        for i in $(seq 1 $worker_count); do
            local worker_name="${APP_NAME}_worker_${i}"
            if docker ps -a --filter "name=${worker_name}" --format "{{.Names}}" | grep -q "^${worker_name}$"; then
                stop_container "$worker_name"
            fi
        done

        # Start new workers
        for i in $(seq 1 $worker_count); do
            local worker_name="${APP_NAME}_worker_${i}"
            start_worker_container "$worker_name" "$current_image" "$ENV_FILE"

            if [ $? -ne 0 ]; then
                log_error "Failed to start worker ${worker_name}"
                return 1
            fi
        done
        log_success "Worker containers restarted successfully"
    fi

    log_success "Restart completed successfully"
    return 0
}

# Function: Scale Rails application
rails_scale_application() {
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

# Function: Stop Rails application
rails_stop_application() {
    log_info "Stopping all ${APP_NAME} containers"

    # Get all containers (web + workers)
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

# Function: Run Rails console in container
rails_run_console() {
    local container_name="${APP_NAME}_web_1"

    # Check if container is running
    if ! docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_error "Container ${container_name} is not running"
        return 1
    fi

    log_info "Starting Rails console in ${container_name}..."
    docker exec -it "$container_name" /bin/bash -c "cd /rails && bundle exec rails console"

    return 0
}

# Function: Run Rails task in container
rails_run_task() {
    local task="$1"
    local container_name="${APP_NAME}_web_1"

    # Check if container is running
    if ! docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_error "Container ${container_name} is not running"
        return 1
    fi

    log_info "Running Rails task in ${container_name}: ${task}"
    docker exec -it "$container_name" /bin/bash -c "cd /rails && bundle exec rails ${task}"

    return 0
}
