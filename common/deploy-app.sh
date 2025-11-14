#!/bin/bash

# Generic Application Deployment Script
# Location: /home/andrzej/DevOps/common/deploy-app.sh
# This script handles deployment for any application type using composition
#
# Usage:
#   1. Source this script from your app's deploy.sh
#   2. Call handle_deploy_command "$@" to process command-line arguments
#
# Requirements:
#   - config.sh must be sourced first
#   - APP_TYPE must be set in config.sh (either "nextjs" or "rails")

set -e

# ==============================================================================
# PRE-DEPLOYMENT CHECKS
# ==============================================================================

# Update DevOps repository to get latest templates and scripts
update_devops_repo() {
    log_info "=== Updating DevOps Repository ==="

    local devops_root="$DEVOPS_DIR"

    # Check if we're in a git repository
    if [ ! -d "$devops_root/.git" ]; then
        log_warning "DevOps directory is not a git repository, skipping update"
        return 0
    fi

    # Save current directory
    local original_dir=$(pwd)

    # Go to DevOps root
    cd "$devops_root"

    # Check if there are uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        log_warning "DevOps repository has uncommitted changes, skipping update"
        cd "$original_dir"
        return 0
    fi

    # Pull latest changes
    log_info "Pulling latest DevOps changes..."
    if git pull origin master 2>&1 | grep -E "(Already up to date|Fast-forward|Updating)"; then
        log_success "DevOps repository updated"
    else
        log_warning "Failed to update DevOps repository, continuing with existing version"
    fi

    # Return to original directory
    cd "$original_dir"

    return 0
}

# Check DNS configuration - FAIL deployment if DNS not configured
check_dns_configuration() {
    log_info "=== DNS Configuration Check ==="

    # Get server IP
    local server_ipv4=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org)
    if [ -z "$server_ipv4" ]; then
        log_error "Could not determine server IP address"
        return 1
    fi

    log_info "Server IP: ${server_ipv4}"

    local dns_ok=true
    local dns_issues=()

    # Build domain list to check
    local domains_to_check=("$DOMAIN")
    [ -n "${DOMAIN_INTERNAL:-}" ] && domains_to_check+=("$DOMAIN_INTERNAL")
    [ -n "${DOMAIN_PUBLIC:-}" ] && domains_to_check+=("$DOMAIN_PUBLIC")

    # Check each domain
    for domain in "${domains_to_check[@]}"; do
        log_info "Checking DNS for: ${domain}"

        local domain_ip=$(dig +short "$domain" A | tail -1)

        if [ -z "$domain_ip" ]; then
            log_error "DNS NOT CONFIGURED for ${domain}"
            log_error "  Please add A record: ${domain} -> ${server_ipv4}"
            dns_ok=false
            dns_issues+=("$domain: not configured")
        elif [ "$domain_ip" != "$server_ipv4" ]; then
            log_error "DNS MISMATCH for ${domain}"
            log_error "  Expected: ${server_ipv4}"
            log_error "  Got:      ${domain_ip}"
            dns_ok=false
            dns_issues+=("$domain: points to wrong IP")
        else
            log_success "DNS OK for ${domain} -> ${server_ipv4}"
        fi
    done

    if [ "$dns_ok" = false ]; then
        echo ""
        log_error "DNS configuration issues detected:"
        for issue in "${dns_issues[@]}"; do
            log_error "  - $issue"
        done
        echo ""
        log_error "DEPLOYMENT STOPPED: Fix DNS configuration before deploying"
        log_error "Deployment cannot proceed without proper DNS configuration"
        return 1
    fi

    log_success "All DNS records configured correctly"
    return 0
}

