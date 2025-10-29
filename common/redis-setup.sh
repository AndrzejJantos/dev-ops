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

    # Check if Redis is running
    if ! redis_check_running; then
        log_warning "Redis is not running. Attempting to start..."
        sudo systemctl start redis-server || {
            log_error "Failed to start Redis"
            return 1
        }
        sleep 2
    fi

    log_success "Redis is running"

    # Check Redis version
    local redis_version=$(redis_get_version)
    log_info "Redis version: $(redis-cli INFO server 2>/dev/null | grep redis_version | cut -d: -f2 | tr -d '\r')"

    if [ "$redis_version" -lt 5 ]; then
        log_warning "Redis version is below 5.0. Streams require 5.0+"
        log_warning "Consider upgrading Redis for better performance"
    fi

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

    # Check if already configured
    if grep -q "Redis Streams Configuration" "$redis_conf"; then
        log_info "Redis Streams configuration already exists"
        return 0
    fi

    # Backup config
    local backup_file="${redis_conf}.backup-$(date +%Y%m%d-%H%M%S)"
    sudo cp "$redis_conf" "$backup_file"
    log_info "Backed up Redis config to: $backup_file"

    # Add configuration
    log_info "Adding Redis Streams configuration..."

    sudo tee -a "$redis_conf" > /dev/null << 'EOF'

# ===== Redis Streams Configuration =====
# Added by DevOps setup script

# Enable AOF persistence (more durable than RDB)
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

# Memory management
maxmemory 2gb
maxmemory-policy noeviction

# Stream optimization
stream-node-max-bytes 4096
stream-node-max-entries 100

# ===== End Redis Streams Configuration =====
EOF

    # Comment out conflicting settings
    sudo sed -i.tmp 's/^appendonly no/# appendonly no # (disabled by Redis Streams setup)/' "$redis_conf"
    sudo sed -i.tmp 's/^maxmemory-policy.*volatile/# maxmemory-policy volatile # (disabled by Redis Streams setup)/' "$redis_conf"

    # Test configuration
    if sudo redis-server "$redis_conf" --test-memory 1 > /dev/null 2>&1; then
        log_success "Configuration syntax is valid"
    else
        log_error "Configuration test failed!"
        log_error "Restoring backup..."
        sudo cp "$backup_file" "$redis_conf"
        return 1
    fi

    # Restart Redis
    log_info "Restarting Redis..."
    sudo systemctl restart redis-server

    # Wait for Redis to start
    sleep 3

    # Verify Redis is running
    local retries=5
    while [ $retries -gt 0 ]; do
        if redis_check_running; then
            log_success "Redis restarted successfully"
            break
        fi
        sleep 2
        retries=$((retries - 1))
    done

    if [ $retries -eq 0 ]; then
        log_error "Redis failed to restart!"
        log_error "Restoring backup configuration..."
        sudo cp "$backup_file" "$redis_conf"
        sudo systemctl restart redis-server
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
