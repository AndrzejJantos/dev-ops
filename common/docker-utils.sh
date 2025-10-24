#!/bin/bash

# Docker-specific utility functions for deployment
# Location: /home/andrzej/DevOps/common/docker-utils.sh
# This file should be sourced by deployment scripts

# Build Docker image
build_docker_image() {
    local app_name="$1"
    local repo_path="$2"
    local image_tag="$3"

    log_info "Building Docker image: ${app_name}:${image_tag}"

    cd "$repo_path" || return 1

    # Create temporary .env file with dummy values for Docker build
    # This prevents errors when Rails/Node loads environment during build
    log_info "Creating temporary .env file for Docker build..."
    cat > "${repo_path}/.env" << 'DOCKER_BUILD_ENV'
# Temporary environment file for Docker build
# These dummy values are used during asset precompilation
# Real values will be provided at runtime via Docker run --env-file

# Database (not used during build)
DATABASE_URL=postgresql://dummy:dummy@localhost/dummy
REDIS_URL=redis://localhost:6379/0

# API Keys (dummy values for build)
MAILGUN_API_KEY=dummy_key_for_build
STRIPE_PUBLISHABLE_KEY=pk_test_dummy_for_build
STRIPE_SECRET_KEY=sk_test_dummy_for_build
GOOGLE_ANALYTICS_ID=G-XXXXXXXXXX
GOOGLE_TAG_MANAGER_ID=GTM-XXXXXXX
FACEBOOK_PIXEL_ID=000000000000000
ROLLBAR_ACCESS_TOKEN=dummy_token_for_build
SECRET_KEY_BASE=dummy_secret_key_base_for_build_only

# Rails environment
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

# Node.js environment
NODE_ENV=production
DOCKER_BUILD_ENV

    docker build -t "${app_name}:${image_tag}" .
    local build_result=$?

    # Remove temporary .env file after build
    rm -f "${repo_path}/.env"
    log_info "Removed temporary build .env file"

    if [ $build_result -eq 0 ]; then
        log_success "Docker image built successfully"
        return 0
    else
        log_error "Docker image build failed"
        return 1
    fi
}

# Start container with proper configuration
start_container() {
    local container_name="$1"
    local image_name="$2"
    local port="$3"
    local env_file="$4"
    local network="${5:-bridge}"

    log_info "Starting container: ${container_name} on port ${port}"

    # Remove existing container if it exists
    docker rm -f "$container_name" 2>/dev/null || true

    docker run -d \
        --name "$container_name" \
        --network "$network" \
        --restart unless-stopped \
        -p "${port}:80" \
        --env-file "$env_file" \
        "$image_name"

    if [ $? -eq 0 ]; then
        log_success "Container started successfully"
        return 0
    else
        log_error "Failed to start container"
        return 1
    fi
}

# Gracefully stop container
stop_container() {
    local container_name="$1"
    local timeout="${2:-30}"

    log_info "Stopping container: ${container_name}"

    if docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker stop -t "$timeout" "$container_name"

        if [ $? -eq 0 ]; then
            log_success "Container stopped successfully"
            docker rm "$container_name" 2>/dev/null || true
            return 0
        else
            log_error "Failed to stop container gracefully, forcing..."
            docker rm -f "$container_name"
            return 1
        fi
    else
        log_warning "Container ${container_name} is not running"
        return 0
    fi
}

# Run migrations in container
run_migrations() {
    local container_name="$1"

    log_info "Running database migrations in ${container_name}"

    docker exec "$container_name" /bin/bash -c "cd /rails && bundle exec rails db:migrate"

    if [ $? -eq 0 ]; then
        log_success "Migrations completed successfully"
        return 0
    else
        log_error "Migrations failed"
        return 1
    fi
}

# Check if migrations are pending
check_pending_migrations() {
    local container_name="$1"

    log_info "Checking for pending migrations..."

    local output=$(docker exec "$container_name" /bin/bash -c "cd /rails && bundle exec rails db:migrate:status 2>&1")

    if echo "$output" | grep -q "down"; then
        log_warning "Pending migrations detected"
        return 0  # Migrations are pending
    else
        log_info "No pending migrations"
        return 1  # No migrations pending
    fi
}

# Clean up old Docker images
cleanup_old_images() {
    local app_name="$1"
    local keep_count="${2:-3}"

    log_info "Cleaning up old Docker images for ${app_name}"

    # Get list of image IDs sorted by creation date (oldest first)
    local images=$(docker images "${app_name}" --format "{{.ID}}" | tail -n +$((keep_count + 1)))

    if [ -n "$images" ]; then
        echo "$images" | xargs docker rmi -f 2>/dev/null || true
        log_success "Old images cleaned up"
    else
        log_info "No old images to clean up"
    fi
}

