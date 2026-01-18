#!/bin/bash

# Cron Job Application Type Module
# Location: /home/andrzej/DevOps/common/app-types/cron-job.sh
# This module provides cron-job specific deployment hooks
# Cron jobs don't need DNS, nginx, SSL - they just run scheduled tasks

# Export app type for identification
export APP_TYPE="cron-job"

# ==============================================================================
# SETUP HOOKS
# ==============================================================================

# Hook: Check cron-job prerequisites
cron-job_check_prerequisites() {
    log_info "Checking cron-job prerequisites..."

    # Just verify Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed"
        return 1
    fi

    log_success "All cron-job prerequisites satisfied"
    return 0
}

# Hook: Create cron-job environment file (copy from template or existing)
cron-job_create_env_file() {
    log_info "Checking environment file: ${ENV_FILE}"

    if [ -f "$ENV_FILE" ]; then
        log_success "Environment file exists: ${ENV_FILE}"
        return 0
    fi

    # Check for template
    if [ -f "$SCRIPT_DIR/.env.example" ]; then
        log_info "Creating environment file from template..."
        cp "$SCRIPT_DIR/.env.example" "$ENV_FILE"
        log_warning "Please edit $ENV_FILE with your configuration"
        return 1
    fi

    log_error "Environment file not found: $ENV_FILE"
    log_error "Please create it manually or provide .env.example template"
    return 1
}

# Hook: No database setup needed for cron-job
cron-job_setup_database() {
    log_info "Cron-job connects to existing database (no setup needed)"
    return 0
}

# Hook: No migrations for cron-job
cron-job_run_migrations() {
    log_info "Cron-job uses existing database schema (no migrations)"
    return 0
}

# ==============================================================================
# DEPLOYMENT HOOKS
# ==============================================================================

# Hook: Pull code for cron-job (from multiple repos if needed)
cron-job_pull_code() {
    log_info "Pulling latest code for cron-job..."

    # Create build context directory
    local build_context="${BUILD_CONTEXT_DIR:-$APP_DIR/build-context}"
    mkdir -p "$build_context"

    # Pull/sync required repositories
    # API repository
    if [ -n "${API_REPO_DIR:-}" ]; then
        log_info "Syncing API code from ${API_REPO_DIR}..."
        if [ -d "$API_REPO_DIR/.git" ]; then
            cd "$API_REPO_DIR"
            git fetch origin "${API_REPO_BRANCH:-master}"
            git reset --hard origin/"${API_REPO_BRANCH:-master}"
            log_success "API code updated"
        fi

        # Copy to build context
        log_info "Copying API to build context..."
        rm -rf "$build_context/${API_SOURCE_DIR:-cheaperfordrug-api}"
        cp -r "$API_REPO_DIR" "$build_context/${API_SOURCE_DIR:-cheaperfordrug-api}"
    fi

    # Scraper repository
    if [ -n "${SCRAPER_REPO_DIR:-}" ]; then
        log_info "Syncing Scraper code from ${SCRAPER_REPO_DIR}..."
        if [ -d "$SCRAPER_REPO_DIR/.git" ]; then
            cd "$SCRAPER_REPO_DIR"
            git fetch origin "${SCRAPER_REPO_BRANCH:-master}"
            git reset --hard origin/"${SCRAPER_REPO_BRANCH:-master}"
            log_success "Scraper code updated"
        fi

        # Copy to build context
        log_info "Copying Scraper to build context..."
        rm -rf "$build_context/${SCRAPER_SOURCE_DIR:-cheaperfordrug-scraper}"
        cp -r "$SCRAPER_REPO_DIR" "$build_context/${SCRAPER_SOURCE_DIR:-cheaperfordrug-scraper}"
    fi

    # Copy DevOps files to build context
    log_info "Copying DevOps configuration to build context..."
    rm -rf "$build_context/DevOps"
    mkdir -p "$build_context/DevOps/apps"
    cp -r "$DEVOPS_DIR/apps/$APP_NAME" "$build_context/DevOps/apps/"

    # Export for use in build
    export BUILD_CONTEXT="$build_context"
    export CURRENT_COMMIT="multi-repo"

    return 0
}

