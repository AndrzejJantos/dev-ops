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

    # Copy .env.production to .env for Docker build
    # This ensures all configured environment variables are available during asset precompilation
    # The .env.production file already has all dummy values configured during setup
    log_info "Creating temporary .env file for Docker build..."

    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "${repo_path}/.env"
        log_info "Copied .env.production to .env for Docker build"
    else
        log_error "Environment file not found: $ENV_FILE"
        log_error "Please run setup.sh first"
        return 1
    fi

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
    local host_port="$3"
    local env_file="$4"
    local container_port="${5:-3000}"  # Default to 3000 (consistent for Rails and Next.js)
    local network="${6:-bridge}"
    local log_mount_path="${7:-/app/log}"  # Default to /app/log, but Rails uses /rails/log

    log_info "Starting container: ${container_name} on host port ${host_port} -> container port ${container_port}"

    # Remove existing container if it exists
    docker rm -f "$container_name" 2>/dev/null || true

    # Ensure logs directory exists with proper permissions for container user
    mkdir -p "${LOG_DIR}"
    chmod 777 "${LOG_DIR}"  # Allow container's app user to write logs

    # Use host network for Rails apps to access PostgreSQL on localhost
    # For other apps, use bridge network with port mapping
    if [ "$network" = "host" ]; then
        docker run -d \
            --name "$container_name" \
            --network host \
            --restart unless-stopped \
            --env-file "$env_file" \
            -e PORT="${host_port}" \
            -v "${LOG_DIR}:${log_mount_path}" \
            --health-cmd "curl -f http://localhost:${host_port}/up || exit 1" \
            --health-interval=30s \
            --health-timeout=3s \
            --health-start-period=40s \
            --health-retries=3 \
            "$image_name"
    else
        docker run -d \
            --name "$container_name" \
            --network "$network" \
            --restart unless-stopped \
            -p "${host_port}:${container_port}" \
            --env-file "$env_file" \
            -v "${LOG_DIR}:${log_mount_path}" \
            --health-cmd "curl -f http://localhost:${container_port}/up || exit 1" \
            --health-interval=30s \
            --health-timeout=3s \
            --health-start-period=40s \
            --health-retries=3 \
            "$image_name"
    fi

    if [ $? -eq 0 ]; then
        log_success "Container started successfully"
        return 0
    else
        log_error "Failed to start container"
        return 1
    fi
}

# Start worker container (no port exposure)
start_worker_container() {
    local container_name="$1"
    local image_name="$2"
    local env_file="$3"
    local worker_command="${4:-bundle exec sidekiq}"
    local network="${5:-bridge}"
    local log_mount_path="${6:-/app/log}"  # Default to /app/log, but Rails uses /rails/log

    log_info "Starting worker container: ${container_name}"

    # Remove existing container if it exists
    docker rm -f "$container_name" 2>/dev/null || true

    # Ensure logs directory exists with proper permissions for container user
    mkdir -p "${LOG_DIR}"
    chmod 777 "${LOG_DIR}"  # Allow container's app user to write logs

    # Extract the workdir from log_mount_path (e.g., /rails/log -> /rails)
    local workdir=$(dirname "$log_mount_path")

    docker run -d \
        --name "$container_name" \
        --network "$network" \
        --restart unless-stopped \
        --env-file "$env_file" \
        -v "${LOG_DIR}:${log_mount_path}" \
        "$image_name" \
        /bin/bash -c "cd ${workdir} && $worker_command"

    if [ $? -eq 0 ]; then
        log_success "Worker container started successfully"
        return 0
    else
        log_error "Failed to start worker container"
        return 1
    fi
}