# Get next available port
get_next_available_port() {
    local start_port="$1"
    local max_attempts="${2:-100}"

    for i in $(seq 0 $max_attempts); do
        local port=$((start_port + i))
        if ! nc -z localhost "$port" 2>/dev/null; then
            echo "$port"
            return 0
        fi
    done

    log_error "No available ports found in range ${start_port}-$((start_port + max_attempts))"
    return 1
}

# Rolling restart of containers
rolling_restart() {
    local app_name="$1"
    local new_image="$2"
    local env_file="$3"
    local base_port="$4"
    local scale="${5:-2}"

    log_info "Performing rolling restart with scale=${scale}"

    # Get currently running containers
    local old_containers=($(get_running_containers "$app_name"))
    local current_count=${#old_containers[@]}

    if [ $current_count -eq 0 ]; then
        log_warning "No running containers found, starting fresh"
        # Start new containers
        for i in $(seq 1 $scale); do
            local port=$(get_next_available_port "$base_port")
            local container_name="${app_name}_web_${i}"

            start_container "$container_name" "$new_image" "$port" "$env_file"

            if [ $? -ne 0 ]; then
                log_error "Failed to start container ${container_name}"
                return 1
            fi

            # Wait for health check
            check_container_health "$container_name"

            if [ $? -ne 0 ]; then
                log_error "Container ${container_name} failed health check"
                return 1
            fi
        done
        return 0
    fi

    # Start new containers one by one
    local new_containers=()
    for i in $(seq 1 $scale); do
        local port=$(get_next_available_port "$base_port")
        local container_name="${app_name}_web_new_${i}"

        start_container "$container_name" "$new_image" "$port" "$env_file"

        if [ $? -ne 0 ]; then
            log_error "Failed to start new container"
            # Cleanup new containers
            for new_container in "${new_containers[@]}"; do
                stop_container "$new_container"
            done
            return 1
        fi

        # Wait for health check
        check_container_health "$container_name" 60

        if [ $? -ne 0 ]; then
            log_error "New container failed health check"
            # Cleanup new containers
            for new_container in "${new_containers[@]}"; do
                stop_container "$new_container"
            done
            stop_container "$container_name"
            return 1
        fi

        new_containers+=("$container_name")
        log_success "New container ${container_name} is healthy and ready"
    done

    # All new containers are healthy, now stop old ones
    log_info "All new containers are healthy, stopping old containers..."

    for old_container in "${old_containers[@]}"; do
        stop_container "$old_container" 30
        sleep 2
    done

    # Rename new containers to standard names
    for i in $(seq 1 $scale); do
        local old_name="${app_name}_web_new_${i}"
        local new_name="${app_name}_web_${i}"

        docker rename "$old_name" "$new_name" 2>/dev/null || true
    done

    log_success "Rolling restart completed successfully"
    return 0
}

# Scale application
scale_application() {
    local app_name="$1"
    local image_name="$2"
    local env_file="$3"
    local base_port="$4"
    local target_scale="$5"

    local current_count=$(get_container_count "$app_name")

    log_info "Scaling from ${current_count} to ${target_scale} instances"

    if [ "$target_scale" -eq "$current_count" ]; then
        log_info "Already at desired scale"
        return 0
    fi

    if [ "$target_scale" -gt "$current_count" ]; then
        # Scale up
        local to_add=$((target_scale - current_count))
        log_info "Scaling up: adding ${to_add} instances"

        for i in $(seq $((current_count + 1)) $target_scale); do
            local port=$(get_next_available_port "$base_port")
            local container_name="${app_name}_web_${i}"

            start_container "$container_name" "$image_name" "$port" "$env_file"

            if [ $? -ne 0 ]; then
                log_error "Failed to start container ${container_name}"
                return 1
            fi

            check_container_health "$container_name"

            if [ $? -ne 0 ]; then
                log_error "Container ${container_name} failed health check"
                stop_container "$container_name"
                return 1
            fi
        done
    else
        # Scale down
        local to_remove=$((current_count - target_scale))
        log_info "Scaling down: removing ${to_remove} instances"

        for i in $(seq $((target_scale + 1)) $current_count); do
            local container_name="${app_name}_web_${i}"
            stop_container "$container_name" 30
        done
    fi

    log_success "Scaling completed successfully"
    return 0
}
