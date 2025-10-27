#!/bin/bash

# Common utility functions for deployment scripts
# Location: /home/andrzej/DevOps/common/utils.sh
# This file should be sourced by setup.sh and deploy.sh scripts

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Send Mailgun notification
send_mailgun_notification() {
    local subject="$1"
    local message="$2"
    local mailgun_api_key="$3"
    local mailgun_domain="$4"
    local recipient="$5"

    if [[ -z "$mailgun_api_key" ]] || [[ -z "$mailgun_domain" ]]; then
        log_warning "Mailgun not configured, skipping notification"
        return 0
    fi

    log_info "Sending notification via Mailgun..."

    curl -s --user "api:${mailgun_api_key}" \
        https://api.mailgun.net/v3/${mailgun_domain}/messages \
        -F from="Deployment Bot <noreply@${mailgun_domain}>" \
        -F to="${recipient}" \
        -F subject="${subject}" \
        -F text="${message}" > /dev/null

    if [ $? -eq 0 ]; then
        log_success "Notification sent successfully"
    else
        log_warning "Failed to send notification"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Wait for service to be ready
wait_for_service() {
    local host="$1"
    local port="$2"
    local max_attempts="${3:-30}"
    local attempt=0

    log_info "Waiting for service at ${host}:${port}..."

    while [ $attempt -lt $max_attempts ]; do
        if nc -z "$host" "$port" 2>/dev/null; then
            log_success "Service is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    log_error "Service failed to become ready after ${max_attempts} seconds"
    return 1
}

# Check if PostgreSQL database exists
check_database_exists() {
    local db_name="$1"
    local db_user="${2:-postgres}"

    sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db_name"
}

# Check if PostgreSQL user exists
check_db_user_exists() {
    local db_user="$1"

    sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${db_user}'" | grep -q 1
}

# Create PostgreSQL user with password
create_db_user() {
    local db_user="$1"
    local db_password="$2"

    log_info "Creating database user: ${db_user}"

    if check_db_user_exists "$db_user"; then
        log_warning "Database user ${db_user} already exists"
        return 0
    fi

    # Create user with password
    sudo -u postgres psql -c "CREATE USER ${db_user} WITH PASSWORD '${db_password}';" 2>/dev/null

    if [ $? -eq 0 ]; then
        log_success "Database user ${db_user} created successfully"
        return 0
    else
        log_error "Failed to create database user ${db_user}"
        return 1
    fi
}

# Create PostgreSQL database
create_database() {
    local db_name="$1"
    local db_user="${2:-postgres}"
    local db_password="${3:-}"

    log_info "Creating database: ${db_name}"

    if check_database_exists "$db_name" "$db_user"; then
        log_warning "Database ${db_name} already exists"
        return 0
    fi

    # Create database
    sudo -u postgres psql -c "CREATE DATABASE ${db_name};" 2>/dev/null

    if [ $? -eq 0 ]; then
        log_success "Database ${db_name} created successfully"
        return 0
    else
        log_error "Failed to create database ${db_name}"
        return 1
    fi
}

# Grant database privileges to user
grant_database_privileges() {
    local db_name="$1"
    local db_user="$2"

    log_info "Granting privileges on ${db_name} to ${db_user}"

    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};" 2>/dev/null
    sudo -u postgres psql -d "${db_name}" -c "GRANT ALL ON SCHEMA public TO ${db_user};" 2>/dev/null
    sudo -u postgres psql -d "${db_name}" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${db_user};" 2>/dev/null
    sudo -u postgres psql -d "${db_name}" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${db_user};" 2>/dev/null

    if [ $? -eq 0 ]; then
        log_success "Privileges granted to ${db_user} on ${db_name}"
        return 0
    else
        log_error "Failed to grant privileges"
        return 1
    fi
}

# Reset database user password
reset_db_user_password() {
    local db_user="$1"
    local db_password="$2"

    log_info "Resetting password for database user: ${db_user}"

    # Use ALTER USER to change password
    sudo -u postgres psql -c "ALTER USER ${db_user} WITH PASSWORD '${db_password}';" 2>/dev/null

    if [ $? -eq 0 ]; then
        log_success "Password reset for ${db_user}"
        return 0
    else
        log_error "Failed to reset password for ${db_user}"
        return 1
    fi
}

# Get or generate secret
get_or_generate_secret() {
    local env_file="$1"
    local key_name="$2"
    local generate_command="$3"

    # Check if secret exists in env file
    if [ -f "$env_file" ]; then
        local existing_secret=$(grep "^${key_name}=" "$env_file" | cut -d '=' -f2-)
        if [ -n "$existing_secret" ]; then
            echo "$existing_secret"
            return 0
        fi
    fi

    # Generate new secret
    eval "$generate_command"
}

# Docker image management
get_running_containers() {
    local app_name="$1"
    docker ps --filter "name=${app_name}_web" --format "{{.Names}}"
}