# Check and update nginx configuration if template changed
check_and_update_nginx() {
    log_info "=== Nginx Configuration Sync ==="

    local nginx_config="/etc/nginx/sites-available/$APP_NAME"

    # Check if nginx config exists
    if [ ! -f "$nginx_config" ]; then
        log_warning "Nginx config not found - run setup.sh first"
        return 0
    fi

    # Use per-app template (same location as setup.sh uses)
    local nginx_template="$SCRIPT_DIR/nginx.conf.template"

    if [ ! -f "$nginx_template" ]; then
        log_info "Nginx template not found (${nginx_template}), skipping sync"
        return 0
    fi

    # Generate what the config SHOULD be
    local temp_config="/tmp/nginx_${APP_NAME}_check.conf"

    # Build upstream servers list
    local UPSTREAM_SERVERS=""
    for i in $(seq 0 $((DEFAULT_SCALE - 1))); do
        local port=$((BASE_PORT + i))
        UPSTREAM_SERVERS="${UPSTREAM_SERVERS}    server localhost:${port} max_fails=3 fail_timeout=30s;\n"
    done

    # Generate config from template
    sed "s/{{APP_NAME}}/$APP_NAME/g" "$nginx_template" | \
    sed "s/{{NGINX_UPSTREAM_NAME}}/${APP_NAME}_backend/g" | \
    sed "s|{{DOMAIN}}|$DOMAIN|g" | \
    sed "s|{{DOMAIN_INTERNAL}}|${DOMAIN_INTERNAL:-}|g" | \
    sed "s|{{DOMAIN_PUBLIC}}|${DOMAIN_PUBLIC:-}|g" | \
    sed "s|{{HEALTH_CHECK_PATH}}|${HEALTH_CHECK_PATH:-/up}|g" | \
    sed "s|{{CONTAINER_PORT}}|${CONTAINER_PORT:-3000}|g" | \
    perl -pe "BEGIN{undef $/;} s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|gs" > "$temp_config"

    # Compare with existing config (ignore comments and empty lines)
    local current_hash=$(grep -v '^#' "$nginx_config" 2>/dev/null | grep -v '^[[:space:]]*$' | md5sum | cut -d' ' -f1)
    local new_hash=$(grep -v '^#' "$temp_config" | grep -v '^[[:space:]]*$' | md5sum | cut -d' ' -f1)

    if [ "$current_hash" = "$new_hash" ]; then
        log_info "Nginx config is up to date"
        rm -f "$temp_config"
        return 0
    fi

    log_warning "Nginx config has changed, updating..."

    # Backup current config
    sudo cp "$nginx_config" "${nginx_config}.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Backed up current config"

    # Install new config
    sudo cp "$temp_config" "$nginx_config"
    rm -f "$temp_config"

    # Test nginx configuration
    log_info "Testing nginx configuration..."
    local nginx_test_output=$(sudo nginx -t 2>&1)
    if echo "$nginx_test_output" | grep -q "successful"; then
        sudo systemctl reload nginx
        log_success "Nginx config updated and reloaded"
    else
        log_error "Nginx configuration test failed:"
        echo "$nginx_test_output"

        log_info "Restoring backup..."
        local latest_backup=$(ls -t "${nginx_config}.backup."* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            sudo cp "$latest_backup" "$nginx_config"
            sudo systemctl reload nginx
            log_warning "Restored previous nginx config"
        fi
        return 1
    fi

    return 0
}

# ==============================================================================
# GENERIC DEPLOYMENT WORKFLOW
# ==============================================================================

# Function: Main deployment workflow that works for any app type
deploy_application() {
    local scale="$1"
    local image_tag="$(date +%Y%m%d_%H%M%S)"
    local migrations_run="false"
    local deployment_start_time=$(date +%s)
    local git_commit="N/A"

    log_info "Starting deployment of ${APP_DISPLAY_NAME}"
    log_info "Application Type: ${APP_TYPE}"

    # Validate app type module exists
    local app_type_module="$DEVOPS_DIR/common/app-types/${APP_TYPE}.sh"
    if [ ! -f "$app_type_module" ]; then
        log_error "App type module not found: ${app_type_module}"
        send_deployment_failure_notification "App type module not found: ${app_type_module}"
        return 1
    fi

    # Load app-type specific module
    source "$app_type_module"

    # Load email notification module
    if [ -f "$DEVOPS_DIR/common/email-notification.sh" ]; then
        source "$DEVOPS_DIR/common/email-notification.sh"
    fi

    # PRE-DEPLOYMENT CHECKS (run before any work)

    # Update DevOps repository to get latest templates and scripts
    if ! update_devops_repo; then
        send_deployment_failure_notification "Failed to update DevOps repository"
        return 1
    fi

    # Check DNS configuration - STOP if not configured
    if ! check_dns_configuration; then
        send_deployment_failure_notification "DNS configuration check failed"
        return 1
    fi

    # Check and update nginx config if changed
    if ! check_and_update_nginx; then
        send_deployment_failure_notification "Failed to update nginx configuration"
        return 1
    fi

    # Step 1: Pull latest code (app-type specific)
    if ! ${APP_TYPE}_pull_code; then
        send_deployment_failure_notification "Failed to pull latest code from repository"
        return 1
    fi

    # Get git commit hash for the notification
    if [ -d "$REPO_DIR/.git" ]; then
        git_commit=$(cd "$REPO_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "N/A")
    fi

    # Send deployment start notification (after we have git commit)
    send_deployment_start_notification "$git_commit"

    # Step 2: Build Docker image (app-type specific)
    if ! ${APP_TYPE}_build_image "$image_tag"; then
        send_deployment_failure_notification "Docker image build failed"
        return 1
    fi

    # Step 3: Check if any containers are running
    local current_count=$(get_container_count "$APP_NAME")

    if [ $current_count -eq 0 ]; then
        # No containers running - fresh deployment
        log_info "No existing containers found, deploying fresh with ${scale} container(s)"
        if ! ${APP_TYPE}_deploy_fresh "$scale" "$image_tag"; then
            send_deployment_failure_notification "Fresh deployment failed"
            return 1
        fi
        actual_scale="$scale"

        # For Rails, migrations run during fresh deployment
        if [ "$APP_TYPE" = "rails" ] && [ "$MIGRATION_BACKUP_ENABLED" = "true" ]; then
            migrations_run="true"
        fi
    else
        # Containers already running - rolling restart
        log_info "Found ${current_count} running container(s), will restart all of them"
        if ! ${APP_TYPE}_deploy_rolling "$current_count" "$image_tag"; then
            send_deployment_failure_notification "Rolling restart failed during container replacement"
            return 1
        fi
        actual_scale="$current_count"

        # For Rails, check if migrations were run
        if [ "$APP_TYPE" = "rails" ]; then
            migrations_run="${RAILS_MIGRATIONS_RUN:-false}"
        fi
    fi

    # Step 4: Clean up old images
    if [ "$AUTO_CLEANUP_ENABLED" = "true" ]; then
        cleanup_old_images "$DOCKER_IMAGE_NAME" "$MAX_IMAGE_VERSIONS"
    fi

    # Step 5: Check and setup SSL if needed (automated SSL management)
    export SSL_SETUP_STATUS="unknown"
    export SSL_SETUP_MESSAGE=""
    check_and_setup_ssl
    ssl_result=$?
    if [ $ssl_result -eq 0 ]; then
        export SSL_SETUP_STATUS="success"
    elif [ $ssl_result -eq 2 ]; then
        export SSL_SETUP_STATUS="failed"
    else
        export SSL_SETUP_STATUS="skipped"
    fi

    # Step 6: Log deployment
    echo "[$(date)] Deployed ${DOCKER_IMAGE_NAME}:${image_tag} with scale=${actual_scale}$([ "$APP_TYPE" = "rails" ] && echo ", migrations=${migrations_run}") ssl=${SSL_SETUP_STATUS}" >> "${LOG_DIR}/deployments.log"

    log_success "Deployment completed successfully!"

    # Step 7: Display summary (app-type specific)
    if [ "$APP_TYPE" = "rails" ]; then
        ${APP_TYPE}_display_deployment_summary "$actual_scale" "$image_tag" "$migrations_run"
    else
        ${APP_TYPE}_display_deployment_summary "$actual_scale" "$image_tag"
    fi

    # Step 8: Send success notification email
    send_deployment_success_notification "$actual_scale" "$image_tag" "$migrations_run" "$git_commit"

    return 0
}

# Function: Send deployment start notification
send_deployment_start_notification() {
    local git_commit="$1"

    # Check if email notification function exists and is enabled
    if [ "${DEPLOYMENT_EMAIL_ENABLED:-true}" != "true" ]; then
        return 0
    fi

    if declare -f send_deployment_start_email > /dev/null 2>&1; then
        # Send email in background with timeout (errors logged to /tmp/email_error.log)
        ( send_deployment_start_email "$APP_NAME" "$APP_DISPLAY_NAME" "${DOMAIN:-$APP_NAME}" "$git_commit" 2>/tmp/email_error_$$.log & EMAIL_PID=$!; sleep 15 && kill $EMAIL_PID 2>/dev/null ) || true
    fi
}

# Function: Send deployment success notification
send_deployment_success_notification() {
    local scale="$1"
    local image_tag="$2"
    local migrations_run="$3"
    local git_commit="$4"

    # Check if email notification function exists and is enabled
    if [ "${DEPLOYMENT_EMAIL_ENABLED:-true}" != "true" ]; then
        return 0
    fi

    if declare -f send_deployment_success_email > /dev/null 2>&1; then
        # Send email in background with timeout (errors logged to /tmp/email_error.log)
        ( send_deployment_success_email "$APP_NAME" "$APP_DISPLAY_NAME" "${DOMAIN:-$APP_NAME}" "$scale" "$image_tag" "$migrations_run" "$git_commit" 2>/tmp/email_error_$$.log & EMAIL_PID=$!; sleep 15 && kill $EMAIL_PID 2>/dev/null ) || true
    fi
}

# Function: Send deployment failure notification
send_deployment_failure_notification() {
    local error_message="$1"

    # Check if email notification function exists and is enabled
    if [ "${DEPLOYMENT_EMAIL_ENABLED:-true}" != "true" ]; then
        return 0
    fi

    if declare -f send_deployment_failure_email > /dev/null 2>&1; then
        # Send email in background with timeout (errors logged to /tmp/email_error.log)
        ( send_deployment_failure_email "$APP_NAME" "$APP_DISPLAY_NAME" "$error_message" 2>/tmp/email_error_$$.log & EMAIL_PID=$!; sleep 15 && kill $EMAIL_PID 2>/dev/null ) || true
    fi
}

# Function: Restart application
restart_application() {
    local scale="$1"

    log_info "Restarting ${APP_DISPLAY_NAME} with scale=${scale}"

    # Load app-type specific module
    source "$DEVOPS_DIR/common/app-types/${APP_TYPE}.sh"

    # Get current image
    local current_image="${DOCKER_IMAGE_NAME}:latest"

    # Check if image exists
    if ! docker image inspect "$current_image" > /dev/null 2>&1; then
        log_error "Image ${current_image} not found. Please run deploy first."
        return 1
    fi

    # Perform rolling restart for web containers
    rolling_restart "$APP_NAME" "$current_image" "$ENV_FILE" "$BASE_PORT" "$scale" "$CONTAINER_PORT"

    if [ $? -ne 0 ]; then
        log_error "Restart failed"
        return 1
    fi

    # For Rails, also restart workers and scheduler
    if [ "$APP_TYPE" = "rails" ]; then
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

        # Restart scheduler container if enabled
        if [ "${SCHEDULER_ENABLED:-false}" = "true" ]; then
            log_info "Restarting scheduler container..."
            local scheduler_name="${APP_NAME}_scheduler"

            # Stop old scheduler
            if docker ps -a --filter "name=${scheduler_name}" --format "{{.Names}}" | grep -q "^${scheduler_name}$"; then
                stop_container "$scheduler_name"
            fi

            # Start new scheduler
            start_scheduler_container "$scheduler_name" "$current_image" "$ENV_FILE"

            if [ $? -ne 0 ]; then
                log_error "Failed to start scheduler ${scheduler_name}"
                return 1
            fi
            log_success "Scheduler container restarted successfully"
        fi
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
    scale_application "$APP_NAME" "$current_image" "$ENV_FILE" "$BASE_PORT" "$target_scale" "$CONTAINER_PORT"

    if [ $? -ne 0 ]; then
        log_error "Scaling failed"
        return 1
    fi

    log_success "Scaling completed successfully (${old_scale} -> ${target_scale})"
    return 0
}

# Function: Stop application
stop_application() {
    # Load app-type specific module
    source "$DEVOPS_DIR/common/app-types/${APP_TYPE}.sh"

    # Use app-type specific stop function
    ${APP_TYPE}_stop_containers
    return $?
}

# Function: List available image versions for rollback
list_image_versions() {
    log_info "Available Docker images for ${APP_DISPLAY_NAME}:"
    echo ""

    # Get all images with timestamps (excluding latest)
    local images=$(docker images "${DOCKER_IMAGE_NAME}" --format "{{.Tag}}\t{{.CreatedAt}}\t{{.Size}}" | grep -v "^latest" | sort -r)

    if [ -z "$images" ]; then
        log_warning "No previous versions found"
        echo ""
        echo "Previous images may have been cleaned up. To preserve images for rollback:"
        echo "  - Set AUTO_CLEANUP_ENABLED=false in config.sh"
        echo "  - Or increase MAX_IMAGE_VERSIONS in config.sh"
        return 1
    fi

    # Print header
    printf "%-3s  %-20s  %-20s  %-10s\n" "#" "VERSION (TAG)" "CREATED" "SIZE"
    echo "--------------------------------------------------------------"

    # Print images with index
    local index=1
    echo "$images" | while IFS=$'\t' read -r tag created size; do
        printf "%-3s  %-20s  %-20s  %-10s\n" "$index" "$tag" "$created" "$size"
        index=$((index + 1))
    done

    echo ""
    return 0
}

# Function: Get currently deployed image tag
get_current_image_tag() {
    # Check first running container to see what version is deployed
    local first_container="${APP_NAME}_web_1"

    if docker ps --filter "name=^${first_container}$" --format "{{.Names}}" | grep -q "^${first_container}$"; then
        local current_image=$(docker inspect -f '{{.Image}}' "$first_container" 2>/dev/null)
        local current_tag=$(docker inspect -f '{{index .Config.Image}}' "$first_container" 2>/dev/null | cut -d':' -f2)

        if [ -n "$current_tag" ] && [ "$current_tag" != "latest" ]; then
            echo "$current_tag"
            return 0
        fi
    fi

    # Fallback: check what :latest points to
    local latest_id=$(docker images "${DOCKER_IMAGE_NAME}:latest" --format "{{.ID}}" 2>/dev/null | head -1)
    if [ -n "$latest_id" ]; then
        docker images "${DOCKER_IMAGE_NAME}" --format "{{.Tag}}\t{{.ID}}" | grep "$latest_id" | grep -v "^latest" | cut -f1 | head -1
    fi
}

# Function: Rollback to a specific version
rollback_to_version() {
    local target_tag="$1"
    local current_tag=$(get_current_image_tag)

    log_header "Rolling Back ${APP_DISPLAY_NAME}"

    # Verify target image exists
    if ! docker image inspect "${DOCKER_IMAGE_NAME}:${target_tag}" >/dev/null 2>&1; then
        log_error "Image ${DOCKER_IMAGE_NAME}:${target_tag} not found"
        return 1
    fi

    log_info "Current version: ${current_tag:-unknown}"
    log_info "Target version:  ${target_tag}"
    echo ""

    # Confirmation
    read -p "Continue with rollback? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Rollback cancelled"
        return 0
    fi

    # Tag the target version as latest
    log_info "Tagging ${DOCKER_IMAGE_NAME}:${target_tag} as latest..."
    docker tag "${DOCKER_IMAGE_NAME}:${target_tag}" "${DOCKER_IMAGE_NAME}:latest"

    if [ $? -ne 0 ]; then
        log_error "Failed to tag image"
        return 1
    fi

    # Get current scale
    local current_count=$(get_container_count "$APP_NAME")

    if [ $current_count -eq 0 ]; then
        log_warning "No containers currently running"
        log_info "Use './deploy.sh deploy' to start containers with rolled back version"
        return 0
    fi

    # Perform rolling restart with the target version
    log_info "Performing rolling restart to version ${target_tag}..."

    # Load app-type specific module
    source "$DEVOPS_DIR/common/app-types/${APP_TYPE}.sh"

    local current_image="${DOCKER_IMAGE_NAME}:latest"

    # Perform rolling restart
    rolling_restart "$APP_NAME" "$current_image" "$ENV_FILE" "$BASE_PORT" "$current_count" "$CONTAINER_PORT"

    if [ $? -ne 0 ]; then
        log_error "Rollback failed during rolling restart"
        log_warning "System may be in inconsistent state"
        log_info "Check status: ./deploy.sh status"
        return 1
    fi

    # Log rollback
    echo "[$(date)] Rolled back from ${current_tag:-unknown} to ${target_tag}" >> "${LOG_DIR}/deployments.log"

    log_success "Rollback completed successfully!"
    echo ""
    echo "Summary:"
    echo "  Previous version: ${current_tag:-unknown}"
    echo "  Current version:  ${target_tag}"
    echo "  Running containers: ${current_count}"
    echo ""
    echo "To verify:"
    echo "  ./deploy.sh status"
    echo "  curl https://${DOMAIN}"
    echo ""

    return 0
}

# Function: Interactive rollback
handle_rollback() {
    log_header "Rollback ${APP_DISPLAY_NAME}"

    # Show current version
    local current_tag=$(get_current_image_tag)
    if [ -n "$current_tag" ]; then
        log_info "Currently deployed version: ${current_tag}"
        echo ""
    fi

    # List available versions
    if ! list_image_versions; then
        return 1
    fi

    # Get user selection
    echo "Enter the version number to rollback to (or 'cancel' to abort):"
    read -p "> " selection

    if [ "$selection" = "cancel" ] || [ -z "$selection" ]; then
        log_info "Rollback cancelled"
        return 0
    fi

    # Validate selection is a number
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        log_error "Invalid selection. Please enter a number."
        return 1
    fi

    # Get the tag for the selected version
    local images_array=($(docker images "${DOCKER_IMAGE_NAME}" --format "{{.Tag}}" | grep -v "^latest" | sort -r))
    local target_index=$((selection - 1))

    if [ $target_index -lt 0 ] || [ $target_index -ge ${#images_array[@]} ]; then
        log_error "Invalid selection. Please choose a number from the list."
        return 1
    fi

    local target_tag="${images_array[$target_index]}"

    # Perform rollback
    rollback_to_version "$target_tag"
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

# Function: Check and setup SSL certificates if missing or invalid
# This function is called automatically during deployment to ensure SSL is always configured
# It will:
# - Check if certificates exist and are valid
# - Verify certificates are not expiring soon (within 30 days)
# - Automatically obtain new certificates if missing (when DNS is configured)
# - Skip if DNS is not configured or certbot account doesn't exist
check_and_setup_ssl() {
    log_info "=== Automated SSL Certificate Management ==="
    log_info "Checking SSL certificates for ${DOMAIN}..."

    # Check if certbot is installed
    if ! command -v certbot >/dev/null 2>&1; then
        log_warning "Certbot not installed, skipping automated SSL check"
        log_info "Install certbot: sudo apt-get install certbot python3-certbot-nginx"
        export SSL_SETUP_MESSAGE="Certbot not installed"
        return 1  # Skipped
    fi

    # Build domain list for certbot
    local cert_domains="-d $DOMAIN"
    local all_domains="$DOMAIN"
    local all_domains_array=("$DOMAIN")

    # Add www subdomain for non-API domains
    if [[ ! "$DOMAIN" =~ ^api ]]; then
        cert_domains="$cert_domains -d www.$DOMAIN"
        all_domains="$all_domains, www.$DOMAIN"
        all_domains_array+=("www.$DOMAIN")
    fi

    # Check if additional domains are defined (e.g., DOMAIN_INTERNAL)
    if [ -n "${DOMAIN_INTERNAL:-}" ]; then
        cert_domains="$cert_domains -d $DOMAIN_INTERNAL"
        all_domains="$all_domains, $DOMAIN_INTERNAL"
        all_domains_array+=("$DOMAIN_INTERNAL")
    fi

    # Check if certificate already exists
    if sudo certbot certificates 2>/dev/null | grep -q "Certificate Name: ${DOMAIN}"; then
        log_success "SSL certificate exists for ${DOMAIN}"

        # Check if certificate covers all required domains
        local cert_domains_list=$(sudo certbot certificates 2>/dev/null | grep -A 10 "Certificate Name: ${DOMAIN}" | grep "Domains:" | sed 's/.*Domains: //')
        local missing_domains=()

        for required_domain in "${all_domains_array[@]}"; do
            if ! echo "$cert_domains_list" | grep -q "$required_domain"; then
                missing_domains+=("$required_domain")
            fi
        done

        if [ ${#missing_domains[@]} -gt 0 ]; then
            log_warning "Certificate missing domains: ${missing_domains[*]}"
            log_info "Automatically expanding certificate to include missing domains..."

            # Build certbot expand command with --cert-name to expand existing cert
            # MUST include ALL domains (existing + missing) when expanding
            local expand_cmd="sudo certbot --nginx --non-interactive --agree-tos --expand --cert-name ${DOMAIN}"
            for domain in "${all_domains_array[@]}"; do
                expand_cmd="$expand_cmd -d $domain"
            done

            log_info "Running: certbot --nginx --expand --cert-name ${DOMAIN} -d ${all_domains_array[*]}"

            # Run certbot and capture both output and exit code
            set +e  # Temporarily allow command to fail
            $expand_cmd 2>&1 | tee /tmp/certbot_expand_$$.log
            local certbot_exit=$?
            set -e

            if [ $certbot_exit -eq 0 ]; then
                log_success "Certificate expanded to include: ${missing_domains[*]}"
                export SSL_SETUP_MESSAGE="Expanded to include all domains"
                rm -f /tmp/certbot_expand_$$.log
                return 0  # Success
            else
                log_error "Failed to expand certificate (exit code: $certbot_exit)"
                log_error "Certbot output:"
                cat /tmp/certbot_expand_$$.log
                export SSL_SETUP_MESSAGE="Expansion failed (${missing_domains[*]})"
                return 2  # Failed
            fi
        fi

        # Check expiry
        local expiry_date=$(sudo certbot certificates 2>/dev/null | grep -A 10 "Certificate Name: ${DOMAIN}" | grep "Expiry Date" | head -1 | awk '{print $3}')
        if [ -n "$expiry_date" ]; then
            local expiry_ts=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
            local now_ts=$(date +%s)
            local days_left=$(( (expiry_ts - now_ts) / 86400 ))

            if [ $days_left -lt 30 ]; then
                log_warning "Certificate expires in ${days_left} days, certbot will auto-renew"
            else
                log_info "Certificate valid for ${days_left} more days"
            fi
        fi
        export SSL_SETUP_MESSAGE="Valid"
        return 0  # Success
    fi

    # Certificate doesn't exist - try to obtain it
    log_warning "SSL certificate not found for ${DOMAIN}"

    # Check DNS configuration
    log_info "Checking DNS configuration..."
    local server_ipv4=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org)
    local dns_ok=true
    local dns_issues=()

    for domain in $DOMAIN ${DOMAIN_INTERNAL:-}; do
        if [[ ! "$domain" =~ ^www\. ]]; then
            local domain_ip=$(dig +short "$domain" A | tail -1)

            if [ -z "$domain_ip" ]; then
                log_warning "DNS not configured for ${domain}"
                dns_ok=false
                dns_issues+=("$domain: not configured")
            elif [ "$domain_ip" != "$server_ipv4" ]; then
                log_warning "DNS mismatch for ${domain}: points to ${domain_ip}, server is ${server_ipv4}"
                dns_ok=false
                dns_issues+=("$domain: wrong IP")
            fi
        fi
    done

    if [ "$dns_ok" = false ]; then
        log_warning "DNS not properly configured. Skipping SSL setup."
        log_info "Configure DNS properly and redeploy to automatically obtain SSL certificates"
        export SSL_SETUP_MESSAGE="Skipped - DNS issues: ${dns_issues[*]}"
        return 1  # Skipped
    fi

    # DNS is good, try to get certificate
    log_info "Obtaining SSL certificates for: ${all_domains}"

    # Try to get email from existing certbot registration
    local existing_email=$(sudo certbot show_account 2>/dev/null | grep -oP 'Email contact: \K.*' || echo "")

    if [ -n "$existing_email" ]; then
        log_info "Using existing certbot account: ${existing_email}"

        # Capture certbot output
        local certbot_output=$(mktemp)
        if sudo certbot --nginx \
            $cert_domains \
            --email "${existing_email}" \
            --non-interactive \
            --agree-tos \
            --expand \
            --redirect 2>&1 | tee "$certbot_output"; then
            log_success "SSL certificates obtained successfully"
            log_success "HTTPS now available at: https://${DOMAIN}"
            export SSL_SETUP_MESSAGE="Successfully obtained"
            rm -f "$certbot_output"
            return 0  # Success
        else
            local error_msg=$(grep -i "error\|failed\|problem" "$certbot_output" | head -3 | tr '\n' '; ')
            log_error "SSL certificate setup FAILED"
            log_error "Error: ${error_msg}"
            log_info "Check DNS configuration and redeploy to automatically retry"
            export SSL_SETUP_MESSAGE="FAILED: ${error_msg}"
            rm -f "$certbot_output"
            return 2  # Failed
        fi
    else
        log_warning "No existing certbot account found"
        log_info "Run certbot manually to create account: sudo certbot --nginx -d ${DOMAIN}"
        export SSL_SETUP_MESSAGE="Skipped - No certbot account"
        return 1  # Skipped
    fi
}

# Function: Update nginx upstream configuration when scaling
update_nginx_upstream() {
    local new_scale="$1"

    log_info "Updating Nginx upstream configuration for ${new_scale} web containers..."

    local nginx_template="$SCRIPT_DIR/nginx.conf.template"
    local nginx_config="/etc/nginx/sites-available/$APP_NAME"

    if [ ! -f "$nginx_template" ]; then
        log_error "Nginx template not found: ${nginx_template}"
        return 1
    fi

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
    perl -pe "
        s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g;
        s|{{DOMAIN}}|${DOMAIN}|g;
        s|{{APP_NAME}}|${APP_NAME}|g;
    " "$nginx_template" | \
    perl -pe "BEGIN{undef $/;} s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|gs" | \
    sudo tee "$nginx_config" > /dev/null

    # Test nginx configuration
    if sudo nginx -t 2>&1 | grep -q "successful"; then
        sudo systemctl reload nginx
        log_success "Nginx configuration updated successfully"
        log_info "Nginx now routing to ${new_scale} containers (ports ${BASE_PORT}-$((BASE_PORT + new_scale - 1)))"

        # Check SSL after nginx config change
        export SSL_SETUP_STATUS="unknown"
        export SSL_SETUP_MESSAGE=""
        check_and_setup_ssl
        ssl_result=$?
        if [ $ssl_result -eq 0 ]; then
            export SSL_SETUP_STATUS="success"
        elif [ $ssl_result -eq 2 ]; then
            export SSL_SETUP_STATUS="failed"
            log_error "SSL setup failed after nginx configuration update"
        else
            export SSL_SETUP_STATUS="skipped"
        fi

        return 0
    else
        log_error "Nginx configuration test failed, restoring backup"
        sudo mv "${nginx_config}.backup" "$nginx_config"
        sudo systemctl reload nginx
        return 1
    fi
}

# ==============================================================================
# COMMAND HANDLER
# ==============================================================================

# Function: Handle command-line arguments
handle_deploy_command() {
    local command="${1:-deploy}"

    case "$command" in
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
        rollback)
            handle_rollback
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
        console)
            if [ "$APP_TYPE" != "rails" ]; then
                log_error "Console command is only available for Rails applications"
                exit 1
            fi
            local container_name="${APP_NAME}_web_1"
            if ! docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
                log_error "Container ${container_name} is not running"
                exit 1
            fi
            log_info "Starting Rails console in ${container_name}..."
            docker exec -it "$container_name" /bin/bash -c "cd /app && bundle exec rails console"
            ;;
        help|*)
            echo "${APP_DISPLAY_NAME} Deployment Script"
            echo ""
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "Commands:"
            echo "  deploy              Pull latest code, build, and deploy application"
            echo "  restart             Restart all running containers with current image"
            echo "  stop                Stop all containers"
            echo "  rollback            Rollback to a previous version (interactive)"
            echo "  scale <N>           Scale web containers to N instances (1-10)"
            echo "  status              Show status of all containers"
            echo "  logs [container]    Show logs (default: ${APP_NAME}_web_1)"
            if [ "$APP_TYPE" = "rails" ]; then
                echo "  console             Open Rails console"
            fi
            echo "  help                Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 deploy           # Deploy latest code"
            echo "  $0 rollback         # Rollback to previous version"
            echo "  $0 scale 3          # Scale to 3 web containers"
            echo "  $0 status           # Show container status"
            echo "  $0 logs web_2       # Show logs for web_2"
            echo ""
            exit 0
            ;;
    esac
}
