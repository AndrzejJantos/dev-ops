#!/bin/bash

# Next.js Application Type Module
# Location: /home/andrzej/DevOps/common/app-types/nextjs.sh
# This module provides Next.js-specific setup and deployment hooks

# Export app type for identification
export APP_TYPE="nextjs"

# ==============================================================================
# SETUP HOOKS
# ==============================================================================

# Hook: Check Next.js prerequisites
nextjs_check_prerequisites() {
    log_info "Checking Next.js prerequisites..."

    # Next.js apps don't need database or Redis
    # Just verify Docker and Node are available (via Docker)

    log_success "All Next.js prerequisites satisfied"
    return 0
}

# Hook: Create Next.js-specific environment file
nextjs_create_env_file() {
    log_info "Creating Next.js environment file: ${ENV_FILE}"

    # Check if we need to preserve existing values
    EXISTING_ENV=""
    if [ -f "$ENV_FILE" ]; then
        log_warning "Environment file already exists. Backing up..."
        cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        EXISTING_ENV="$ENV_FILE"
    fi

    # Create production env file with common Next.js variables
    cat > "$ENV_FILE" << EOF
# Production Environment Variables for ${APP_NAME}
# Generated on $(date)
# Location: ${ENV_FILE}

# Application Configuration
NODE_ENV=production
PORT=${CONTAINER_PORT:-3000}

# API Configuration (update with your actual API URL)
NEXT_PUBLIC_API_URL=https://api.example.com
NEXT_PUBLIC_API_TIMEOUT=30000

# Google Maps (if needed)
NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=your_google_maps_key_here

# Google Analytics (if needed)
NEXT_PUBLIC_GA_MEASUREMENT_ID=your_ga_measurement_id_here

# App-specific environment variables
# Add your custom variables below:

EOF

    log_success "Environment file created: ${ENV_FILE}"
    log_warning "IMPORTANT: Edit ${ENV_FILE} and update the API URLs and keys!"

    return 0
}

# Hook: Setup Next.js-specific requirements
nextjs_setup_requirements() {
    log_info "Setting up Next.js-specific requirements..."

    # Check if next.config.js has standalone output configured
    if [ -f "$REPO_DIR/next.config.js" ] || [ -f "$REPO_DIR/next.config.mjs" ]; then
        log_warning "Please ensure your next.config.js has output: 'standalone' configured:"
        echo ""
        echo "  module.exports = {"
        echo "    output: 'standalone',"
        echo "    // ... other config"
        echo "  }"
        echo ""
    else
        log_warning "next.config.js not found. You may need to create it with standalone output."
    fi

    # Copy Dockerfile and .dockerignore from DevOps template
    log_info "Copying Docker files from template..."
    cp "$DEVOPS_DIR/common/nextjs/Dockerfile.template" "$REPO_DIR/Dockerfile"

    if [ -f "$DEVOPS_DIR/common/nextjs/.dockerignore.template" ]; then
        cp "$DEVOPS_DIR/common/nextjs/.dockerignore.template" "$REPO_DIR/.dockerignore"
    fi

    log_success "Next.js setup requirements completed"
    return 0
}

# Hook: No database setup needed for Next.js
nextjs_setup_database() {
    log_info "Next.js apps don't require database setup"
    return 0
}

# Hook: No migrations for Next.js
nextjs_run_migrations() {
    log_info "Next.js apps don't have database migrations"
    return 0
}

# ==============================================================================
# DEPLOYMENT HOOKS
# ==============================================================================