# Start scheduler container (no port exposure)
start_scheduler_container() {
    local container_name="$1"
    local image_name="$2"
    local env_file="$3"
    local scheduler_command="${4:-bundle exec clockwork config/clock.rb}"
    local network="${5:-bridge}"
    local log_mount_path="${6:-/app/log}"  # Default to /app/log, but Rails uses /rails/log

    log_info "Starting scheduler container: ${container_name}"

    # Remove existing container if it exists
    docker rm -f "$container_name" 2>/dev/null || true

    # Ensure logs directory exists with proper permissions for container user
    mkdir -p "${LOG_DIR}"
    chmod 777 "${LOG_DIR}"  # Allow container's app user to write logs

    # Extract the workdir from log_mount_path (e.g., /rails/log -> /rails)
    local workdir=$(dirname "$log_mount_path")

    docker run -d \
        --name "$container_name" \
        --network "$network" \
        --restart unless-stopped \
        --env-file "$env_file" \
        -v "${LOG_DIR}:${log_mount_path}" \
        "$image_name" \
        /bin/bash -c "cd ${workdir} && $scheduler_command"

    if [ $? -eq 0 ]; then
        log_success "Scheduler container started successfully"
        return 0
    else
        log_error "Failed to start scheduler container"
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

    docker exec "$container_name" /bin/bash -c "cd /app && bundle exec rails db:migrate"

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

    local output=$(docker exec "$container_name" /bin/bash -c "cd /app && bundle exec rails db:migrate:status 2>&1")
    local exit_code=$?

    # If command failed (likely no schema_migrations table exists), migrations are needed
    if [ $exit_code -ne 0 ] || echo "$output" | grep -qE "does not exist|No such|PG::UndefinedTable"; then
        log_warning "Database schema not initialized, migrations needed"
        return 0  # Migrations are pending
    fi

    # Check for migrations with "down" status
    if echo "$output" | grep -q "down"; then
        log_warning "Pending migrations detected"
        return 0  # Migrations are pending
    fi

    # Check if there are NO migrations at all (output is empty or very short)
    if [ -z "$output" ] || [ ${#output} -lt 50 ]; then
        log_warning "No migration history found, migrations may be needed"
        return 0  # Migrations are pending (safer to assume they need to run)
    fi

    log_info "No pending migrations"
    return 1  # No migrations pending
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

# Save Docker image as tar file
save_docker_image() {
    local image_name="$1"
    local image_tag="$2"
    local backup_dir="$3"

    log_info "Saving Docker image as tar file: ${image_name}:${image_tag}"

    # Create backup directory if it doesn't exist
    mkdir -p "$backup_dir"

    local tar_file="${backup_dir}/${image_name}_${image_tag}.tar"

    # Save image to tar file
    if docker save "${image_name}:${image_tag}" -o "$tar_file"; then
        # Compress the tar file to save space
        gzip -f "$tar_file"
        log_success "Image saved to ${tar_file}.gz"

        # Show file size
        local file_size=$(du -h "${tar_file}.gz" | cut -f1)
        log_info "Backup size: ${file_size}"
        return 0
    else
        log_error "Failed to save Docker image"
        return 1
    fi
}

# Load Docker image from tar file
load_docker_image() {
    local tar_file="$1"

    log_info "Loading Docker image from ${tar_file}"

    # Check if file is gzipped
    if [[ "$tar_file" == *.gz ]]; then
        if gunzip -c "$tar_file" | docker load; then
            log_success "Image loaded successfully"
            return 0
        else
            log_error "Failed to load Docker image"
            return 1
        fi
    else
        if docker load -i "$tar_file"; then
            log_success "Image loaded successfully"
            return 0
        else
            log_error "Failed to load Docker image"
            return 1
        fi
    fi
}

# Cleanup old image backups
cleanup_old_image_backups() {
    local backup_dir="$1"
    local keep_count="${2:-5}"

    log_info "Cleaning up old image backups in ${backup_dir}"

    if [ ! -d "$backup_dir" ]; then
        log_info "Backup directory doesn't exist"
        return 0
    fi

    # Get list of tar.gz files sorted by modification time (oldest first)
    local old_files=$(ls -t "${backup_dir}"/*.tar.gz 2>/dev/null | tail -n +$((keep_count + 1)))

    if [ -n "$old_files" ]; then
        echo "$old_files" | xargs rm -f
        log_success "Old image backups cleaned up"
    else
        log_info "No old backups to clean up"
    fi
}

# List available image backups
list_image_backups() {
    local backup_dir="$1"

    if [ ! -d "$backup_dir" ]; then
        log_warning "No backup directory found at ${backup_dir}"
        return 1
    fi

    log_info "Available image backups:"
    echo ""
    ls -lh "${backup_dir}"/*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ", " $6 " " $7 " " $8 ")"}'
    echo ""
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
    local container_port="${6:-3000}"  # Default to 3000 (consistent for Rails and Next.js)
    local network="${7:-bridge}"       # Default to bridge, but Rails uses host

    log_info "Performing rolling restart with scale=${scale}"

    # Get currently running containers
    local old_containers=($(get_running_containers "$app_name"))
    local current_count=${#old_containers[@]}

    if [ $current_count -eq 0 ]; then
        log_warning "No running containers found, starting fresh"
        # Start new containers
        for i in $(seq 1 $scale); do
            local port=$((base_port + i - 1))
            local container_name="${app_name}_web_${i}"

            start_container "$container_name" "$new_image" "$port" "$env_file" "$container_port" "$network"

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

    # Rolling restart: restart each container one by one on the same port
    # This maintains the correct port mappings and ensures zero downtime
    for i in $(seq 1 $scale); do
        local port=$((base_port + i - 1))
        local container_name="${app_name}_web_${i}"

        log_info "Restarting container ${i}/${scale} on port ${port}"

        # Stop old container
        if docker ps --filter "name=^${container_name}$" --format "{{.Names}}" | grep -q "^${container_name}$"; then
            stop_container "$container_name" 30
            sleep 2
        fi

        # Start new container on same port
        start_container "$container_name" "$new_image" "$port" "$env_file" "$container_port" "$network"

        if [ $? -ne 0 ]; then
            log_error "Failed to start container ${container_name}"
            return 1
        fi

        # Wait for health check
        check_container_health "$container_name" 60

        if [ $? -ne 0 ]; then
            log_error "Container ${container_name} failed health check"
            return 1
        fi

        log_success "Container ${container_name} restarted successfully"

        # Brief pause before next container (allows traffic to stabilize)
        if [ $i -lt $scale ]; then
            sleep 5
        fi
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
    local container_port="${6:-3000}"  # Default to 3000 (consistent for Rails and Next.js)

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

            start_container "$container_name" "$image_name" "$port" "$env_file" "$container_port"

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
