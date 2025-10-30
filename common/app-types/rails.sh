#!/bin/bash

# Rails Application Type Module
# Location: /home/andrzej/DevOps/common/app-types/rails.sh
# This module provides Rails-specific setup and deployment hooks

# Export app type for identification
export APP_TYPE="rails"

# ==============================================================================
# SETUP HOOKS
# ==============================================================================

# Hook: Check Rails prerequisites
rails_check_prerequisites() {
    log_info "Checking Rails prerequisites..."

    if ! command_exists psql; then
        log_error "PostgreSQL is not installed. Please run ubuntu-init-setup.sh first."
        return 1
    fi

    if ! command_exists redis-cli; then
        log_error "Redis is not installed. Please run ubuntu-init-setup.sh first."
        return 1
    fi

    if ! redis-cli ping > /dev/null 2>&1; then
        log_error "Redis is not running. Please start Redis service."
        return 1
    fi

    log_success "All Rails prerequisites are installed"
    return 0
}

# Hook: Setup Rails database
rails_setup_database() {
    log_info "Setting up Rails database..."

    # Generate database user name from app name
    DB_APP_USER="${APP_NAME//-/_}_user"

    # Generate strong password for database user
    DB_APP_PASSWORD=$(get_or_generate_secret "$ENV_FILE" "DB_PASSWORD" "openssl rand -base64 32 | tr -d '/+=' | head -c 32")

    log_info "Database user will be: ${DB_APP_USER}"

    # Create database user if it doesn't exist, or reset password if it does
    if ! check_db_user_exists "$DB_APP_USER"; then
        create_db_user "$DB_APP_USER" "$DB_APP_PASSWORD"
        if [ $? -ne 0 ]; then
            log_error "Failed to create database user"
            return 1
        fi
    else
        log_info "Database user ${DB_APP_USER} already exists"
        # Reset password to match the one in .env file
        reset_db_user_password "$DB_APP_USER" "$DB_APP_PASSWORD"
        if [ $? -ne 0 ]; then
            log_error "Failed to reset database user password"
            return 1
        fi
    fi

    # Create database if it doesn't exist
    if ! check_database_exists "$DB_NAME"; then
        create_database "$DB_NAME"
        if [ $? -ne 0 ]; then
            log_error "Failed to create database"
            return 1
        fi

        # Grant privileges to the app user
        grant_database_privileges "$DB_NAME" "$DB_APP_USER"
        if [ $? -ne 0 ]; then
            log_error "Failed to grant database privileges"
            return 1
        fi
    else
        log_info "Database ${DB_NAME} already exists"
        # Still grant privileges in case user was created after database
        grant_database_privileges "$DB_NAME" "$DB_APP_USER"
    fi

    # Generate database URL with dedicated user
    DATABASE_URL="postgresql://${DB_APP_USER}:${DB_APP_PASSWORD}@localhost/${DB_NAME}"

    # Export for use in env file creation
    export DB_APP_USER
    export DB_APP_PASSWORD
    export DATABASE_URL

    log_success "Database configured: ${DB_NAME}"
    log_success "Database user: ${DB_APP_USER}"
    log_info "Database password stored in .env.production"
    return 0
}