# Hook: Pull code for Next.js app
nextjs_pull_code() {
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

# Hook: Build Next.js Docker image
nextjs_build_image() {
    local image_tag="$1"

    log_info "Building Next.js Docker image with tag: ${image_tag}"

    # Ensure Dockerfile from DevOps template is used
    if [ -f "${DEVOPS_DIR}/common/nextjs/Dockerfile.template" ]; then
        log_info "Copying Dockerfile from DevOps template..."
        cp "${DEVOPS_DIR}/common/nextjs/Dockerfile.template" "${REPO_DIR}/Dockerfile"

        if [ -f "${DEVOPS_DIR}/common/nextjs/.dockerignore.template" ]; then
            cp "${DEVOPS_DIR}/common/nextjs/.dockerignore.template" "${REPO_DIR}/.dockerignore"
        fi
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

    # Build Docker image using common function
    build_docker_image "$DOCKER_IMAGE_NAME" "$REPO_DIR" "$image_tag"
    local build_result=$?

    # Remove temporary .env.production after build
    rm -f "${REPO_DIR}/.env.production"
    log_info "Removed temporary build environment file"

    if [ $build_result -ne 0 ]; then
        log_error "Docker build failed"
        return 1
    fi

    # Tag as latest
    docker tag "${DOCKER_IMAGE_NAME}:${image_tag}" "${DOCKER_IMAGE_NAME}:latest"

    log_success "Docker image built and tagged successfully"

    # Save image as tar file backup if enabled
    if [ "${SAVE_IMAGE_BACKUPS:-false}" = "true" ] && [ -n "${IMAGE_BACKUP_DIR:-}" ]; then
        log_info "=== Docker Image Backup ==="

        # Show last backup before creating new one
        if [ -d "$IMAGE_BACKUP_DIR" ]; then
            local last_image_backup=$(ls -t "${IMAGE_BACKUP_DIR}"/*.tar.gz 2>/dev/null | head -1)
            if [ -n "$last_image_backup" ]; then
                local img_backup_name=$(basename "$last_image_backup")
                local img_backup_size=$(du -h "$last_image_backup" | cut -f1)
                local img_backup_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$last_image_backup" 2>/dev/null || stat -c "%y" "$last_image_backup" 2>/dev/null | cut -d'.' -f1)
                log_info "Last image backup: ${img_backup_name}"
                log_info "  Size: ${img_backup_size}"
                log_info "  Created: ${img_backup_time}"
            else
                log_info "No previous image backups found"
            fi
        fi

        log_info "Creating new Docker image backup..."
        save_docker_image "$DOCKER_IMAGE_NAME" "$image_tag" "$IMAGE_BACKUP_DIR"

        # Show the new backup that was just created
        local new_image_backup="${IMAGE_BACKUP_DIR}/${DOCKER_IMAGE_NAME}_${image_tag}.tar.gz"
        if [ -f "$new_image_backup" ]; then
            local new_img_size=$(du -h "$new_image_backup" | cut -f1)
            log_success "New image backup: ${DOCKER_IMAGE_NAME}_${image_tag}.tar.gz (${new_img_size})"
        fi

        # Cleanup old backups and show retention info
        local keep_count="${MAX_IMAGE_BACKUPS:-5}"
        log_info "Keeping last ${keep_count} image backups, cleaning up older ones..."
        cleanup_old_image_backups "$IMAGE_BACKUP_DIR" "$keep_count"

        # Show current backup count
        local total_backups=$(ls -1 "${IMAGE_BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        log_info "Total image backups retained: ${total_backups}"

        log_info "=========================="
    fi

    return 0
}

# Hook: Deploy Next.js containers (fresh deployment)
nextjs_deploy_fresh() {
    local scale="$1"
    local image_tag="$2"

    log_info "No existing containers found, deploying fresh with ${scale} container(s)"

    # Start web containers
    for i in $(seq 1 $scale); do
        local port=$((BASE_PORT + i - 1))
        local container_name="${APP_NAME}_web_${i}"

        start_container "$container_name" "${DOCKER_IMAGE_NAME}:${image_tag}" "$port" "$ENV_FILE" "$CONTAINER_PORT"

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

# Hook: Deploy Next.js containers (rolling restart)
nextjs_deploy_rolling() {
    local scale="$1"
    local image_tag="$2"

    log_info "Running containers detected, performing zero-downtime deployment"

    # Perform rolling restart for web containers
    if [ "$ZERO_DOWNTIME_ENABLED" = "true" ]; then
        rolling_restart "$APP_NAME" "${DOCKER_IMAGE_NAME}:${image_tag}" "$ENV_FILE" "$BASE_PORT" "$scale" "$CONTAINER_PORT"

        if [ $? -ne 0 ]; then
            log_error "Rolling restart failed"
            return 1
        fi

        log_success "Zero-downtime deployment completed successfully"
    fi

    return 0
}

# Hook: Display Next.js deployment summary
nextjs_display_deployment_summary() {
    local scale="$1"
    local image_tag="$2"

    echo ""
    echo "================================================================================"
    echo "                     DEPLOYMENT SUMMARY"
    echo "================================================================================"
    echo ""
    echo "APPLICATION:"
    echo "  Name: ${APP_DISPLAY_NAME}"
    echo "  Type: Next.js Frontend"
    echo "  App ID: ${APP_NAME}"
    echo "  Git Commit: ${CURRENT_COMMIT:0:7}"
    echo "  Image Tag: ${image_tag}"
    echo ""
    echo "DEPLOYMENT STATUS:"
    echo "  Status: SUCCESS"
    echo "  Timestamp: $(date)"
    echo ""
    echo "AVAILABILITY:"
    echo "  Primary URL: https://${DOMAIN}"
    if [[ "$DOMAIN" != www.* ]]; then
        echo "  Alternative: https://www.${DOMAIN}"
    fi
    echo ""

    # SSL Certificate Information
    echo "SSL CERTIFICATE:"
    if command -v certbot >/dev/null 2>&1 && sudo certbot certificates 2>/dev/null | grep -q "Certificate Name: ${DOMAIN}"; then
        # Certificate exists, extract details
        local cert_info=$(sudo certbot certificates 2>/dev/null | grep -A 15 "Certificate Name: ${DOMAIN}")

        # Extract domains
        local domains=$(echo "$cert_info" | grep "Domains:" | sed 's/.*Domains: //')

        # Extract expiry date (take only first match)
        local expiry_date=$(echo "$cert_info" | grep "Expiry Date:" | head -1 | awk '{print $3}')
        local expiry_time=$(echo "$cert_info" | grep "Expiry Date:" | head -1 | awk '{print $4}')

        # Calculate days remaining
        if [ -n "$expiry_date" ]; then
            local expiry_ts=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
            local now_ts=$(date +%s)
            local days_left=$(( (expiry_ts - now_ts) / 86400 ))

            echo "  Status: Active"
            echo "  Domains: ${domains}"
            echo "  Expires: ${expiry_date} ${expiry_time}"

            if [ $days_left -lt 30 ]; then
                echo "  Validity: ${days_left} days remaining ⚠️  (renewal due)"
            elif [ $days_left -lt 60 ]; then
                echo "  Validity: ${days_left} days remaining"
            else
                echo "  Validity: ${days_left} days remaining ✓"
            fi

            # Certificate path
            echo "  Certificate: /etc/letsencrypt/live/${DOMAIN}/"
        else
            echo "  Status: Active (unable to parse expiry)"
        fi
    else
        echo "  Status: Not configured"
        echo "  Note: SSL is automatically checked during deployment"
    fi

    # Show SSL setup attempt status if available
    if [ -n "${SSL_SETUP_STATUS:-}" ]; then
        case "$SSL_SETUP_STATUS" in
            success)
                echo "  Last Setup: ✓ Success"
                ;;
            failed)
                echo "  Last Setup: ✗ FAILED"
                [ -n "${SSL_SETUP_MESSAGE:-}" ] && echo "  Error: ${SSL_SETUP_MESSAGE}"
                echo "  Action: Check DNS configuration and redeploy"
                ;;
            skipped)
                [ -n "${SSL_SETUP_MESSAGE:-}" ] && echo "  Note: ${SSL_SETUP_MESSAGE}"
                ;;
        esac
    fi
    echo ""

    echo "WEB CONTAINERS:"
    local containers=($(get_running_containers "$APP_NAME"))
    echo "  Count: ${#containers[@]} instances"
    echo "  Containers:"
    for container in "${containers[@]}"; do
        local port=$(docker port "$container" "$CONTAINER_PORT" 2>/dev/null | cut -d ':' -f2)
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
    echo "  Deploy:           cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh"
    echo "  Check health:     curl https://${DOMAIN}"
    echo "  Scale to N:       cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh scale N"
    echo "  Restart:          cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh restart"
    echo "  Stop:             cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh stop"
    echo ""
    echo "NAVIGATION:"
    echo "  Config dir:       cd ~/DevOps/apps/${APP_NAME}"
    echo "  Deployed app:     cd ~/apps/${APP_NAME}"
    echo "  Quick link:       cd ~/apps/${APP_NAME}/config (→ config dir)"
    echo ""
    echo "LOGS (Next.js logs to Docker stdout):"
    echo "  Docker logs:      docker logs ${APP_NAME}_web_1 -f"
    echo "  All containers:   docker logs ${APP_NAME}_web_1 -f --tail=100"
    echo "  Note: To persist logs to ${LOG_DIR}/, configure a custom logger in your Next.js app"
    echo ""
    echo "================================================================================"
    echo ""
}

# ==============================================================================
# CONTAINER MANAGEMENT HOOKS
# ==============================================================================

# Hook: Stop all Next.js containers
nextjs_stop_containers() {
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

# Hook: Next.js apps don't have workers/schedulers
nextjs_has_workers() {
    return 1  # false
}

nextjs_has_scheduler() {
    return 1  # false
}