# Hook: Build cron-job Docker image
cron-job_build_image() {
    local image_tag="$1"
    local build_context="${BUILD_CONTEXT:-$APP_DIR/build-context}"

    log_info "Building cron-job Docker image with tag: ${image_tag}"
    log_info "Build context: ${build_context}"
    log_info "Dockerfile: ${DOCKERFILE_PATH}"

    cd "$build_context"

    # Build Docker image
    if docker build \
        -f "${DOCKERFILE_PATH}" \
        -t "${DOCKER_IMAGE_NAME}:${image_tag}" \
        -t "${DOCKER_IMAGE_NAME}:latest" \
        .; then
        log_success "Docker image built: ${DOCKER_IMAGE_NAME}:${image_tag}"
    else
        log_error "Docker build failed"
        return 1
    fi

    # Save image backup if enabled
    if [ "${SAVE_IMAGE_BACKUPS:-false}" = "true" ] && [ -n "${IMAGE_BACKUP_DIR:-}" ]; then
        log_info "Saving Docker image backup..."
        mkdir -p "$IMAGE_BACKUP_DIR"
        local backup_file="${IMAGE_BACKUP_DIR}/${DOCKER_IMAGE_NAME}_${image_tag}.tar"

        if docker save "${DOCKER_IMAGE_NAME}:${image_tag}" -o "$backup_file"; then
            log_success "Image backup saved: $backup_file"

            # Cleanup old backups
            local max_backups="${MAX_IMAGE_BACKUPS:-5}"
            local backup_count=$(ls -1 "${IMAGE_BACKUP_DIR}"/*.tar 2>/dev/null | wc -l)

            if [ "$backup_count" -gt "$max_backups" ]; then
                local to_delete=$((backup_count - max_backups))
                log_info "Cleaning up $to_delete old backup(s)..."
                ls -1t "${IMAGE_BACKUP_DIR}"/*.tar | tail -n "$to_delete" | xargs rm -f
            fi
        else
            log_warning "Failed to save image backup"
        fi
    fi

    return 0
}

# Hook: Deploy cron-job container (fresh deployment)
cron-job_deploy_fresh() {
    local scale="$1"  # Ignored for cron-job (always 1)
    local image_tag="$2"

    log_info "Deploying cron-job container..."

    # Stop existing container if any
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
        --network "${NETWORK_MODE:-host}" \
        --restart unless-stopped \
        --env-file "$ENV_FILE" \
        -v "$LOG_DIR:/var/log/drug-processor" \
        "${DOCKER_IMAGE_NAME}:latest"

    # Wait and check health
    sleep 5

    if docker ps -q -f "name=${CONTAINER_NAME}" | grep -q .; then
        log_success "Container started successfully"
        return 0
    else
        log_error "Container failed to start"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -50
        return 1
    fi
}

# Hook: Deploy cron-job containers (rolling - same as fresh for single container)
cron-job_deploy_rolling() {
    local scale="$1"
    local image_tag="$2"

    # For cron-job, rolling is same as fresh (single container)
    cron-job_deploy_fresh "$scale" "$image_tag"
    return $?
}

# Hook: Display cron-job deployment summary
cron-job_display_deployment_summary() {
    local scale="$1"
    local image_tag="$2"

    echo ""
    echo "================================================================================"
    echo "                     DEPLOYMENT SUMMARY"
    echo "================================================================================"
    echo ""
    echo "APPLICATION:"
    echo "  Name: ${APP_DISPLAY_NAME}"
    echo "  Type: Cron Job"
    echo "  App ID: ${APP_NAME}"
    echo "  Image Tag: ${image_tag}"
    echo ""
    echo "CONTAINER:"
    if docker ps -q -f "name=${CONTAINER_NAME}" | grep -q .; then
        local status=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
        local started=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null)
        echo "  Name: ${CONTAINER_NAME}"
        echo "  Status: ${status}"
        echo "  Started: ${started}"
    else
        echo "  Status: Not running"
    fi
    echo ""
    echo "SCHEDULE:"
    echo "  Cron: ${CRON_SCHEDULE:-Not configured}"
    echo ""
    echo "USEFUL COMMANDS:"
    echo "  Deploy:    cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh deploy"
    echo "  Status:    cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh status"
    echo "  Logs:      cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh logs"
    echo "  Test run:  cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh test"
    echo "  Stop:      cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh stop"
    echo ""
    echo "================================================================================"
    echo ""
}

# ==============================================================================
# CONTAINER MANAGEMENT HOOKS
# ==============================================================================

# Hook: Stop cron-job container
cron-job_stop_containers() {
    log_info "Stopping ${CONTAINER_NAME} container"

    if docker ps -q -f "name=${CONTAINER_NAME}" | grep -q .; then
        docker stop "$CONTAINER_NAME"
        docker rm "$CONTAINER_NAME" || true
        log_success "Container stopped"
    else
        log_info "Container not running"
    fi

    return 0
}

# Hook: Cron-job doesn't have workers
cron-job_has_workers() {
    return 1  # false
}

# Hook: Cron-job doesn't have scheduler (it IS the scheduler)
cron-job_has_scheduler() {
    return 1  # false
}