# Hook: Create Rails environment file
rails_create_env_file() {
    log_info "Creating Rails environment file: ${ENV_FILE}"

    # Check if we need to preserve existing SECRET_KEY_BASE
    EXISTING_SECRET=""
    if [ -f "$ENV_FILE" ]; then
        log_warning "Environment file already exists. Backing up..."
        EXISTING_SECRET=$(grep "^SECRET_KEY_BASE=" "$ENV_FILE" 2>/dev/null | cut -d '=' -f2-)
        cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Generate or reuse SECRET_KEY_BASE
    if [ -n "$EXISTING_SECRET" ]; then
        SECRET_KEY_BASE="$EXISTING_SECRET"
        log_info "Reusing existing SECRET_KEY_BASE"
    else
        SECRET_KEY_BASE=$(openssl rand -hex 64)
        log_info "Generated new SECRET_KEY_BASE"
    fi

    # Create production env file
    cat > "$ENV_FILE" << EOF
# Production Environment Variables for ${APP_NAME}
# Generated on $(date)
# Location: ${ENV_FILE}

# Database Configuration
# Database: ${DB_NAME}
# Database User: ${DB_APP_USER}
DATABASE_URL=${DATABASE_URL}

# Database credentials (for reference - DO NOT commit to git)
DB_NAME=${DB_NAME}
DB_USER=${DB_APP_USER}
DB_PASSWORD=${DB_APP_PASSWORD}

# Rails Configuration
SECRET_KEY_BASE=${SECRET_KEY_BASE}
RAILS_ENV=production
RAILS_SERVE_STATIC_FILES=true

# Redis Configuration (Dedicated database)
REDIS_URL=${REDIS_URL:-redis://localhost:6379/0}

# Redis Streams Configuration (for async scraper data ingestion)
# Enable consumers for cheaperfordrug-api only
ENABLE_REDIS_STREAM_CONSUMERS=${ENABLE_REDIS_STREAM_CONSUMERS:-false}
REDIS_STREAM_CONSUMER_COUNT=${REDIS_STREAM_CONSUMER_COUNT:-3}
REDIS_STREAM_BATCH_SIZE=${REDIS_STREAM_BATCH_SIZE:-10}
REDIS_STREAM_BLOCK_MS=${REDIS_STREAM_BLOCK_MS:-5000}
REDIS_STREAM_MAX_ITERATIONS=${REDIS_STREAM_MAX_ITERATIONS:-1000}
REDIS_STREAMS_URL=${REDIS_STREAMS_URL:-redis://localhost:6379/3}
REDIS_STREAM_ALERT_THRESHOLD=${REDIS_STREAM_ALERT_THRESHOLD:-1000}

# Mailgun Configuration (for application emails)
MAILGUN_API_KEY=${MAILGUN_API_KEY:-dummy_mailgun_key}
MAILGUN_DOMAIN=${MAILGUN_DOMAIN:-mg.example.com}
MAILGUN_FROM_EMAIL=${MAILGUN_FROM_EMAIL:-noreply@example.com}
MAIL_DELIVERY_METHOD=mailgun_api

# Application Port
PORT=${CONTAINER_PORT:-3000}
WEB_CONCURRENCY=2
RAILS_MAX_THREADS=5

# CORS Configuration
# Allowed origins for API requests (comma-separated)
# Update with your actual frontend domain(s)
ALLOWED_ORIGINS=https://example.com,https://www.example.com

# App-specific environment variables
# Add your custom variables below:

EOF

    # Validate that SECRET_KEY_BASE was written
    if grep -q "^SECRET_KEY_BASE=.\+" "$ENV_FILE"; then
        log_success "SECRET_KEY_BASE generated and written to env file"
    else
        log_error "Failed to write SECRET_KEY_BASE to env file"
        return 1
    fi

    log_success "Environment file created: ${ENV_FILE}"
    log_info "Database URL: postgresql://${DB_APP_USER}:***@localhost/${DB_NAME}"
    log_warning "IMPORTANT: Edit ${ENV_FILE} and update the credentials marked with dummy_ or your_ prefixes!"

    return 0
}

# Hook: Setup Rails-specific requirements
rails_setup_requirements() {
    log_info "Setting up Rails-specific requirements..."

    # Copy Dockerfile and .dockerignore from DevOps template
    log_info "Copying Docker files from template..."
    cp "$DEVOPS_DIR/common/rails/Dockerfile.template" "$REPO_DIR/Dockerfile"

    if [ -f "$DEVOPS_DIR/common/rails/.dockerignore.template" ]; then
        cp "$DEVOPS_DIR/common/rails/.dockerignore.template" "$REPO_DIR/.dockerignore"
    fi

    # Setup native Rails environment for console access
    log_info "Setting up native Rails environment for console access..."
    cd "$REPO_DIR"

    # Check Ruby version
    REQUIRED_RUBY_VERSION=$(cat .ruby-version 2>/dev/null || echo "3.4.4")
    CURRENT_RUBY_VERSION=$(ruby -v | grep -oP '\d+\.\d+\.\d+' | head -1 2>/dev/null || echo "unknown")

    log_info "Required Ruby version: ${REQUIRED_RUBY_VERSION}"
    log_info "Current Ruby version: ${CURRENT_RUBY_VERSION}"

    # Warn if Ruby version mismatch
    if [ "$CURRENT_RUBY_VERSION" != "$REQUIRED_RUBY_VERSION" ]; then
        log_warning "Ruby version mismatch! Required: ${REQUIRED_RUBY_VERSION}, Current: ${CURRENT_RUBY_VERSION}"
        log_warning "Gems may not install correctly. Consider upgrading Ruby to ${REQUIRED_RUBY_VERSION}"
    fi

    # Install bundler if not present
    if ! command_exists bundle; then
        log_info "Installing bundler..."
        gem install bundler 2>/dev/null || log_warning "Could not install bundler (may need manual installation)"
    fi

    # Configure bundler to use .bundle/vendor
    if command_exists bundle; then
        log_info "Configuring bundler to use .bundle/vendor..."
        bundle config set --local path '.bundle/vendor'
        bundle config set --local without 'development test'

        # Install application gems for production use
        log_info "Installing application gems (this may take a few minutes)..."
        RAILS_ENV=production bundle install 2>&1 | grep -v "^Fetching" || log_warning "Gem installation had issues (non-critical)"

        # Create symlink to .env.production for easier access
        ln -sf "$ENV_FILE" "${REPO_DIR}/.env.production"
        log_success "Created symlink: ${REPO_DIR}/.env.production -> ${ENV_FILE}"
    else
        log_warning "Bundler not available, skipping gem installation"
    fi

    # Ensure log directory exists in repo for Rails file logging
    if [ ! -d "${REPO_DIR}/log" ]; then
        mkdir -p "${REPO_DIR}/log"
        chmod 777 "${REPO_DIR}/log"  # Allow container's app user to write logs
        log_info "Created log directory: ${REPO_DIR}/log"
    fi

    log_success "Rails setup requirements completed"
    return 0
}

# Hook: Run Rails migrations during setup
rails_run_migrations() {
    log_info "Running database migrations..."
    cd "$REPO_DIR"

    # Load environment variables from .env file properly
    if [ -f "$ENV_FILE" ]; then
        set -a  # Automatically export all variables
        source "$ENV_FILE"
        set +a  # Turn off automatic export
        log_info "Loaded environment variables from $ENV_FILE"
    else
        log_error "Environment file not found: $ENV_FILE"
        return 0  # Don't fail setup
    fi

    export RAILS_ENV=production

    if command_exists bundle; then
        bundle exec rails db:migrate 2>&1 || log_warning "Migrations failed (may need to run manually after fixing env vars)"
        log_success "Migrations completed (or will be run on first deploy)"
    else
        log_info "Bundler not available, migrations will run on first deploy"
    fi

    return 0
}

# ==============================================================================
# DEPLOYMENT HOOKS
# ==============================================================================

# Hook: Pull code for Rails app
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

    # Install/update gems for production use
    if command_exists bundle; then
        log_info "Installing/updating application gems..."

        # Check Ruby version compatibility
        REQUIRED_RUBY_VERSION=$(cat .ruby-version 2>/dev/null || echo "3.4.4")
        CURRENT_RUBY_VERSION=$(ruby -v | grep -oP '\d+\.\d+\.\d+' | head -1 2>/dev/null || echo "unknown")

        if [ "$CURRENT_RUBY_VERSION" != "$REQUIRED_RUBY_VERSION" ] && [ "$CURRENT_RUBY_VERSION" != "unknown" ]; then
            log_warning "Ruby version mismatch! Required: ${REQUIRED_RUBY_VERSION}, Current: ${CURRENT_RUBY_VERSION}"
            log_warning "To fix: Re-run ubuntu-init-setup.sh or manually install Ruby ${REQUIRED_RUBY_VERSION}"
        fi

        # Ensure bundler config is set
        bundle config set --local path '.bundle/vendor'
        bundle config set --local without 'development test'

        # Install gems
        RAILS_ENV=production bundle install --quiet 2>&1 | grep -v "^Fetching" || log_warning "Gem installation completed with warnings"

        # Ensure .env.production symlink exists for console access
        if [ ! -L "${REPO_DIR}/.env.production" ]; then
            ln -sf "$ENV_FILE" "${REPO_DIR}/.env.production"
            log_info "Created symlink: ${REPO_DIR}/.env.production -> ${ENV_FILE}"
        fi

        log_success "Gems installed/updated successfully"
    else
        log_warning "Bundler not available, skipping gem installation"
    fi

    # Ensure log directory exists in repo for Rails file logging
    if [ ! -d "${REPO_DIR}/log" ]; then
        mkdir -p "${REPO_DIR}/log"
        chmod 777 "${REPO_DIR}/log"  # Allow container's app user to write logs
        log_info "Created log directory: ${REPO_DIR}/log"
    fi

    # Export commit for use in notifications
    export CURRENT_COMMIT="$new_commit"
    return 0
}

# Hook: Build Rails Docker image
rails_build_image() {
    local image_tag="$1"

    log_info "Building Rails Docker image with tag: ${image_tag}"

    # Ensure Dockerfile from DevOps template is used (in case git pull overwrote it)
    if [ -f "${DEVOPS_DIR}/common/rails/Dockerfile.template" ]; then
        log_info "Copying Dockerfile from DevOps template..."
        cp "${DEVOPS_DIR}/common/rails/Dockerfile.template" "${REPO_DIR}/Dockerfile"

        if [ -f "${DEVOPS_DIR}/common/rails/.dockerignore.template" ]; then
            cp "${DEVOPS_DIR}/common/rails/.dockerignore.template" "${REPO_DIR}/.dockerignore"
        fi
    fi

    # Build Docker image using common function
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
        cleanup_old_image_backups "$IMAGE_BACKUP_DIR" "${MAX_IMAGE_BACKUPS:-5}"
    fi

    # Create console wrapper script
    rails_create_console_wrapper

    return 0
}

# Create console wrapper script for easy Rails console access
rails_create_console_wrapper() {
    log_info "Creating Rails console wrapper script..."

    cat > "${APP_DIR}/console.sh" << 'CONSOLE_WRAPPER'
#!/bin/bash
cd "$(dirname "$0")/repo"
export RAILS_ENV=production
set -a
source .env.production 2>/dev/null || source ../.env.production
set +a
exec bundle exec rails console "$@"
CONSOLE_WRAPPER

    chmod +x "${APP_DIR}/console.sh"
    log_success "Console wrapper created: ${APP_DIR}/console.sh"

    # Create log viewing wrapper script
    cat > "${APP_DIR}/logs.sh" << 'LOGS_WRAPPER'
#!/bin/bash
# Rails containers write logs to mounted volume at ~/apps/APP_NAME/logs/
LOG_DIR="$(dirname "$0")/logs"
PRODUCTION_LOG="${LOG_DIR}/production.log"

# Check if log file exists
if [ ! -f "$PRODUCTION_LOG" ]; then
    echo "Log file not found: $PRODUCTION_LOG"
    echo ""
    echo "Available logs in ${LOG_DIR}:"
    ls -lh "${LOG_DIR}" 2>/dev/null || echo "  (directory is empty or doesn't exist yet)"
    echo ""
    echo "Logs will be created when the application starts."
    echo "Try running: docker logs APP_NAME_web_1"
    exit 1
fi

# Follow production log
echo "Following production.log..."
echo "Log file: $PRODUCTION_LOG"
echo "Press Ctrl+C to stop"
echo ""
tail -f "$PRODUCTION_LOG"
LOGS_WRAPPER

    chmod +x "${APP_DIR}/logs.sh"
    log_success "Log viewer created: ${APP_DIR}/logs.sh"
}

# Hook: Check for pending Rails migrations
rails_check_pending_migrations() {
    local test_container="$1"

    # Simply call check_pending_migrations - it handles all logging
    check_pending_migrations "$test_container"
    return $?
}

# Hook: Run Rails migrations with backup
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

# Hook: Deploy Rails containers (fresh deployment)
rails_deploy_fresh() {
    local scale="$1"
    local image_tag="$2"

    log_info "No running containers found, starting fresh deployment"

    # Start web containers with host network for database access
    for i in $(seq 1 $scale); do
        local port=$((BASE_PORT + i - 1))
        local container_name="${APP_NAME}_web_${i}"

        start_container "$container_name" "${DOCKER_IMAGE_NAME}:${image_tag}" "$port" "$ENV_FILE" "$CONTAINER_PORT" "host" "/rails/log"

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

    # Always check and run migrations after first container is up
    log_info "Checking for pending migrations..."
    if check_pending_migrations "${APP_NAME}_web_1"; then
        log_info "Running database migrations..."
        run_migrations "${APP_NAME}_web_1"

        if [ $? -ne 0 ]; then
            log_error "Migrations failed"
            return 1
        fi
    fi

    # Start worker containers if configured (also use host network)
    local worker_count="${WORKER_COUNT:-0}"
    if [ $worker_count -gt 0 ]; then
        log_info "Starting ${worker_count} worker container(s)..."
        for i in $(seq 1 $worker_count); do
            local worker_name="${APP_NAME}_worker_${i}"
            start_worker_container "$worker_name" "${DOCKER_IMAGE_NAME}:${image_tag}" "$ENV_FILE" "bundle exec sidekiq" "host" "/rails/log"

            if [ $? -ne 0 ]; then
                log_error "Failed to start worker ${worker_name}"
                return 1
            fi
        done
        log_success "Worker containers started successfully"
    fi

    # Start scheduler container if enabled (also use host network)
    if [ "${SCHEDULER_ENABLED:-false}" = "true" ]; then
        log_info "Starting scheduler container..."
        local scheduler_name="${APP_NAME}_scheduler"
        start_scheduler_container "$scheduler_name" "${DOCKER_IMAGE_NAME}:${image_tag}" "$ENV_FILE" "bundle exec clockwork lib/clock.rb" "host" "/rails/log"

        if [ $? -ne 0 ]; then
            log_error "Failed to start scheduler ${scheduler_name}"
            return 1
        fi
        log_success "Scheduler container started successfully"
    fi

    log_success "Fresh deployment completed successfully"
    return 0
}

# Hook: Deploy Rails containers (rolling restart)
rails_deploy_rolling() {
    local scale="$1"
    local image_tag="$2"

    log_info "Running containers detected, performing zero-downtime deployment"

    # Initialize migrations flag
    export RAILS_MIGRATIONS_RUN="false"

    # Create a test container to check migrations (use host network)
    local test_container="${APP_NAME}_migration_check"

    if [ "$MIGRATION_BACKUP_ENABLED" = "true" ]; then
        docker run -d \
            --name "$test_container" \
            --network host \
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

            # Mark that migrations were run
            export RAILS_MIGRATIONS_RUN="true"
        fi

        docker rm -f "$test_container"
    fi

    # Perform rolling restart for web containers (use host network)
    if [ "$ZERO_DOWNTIME_ENABLED" = "true" ]; then
        rolling_restart "$APP_NAME" "${DOCKER_IMAGE_NAME}:${image_tag}" "$ENV_FILE" "$BASE_PORT" "$scale" "$CONTAINER_PORT" "host"

        if [ $? -ne 0 ]; then
            log_error "Rolling restart failed"
            return 1
        fi

        log_success "Zero-downtime deployment completed successfully"
    fi

    # Restart worker containers if configured (use host network)
    local worker_count="${WORKER_COUNT:-0}"
    if [ $worker_count -gt 0 ]; then
        log_info "Restarting ${worker_count} worker container(s)..."

        # Stop old workers with longer timeout to finish jobs gracefully
        # Sidekiq needs time to finish processing current jobs
        log_info "Stopping workers gracefully (allowing time to finish current jobs)..."

        for i in $(seq 1 $worker_count); do
            local worker_name="${APP_NAME}_worker_${i}"
            if docker ps -a --filter "name=${worker_name}" --format "{{.Names}}" | grep -q "^${worker_name}$"; then
                # Send TSTP signal to stop accepting new jobs (quiet mode)
                log_info "Putting ${worker_name} into quiet mode..."
                docker exec "$worker_name" pkill -TSTP -f sidekiq 2>/dev/null || true
                sleep 2

                # Stop container with extended timeout (default: 90 seconds)
                local worker_timeout="${WORKER_SHUTDOWN_TIMEOUT:-90}"
                log_info "Stopping ${worker_name} (timeout: ${worker_timeout}s)..."
                stop_container "$worker_name" "$worker_timeout"
            fi
        done

        # Start new workers
        for i in $(seq 1 $worker_count); do
            local worker_name="${APP_NAME}_worker_${i}"
            start_worker_container "$worker_name" "${DOCKER_IMAGE_NAME}:${image_tag}" "$ENV_FILE" "bundle exec sidekiq" "host" "/rails/log"

            if [ $? -ne 0 ]; then
                log_error "Failed to start worker ${worker_name}"
                return 1
            fi
        done
        log_success "Worker containers restarted successfully"
    fi

    # Restart scheduler container if enabled (use host network)
    if [ "${SCHEDULER_ENABLED:-false}" = "true" ]; then
        log_info "Restarting scheduler container..."
        local scheduler_name="${APP_NAME}_scheduler"

        # Stop old scheduler
        if docker ps -a --filter "name=${scheduler_name}" --format "{{.Names}}" | grep -q "^${scheduler_name}$"; then
            stop_container "$scheduler_name"
        fi

        # Start new scheduler
        start_scheduler_container "$scheduler_name" "${DOCKER_IMAGE_NAME}:${image_tag}" "$ENV_FILE" "bundle exec clockwork lib/clock.rb" "host" "/rails/log"

        if [ $? -ne 0 ]; then
            log_error "Failed to start scheduler ${scheduler_name}"
            return 1
        fi
        log_success "Scheduler container restarted successfully"
    fi

    return 0
}

# Hook: Display Rails deployment summary
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
    echo "  Type: Rails API"
    echo "  App ID: ${APP_NAME}"
    echo "  Git Commit: ${CURRENT_COMMIT:0:7}"
    echo "  Image Tag: ${image_tag}"
    echo ""

    # Deployment Status
    echo "DEPLOYMENT STATUS:"
    echo "  Status: SUCCESS"
    echo "  Timestamp: $(date)"
    echo "  Migrations: $([ "$migrations_run" = "true" ] && echo "Executed" || echo "Not needed")"
    echo ""

    # URLs and Access
    echo "AVAILABILITY:"
    echo "  Primary URL: https://${DOMAIN}"
    if [ -n "${DOMAIN_INTERNAL:-}" ]; then
        echo "  Internal URL: https://${DOMAIN_INTERNAL}"
    fi
    if [[ "$DOMAIN" != www.* ]] && [[ "$DOMAIN" != api* ]]; then
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
        local port=$(docker port "$container" "$CONTAINER_PORT" 2>/dev/null | cut -d ':' -f2)
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

    # Scheduler Information (if applicable)
    local scheduler_container="${APP_NAME}_scheduler"
    if docker ps --filter "name=${scheduler_container}" --format "{{.Names}}" 2>/dev/null | grep -q "^${scheduler_container}$"; then
        echo "SCHEDULER CONTAINER:"
        local status=$(docker inspect -f '{{.State.Status}}' "$scheduler_container" 2>/dev/null)
        echo "  Container: ${scheduler_container}"
        echo "  Status: ${status}"
        echo "  Type: Clockwork (scheduled tasks)"
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

    # Database Information
    echo "DATABASE:"
    echo "  Name: ${DB_NAME}"
    local backup_count=$(ls -1 ${BACKUP_DIR}/*.sql.gz 2>/dev/null | wc -l | tr -d ' ')
    echo "  Available Backups: ${backup_count}"
    echo "  Latest Backup: $(ls -t ${BACKUP_DIR}/*.sql.gz 2>/dev/null | head -1 | xargs -r basename)"
    echo "  Backup Location: ${BACKUP_DIR}"
    echo ""

    # Useful Commands
    echo "USEFUL COMMANDS:"
    echo "  Deploy:           cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh"
    echo "  Rails console:    ${APP_DIR}/console.sh"
    echo "  View app logs:    ${APP_DIR}/logs.sh"
    echo "  Docker logs:      docker logs ${APP_NAME}_web_1 -f"
    echo "  Check health:     curl https://${DOMAIN}${HEALTH_CHECK_PATH}"
    echo "  Scale to N:       cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh scale N"
    echo "  Restart:          cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh restart"
    echo "  Stop:             cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh stop"
    echo ""
    echo "NAVIGATION:"
    echo "  Config dir:       cd ~/DevOps/apps/${APP_NAME}"
    echo "  Deployed app:     cd ~/apps/${APP_NAME}"
    echo "  Quick link:       cd ~/apps/${APP_NAME}/config (→ config dir)"
    echo ""
    echo "LOG FILES:"
    echo "  Production logs:  ${LOG_DIR}/production.log"
    echo "  Sidekiq logs:     ${LOG_DIR}/sidekiq.log"
    echo "  All containers write to: ${LOG_DIR}/"
    echo ""

    echo "================================================================================"
    echo ""
}

# ==============================================================================
# CONTAINER MANAGEMENT HOOKS
# ==============================================================================

# Hook: Stop all Rails containers (web + workers + scheduler)
rails_stop_containers() {
    log_info "Stopping all ${APP_NAME} containers"

    # Get all containers (web + workers + scheduler)
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

# Hook: Rails apps can have workers
rails_has_workers() {
    [ "${WORKER_COUNT:-0}" -gt 0 ]
    return $?
}

# Hook: Rails apps can have scheduler
rails_has_scheduler() {
    [ "${SCHEDULER_ENABLED:-false}" = "true" ]
    return $?
}
