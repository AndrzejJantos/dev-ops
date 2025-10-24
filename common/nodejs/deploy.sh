#!/bin/bash

# Node.js-specific deployment functions
# Location: /home/andrzej/DevOps/common/nodejs/deploy.sh
# This file should be sourced by app-specific deploy.sh scripts

# This file provides Node.js-specific deployment functionality that can be:
# 1. Used as-is by sourcing it
# 2. Overridden by defining functions with the same name AFTER sourcing
# 3. Extended with pre/post hooks

# Function: Pull latest code from repository
nodejs_pull_code() {
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

# Function: Build Node.js Docker image
nodejs_build_image() {
    local image_tag="$1"

    log_info "Building Docker image with tag: ${image_tag}"

    build_docker_image "$DOCKER_IMAGE_NAME" "$REPO_DIR" "$image_tag"

    if [ $? -ne 0 ]; then
        log_error "Docker build failed"
        return 1
    fi

    # Tag as latest
    docker tag "${DOCKER_IMAGE_NAME}:${image_tag}" "${DOCKER_IMAGE_NAME}:latest"

    log_success "Docker image built and tagged successfully"
    return 0
}

# Function: Check for pending Node.js migrations
nodejs_check_pending_migrations() {
    local test_container="$1"

    # Only check if migrations are configured
    if [ "${NEEDS_MIGRATIONS:-false}" != "true" ]; then
        return 1  # No migrations to check
    fi

    log_info "Checking for pending migrations..."

    # This is app-specific, override in your app's deploy.sh if needed
    # Example for Prisma:
    # local output=$(docker exec "$test_container" npm run migrate:status 2>&1)
    # if echo "$output" | grep -q "pending"; then
    #     return 0
    # fi

    return 1  # Default: no pending migrations
}

# Function: Run Node.js migrations with backup
nodejs_run_migrations_with_backup() {
    local test_container="$1"

    if [ "${NEEDS_MIGRATIONS:-false}" != "true" ]; then
        return 0  # No migrations needed
    fi

    log_info "Running migrations with database backup..."

    # Backup database if PostgreSQL is used
    if [ "${NEEDS_POSTGRES:-false}" = "true" ]; then
        backup_database "$DB_NAME" "$BACKUP_DIR"
    fi

    # Run migrations
    docker exec "$test_container" /bin/bash -c "npm run migrate"

    if [ $? -ne 0 ]; then
        log_error "Migrations failed"
        return 1
    fi

    log_success "Migrations completed successfully"
    return 0
}

# Function: Deploy Node.js application (fresh deployment - no existing containers)
nodejs_deploy_fresh() {
    local scale="$1"
    local image_tag="$2"

    log_info "No running containers found, starting fresh deployment"

    # Start containers
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

    # Run migrations after first container is up (if needed)
    if [ "${NEEDS_MIGRATIONS:-false}" = "true" ] && [ "${MIGRATION_BACKUP_ENABLED:-true}" = "true" ]; then
        log_info "Running database migrations..."
        docker exec "${APP_NAME}_web_1" /bin/bash -c "npm run migrate"
    fi

    log_success "Fresh deployment completed successfully"
    return 0
}

# Function: Deploy Node.js application with zero downtime (rolling restart)
nodejs_deploy_rolling() {
    local scale="$1"
    local image_tag="$2"

    log_info "Running containers detected, performing zero-downtime deployment"

    # Create a test container to check migrations (if needed)
    if [ "${NEEDS_MIGRATIONS:-false}" = "true" ] && [ "${MIGRATION_BACKUP_ENABLED:-true}" = "true" ]; then
        local test_container="${APP_NAME}_migration_check"

        docker run -d \
            --name "$test_container" \
            --env-file "$ENV_FILE" \
            "${DOCKER_IMAGE_NAME}:${image_tag}" \
            sleep infinity

        sleep 5

        # Check if migrations are needed
        if nodejs_check_pending_migrations "$test_container"; then
            nodejs_run_migrations_with_backup "$test_container"

            if [ $? -ne 0 ]; then
                docker rm -f "$test_container"
                return 1
            fi
        fi

        docker rm -f "$test_container"
    fi

    # Perform rolling restart
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

# Function: Main Node.js deployment workflow
nodejs_deploy_application() {
    local scale="$1"
    local image_tag="$(date +%Y%m%d_%H%M%S)"

    log_info "Starting Node.js deployment of ${APP_DISPLAY_NAME} with scale=${scale}"

    # Pull latest code
    nodejs_pull_code || return 1

    # Build Docker image
    nodejs_build_image "$image_tag" || return 1

    # Check if any containers are running
    local current_count=$(get_container_count "$APP_NAME")

    if [ $current_count -eq 0 ]; then
        nodejs_deploy_fresh "$scale" "$image_tag" || return 1
    else
        nodejs_deploy_rolling "$scale" "$image_tag" || return 1
    fi

    # Clean up old images
    if [ "$AUTO_CLEANUP_ENABLED" = "true" ]; then
        cleanup_old_images "$DOCKER_IMAGE_NAME" "$MAX_IMAGE_VERSIONS"
    fi

    # Log deployment
    echo "[$(date)] Deployed ${DOCKER_IMAGE_NAME}:${image_tag} with scale=${scale}" >> "${LOG_DIR}/deployments.log"

    log_success "Node.js deployment completed successfully!"

    return 0
}

# Function: Restart Node.js application
nodejs_restart_application() {
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

# Function: Scale Node.js application
nodejs_scale_application() {
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

# Function: Stop Node.js application
nodejs_stop_application() {
    log_info "Stopping all ${APP_NAME} containers"

    local containers=($(get_running_containers "$APP_NAME"))

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

# Function: Run Node.js shell in container
nodejs_run_shell() {
    local container_name="${APP_NAME}_web_1"

    # Check if container is running
    if ! docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_error "Container ${container_name} is not running"
        return 1
    fi

    log_info "Starting shell in ${container_name}..."
    docker exec -it "$container_name" /bin/bash

    return 0
}

# Function: Run npm script in container
nodejs_run_script() {
    local script="$1"
    local container_name="${APP_NAME}_web_1"

    # Check if container is running
    if ! docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_error "Container ${container_name} is not running"
        return 1
    fi

    log_info "Running npm script in ${container_name}: ${script}"
    docker exec -it "$container_name" npm run "$script"

    return 0
}
