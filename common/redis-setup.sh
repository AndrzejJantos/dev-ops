#!/bin/bash

# ==============================================================================
# REDIS SETUP AND CONFIGURATION
# ==============================================================================
# This script handles Redis installation and configuration for Redis Streams
# Can be called during server initialization or app setup
#
# Usage:
#   source common/redis-setup.sh
#   setup_redis_for_streams
#
# ==============================================================================

# Function: Check if Redis is installed
redis_check_installed() {
    if command -v redis-cli &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function: Check if Redis is running
redis_check_running() {
    if redis-cli ping > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function: Get Redis version
redis_get_version() {
    redis-cli INFO server 2>/dev/null | grep redis_version | cut -d: -f2 | cut -d. -f1 | tr -d '\r'
}

# Function: Configure Redis for Streams
setup_redis_for_streams() {
    log_info "Configuring Redis for Redis Streams..."

    # Check if Redis is installed
    if ! redis_check_installed; then
        log_error "Redis is not installed. Run ubuntu-init-setup.sh first"
        return 1
    fi

    # Stop Redis before replacing config
    log_info "Stopping Redis to replace configuration..."
    sudo systemctl stop redis-server
    sleep 2

    # Check Redis version
    log_info "Redis version: $(redis-server --version | grep -oP 'v=\K[0-9]+\.[0-9]+\.[0-9]+')"

    # Locate Redis config file
    local redis_conf="/etc/redis/redis.conf"
    if [ ! -f "$redis_conf" ]; then
        if [ -f "/etc/redis.conf" ]; then
            redis_conf="/etc/redis.conf"
        else
            log_error "Cannot find Redis config file"
            return 1
        fi
    fi

    log_info "Redis config: $redis_conf"

    # Get the DevOps directory (assuming we're in DevOps/common or DevOps/apps/*)
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local devops_dir=""

    # Try to find DevOps root
    if [[ "$script_dir" == */DevOps/common ]]; then
        devops_dir="$(dirname "$script_dir")"
    elif [[ "$script_dir" == */DevOps/apps/* ]]; then
        devops_dir="$(dirname "$(dirname "$script_dir")")"
    elif [[ "$script_dir" == */DevOps ]]; then
        devops_dir="$script_dir"
    else
        log_error "Cannot determine DevOps directory from: $script_dir"
        return 1
    fi

    local template_conf="${devops_dir}/common/templates/redis.conf"

    if [ ! -f "$template_conf" ]; then
        log_error "Redis config template not found: $template_conf"
        log_error "Please ensure DevOps repository is up to date"
        return 1
    fi

    log_info "Using template: $template_conf"

    # Backup existing config
    local backup_file="${redis_conf}.backup-$(date +%Y%m%d-%H%M%S)"
    sudo cp "$redis_conf" "$backup_file"
    log_info "Backed up existing config to: $backup_file"

    # Deploy clean config from template
    log_info "Deploying clean Redis configuration..."
    sudo cp "$template_conf" "$redis_conf"
    sudo chown redis:redis "$redis_conf"
    sudo chmod 640 "$redis_conf"

    # Test configuration
    log_info "Testing configuration..."
    if ! sudo redis-server "$redis_conf" --test-memory 1 2>&1 | grep -q "Configuration passed"; then
        log_error "Configuration test failed!"
        log_error "Restoring backup..."
        sudo cp "$backup_file" "$redis_conf"
        return 1
    fi

    log_success "Configuration syntax is valid"

    # Start Redis with new config
    log_info "Starting Redis with new configuration..."
    sudo systemctl start redis-server

    # Wait for Redis to start
    sleep 3

    # Verify Redis is running
    local retries=10
    while [ $retries -gt 0 ]; do
        if redis_check_running; then
            log_success "Redis started successfully with new configuration"
            break
        fi
        sleep 2
        retries=$((retries - 1))
    done

    if [ $retries -eq 0 ]; then
        log_error "Redis failed to start!"
        log_error "Checking logs..."
        sudo journalctl -xeu redis-server.service --no-pager | tail -20
        log_error "Restoring backup configuration..."
        sudo cp "$backup_file" "$redis_conf"
        sudo systemctl start redis-server
        return 1
    fi

    # Verify configuration
    local aof_status=$(redis-cli CONFIG GET appendonly | tail -1)
    local maxmem=$(redis-cli CONFIG GET maxmemory | tail -1)
    local policy=$(redis-cli CONFIG GET maxmemory-policy | tail -1)

    log_success "Redis Streams configuration complete:"
    log_info "  AOF Persistence: $aof_status"
    log_info "  Max Memory: $(numfmt --to=iec $maxmem 2>/dev/null || echo $maxmem)"
    log_info "  Eviction Policy: $policy"

    return 0
}

# Function: Enable Redis Streams for specific app
enable_redis_streams_for_app() {
    local app_name=$1
    local env_file="${HOME}/apps/${app_name}/.env.production"

    if [ ! -f "$env_file" ]; then
        log_error "Environment file not found: $env_file"
        return 1
    fi

    log_info "Enabling Redis Streams for $app_name..."

    # Check if already enabled
    if grep -q "ENABLE_REDIS_STREAM_CONSUMERS=true" "$env_file"; then
        log_info "Redis Streams already enabled for $app_name"
        return 0
    fi

    # Update configuration
    sed -i 's/ENABLE_REDIS_STREAM_CONSUMERS=false/ENABLE_REDIS_STREAM_CONSUMERS=true/' "$env_file"

    log_success "Redis Streams enabled for $app_name"
    log_warning "Redeploy the app to apply changes"

    return 0
}

# Export functions
export -f redis_check_installed
export -f redis_check_running
export -f redis_get_version
export -f setup_redis_for_streams
export -f enable_redis_streams_for_app