get_container_count() {
    local app_name="$1"
    get_running_containers "$app_name" | wc -l | tr -d ' '
}

# Health check for container
check_container_health() {
    local container_name="$1"
    local max_attempts="${2:-30}"
    local attempt=0

    log_info "Checking health of container: ${container_name}"

    while [ $attempt -lt $max_attempts ]; do
        # Check if container is running
        if ! docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
            log_error "Container ${container_name} is not running"
            return 1
        fi

        # Get container port (try both 3000 for Next.js/Node and 80 for other services)
        local port=$(docker port "${container_name}" 3000 2>/dev/null | cut -d ':' -f2)
        if [ -z "$port" ]; then
            port=$(docker port "${container_name}" 80 2>/dev/null | cut -d ':' -f2)
        fi

        if [ -n "$port" ]; then
            # Try multiple health check paths and accept 2xx or 3xx status codes
            for path in "/up" "/" "/api/health"; do
                local status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${port}${path} 2>/dev/null)
                if [[ "$status" =~ ^[23][0-9][0-9]$ ]]; then
                    log_success "Container ${container_name} is healthy (HTTP $status on $path)"
                    return 0
                fi
            done
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    log_error "Container ${container_name} failed health check after ${max_attempts} attempts"
    # Show container logs for debugging
    log_error "Last 20 lines of container logs:"
    docker logs "${container_name}" --tail 20 2>&1 | sed 's/^/  /'
    return 1
}

# Generate random string
generate_random_string() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

# Backup database
backup_database() {
    local db_name="$1"
    local backup_dir="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/${db_name}_${timestamp}.sql"

    mkdir -p "$backup_dir"

    log_info "Backing up database ${db_name} to ${backup_file}"

    sudo -u postgres pg_dump "$db_name" > "$backup_file"

    if [ $? -eq 0 ]; then
        log_success "Database backed up successfully"
        # Compress backup
        gzip "$backup_file"
        log_info "Backup compressed: ${backup_file}.gz"
        return 0
    else
        log_error "Database backup failed"
        return 1
    fi
}

# Cleanup old database backups
cleanup_old_backups() {
    local backup_dir="$1"
    local retention_days="${2:-30}"

    log_info "Cleaning up database backups older than ${retention_days} days"

    if [ ! -d "$backup_dir" ]; then
        log_info "Backup directory doesn't exist: ${backup_dir}"
        return 0
    fi

    # Find and delete backups older than retention days
    local old_backups=$(find "$backup_dir" -name "*.sql.gz" -mtime +${retention_days} 2>/dev/null)

    if [ -n "$old_backups" ]; then
        echo "$old_backups" | xargs rm -f
        log_success "Cleaned up old database backups"
    else
        log_info "No old backups to clean up"
    fi

    return 0
}

# List available database backups
list_backups() {
    local backup_dir="$1"

    if [ ! -d "$backup_dir" ]; then
        log_error "Backup directory not found: ${backup_dir}"
        return 1
    fi

    echo "Available database backups:"
    echo "============================"
    ls -lh "$backup_dir"/*.sql.gz 2>/dev/null | awk '{print $9, "(" $5 ")", $6, $7, $8}'

    if [ $? -ne 0 ]; then
        echo "No backups found in ${backup_dir}"
    fi

    return 0
}

# Restore database from backup
restore_database() {
    local db_name="$1"
    local backup_file="$2"

    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: ${backup_file}"
        return 1
    fi

    log_warning "This will restore database ${db_name} from ${backup_file}"
    log_warning "Current data will be LOST. Press Ctrl+C to cancel."
    sleep 5

    log_info "Restoring database ${db_name} from ${backup_file}..."

    # Drop and recreate database
    sudo -u postgres dropdb "$db_name" 2>/dev/null || true
    sudo -u postgres createdb "$db_name"

    # Restore from backup
    if [[ "$backup_file" == *.gz ]]; then
        gunzip -c "$backup_file" | sudo -u postgres psql "$db_name" > /dev/null 2>&1
    else
        sudo -u postgres psql "$db_name" < "$backup_file" > /dev/null 2>&1
    fi

    if [ $? -eq 0 ]; then
        log_success "Database restored successfully"
        return 0
    else
        log_error "Database restore failed"
        return 1
    fi
}

# Load environment variables from file
load_env_file() {
    local env_file="$1"

    if [ ! -f "$env_file" ]; then
        log_error "Environment file not found: ${env_file}"
        return 1
    fi

    # Export variables from env file
    set -a
    source "$env_file"
    set +a

    log_success "Environment loaded from ${env_file}"
}

# Ensure directory exists with proper permissions
ensure_directory() {
    local dir_path="$1"
    local owner="${2:-$USER}"

    if [ ! -d "$dir_path" ]; then
        log_info "Creating directory: ${dir_path}"
        mkdir -p "$dir_path"
        chown -R "$owner:$owner" "$dir_path"
    fi
}
