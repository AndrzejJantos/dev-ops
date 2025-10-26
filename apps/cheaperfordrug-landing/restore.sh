#!/bin/bash

# Database restore script for cheaperfordrug-landing
# Location: /home/andrzej/DevOps/apps/cheaperfordrug-landing/restore.sh
# Usage: ./restore.sh [backup-file]

set -euo pipefail

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG_DIR="$SCRIPT_DIR"
DEVOPS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load app configuration
if [ ! -f "${APP_CONFIG_DIR}/config.sh" ]; then
    echo "Error: Configuration file not found: ${APP_CONFIG_DIR}/config.sh"
    exit 1
fi

source "${APP_CONFIG_DIR}/config.sh"

# Load common utilities
source "${DEVOPS_DIR}/common/utils.sh"

# ============================================================================
# RESTORE FUNCTIONS
# ============================================================================

# Function: List available backups
list_backups() {
    log_info "Available database backups:"
    echo ""

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR/*.sql.gz 2>/dev/null)" ]; then
        log_warning "No backups found in ${BACKUP_DIR}"
        return 1
    fi

    # List backups with numbers
    ls -t "${BACKUP_DIR}"/*.sql.gz | nl -v 1 | while read num file; do
        local size=$(du -h "$file" | cut -f1)
        local date=$(stat -c %y "$file" 2>/dev/null || stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$file")
        printf "  %2d) %-60s  %8s  %s\n" "$num" "$(basename $file)" "$size" "$date"
    done
    echo ""

    return 0
}

# Function: Select backup interactively
select_backup() {
    list_backups || exit 1

    echo ""
    read -p "Select backup number (or 'q' to quit): " selection

    if [ "$selection" = "q" ] || [ "$selection" = "Q" ]; then
        log_info "Restore cancelled"
        exit 0
    fi

    # Validate selection is a number
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        log_error "Invalid selection: ${selection}"
        exit 1
    fi

    # Get the backup file
    local backup_file=$(ls -t "${BACKUP_DIR}"/*.sql.gz | sed -n "${selection}p")

    if [ -z "$backup_file" ]; then
        log_error "Invalid backup number: ${selection}"
        exit 1
    fi

    echo "$backup_file"
}

# Function: Confirm restore
confirm_restore() {
    local backup_file="$1"

    log_warning "WARNING: This will REPLACE the current database with the backup!"
    log_warning "Database: ${DB_NAME}"
    log_warning "Backup: $(basename $backup_file)"
    echo ""
    log_info "Current database will be backed up before restore"
    echo ""

    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation

    if [ "$confirmation" != "yes" ]; then
        log_info "Restore cancelled"
        exit 0
    fi
}

# Function: Stop application containers
stop_application() {
    log_info "Stopping application containers..."

    local containers=($(docker ps --filter "name=${APP_NAME}" --format "{{.Names}}" 2>/dev/null))

    if [ ${#containers[@]} -eq 0 ]; then
        log_info "No running containers found"
        return 0
    fi

    for container in "${containers[@]}"; do
        docker stop "$container" >/dev/null 2>&1
        log_success "Stopped: ${container}"
    done

    return 0
}

# Function: Start application containers
start_application() {
    log_info "Starting application containers..."

    # Use deploy script to restart
    cd "$SCRIPT_DIR"
    ./deploy.sh restart >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        log_success "Application restarted successfully"
        return 0
    else
        log_warning "Failed to restart application automatically"
        log_info "Please run: ./deploy.sh restart"
        return 1
    fi
}

# Function: Backup current database before restore
backup_current_database() {
    log_info "Creating safety backup of current database..."

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local safety_backup="${BACKUP_DIR}/${DB_NAME}_pre_restore_${timestamp}.sql"

    sudo -u postgres pg_dump "$DB_NAME" > "$safety_backup"

    if [ $? -eq 0 ]; then
        gzip "$safety_backup"
        log_success "Current database backed up to: ${safety_backup}.gz"
        return 0
    else
        log_error "Failed to create safety backup"
        return 1
    fi
}

# Function: Restore database from backup
restore_database() {
    local backup_file="$1"

    log_info "Restoring database from: $(basename $backup_file)"

    # Drop and recreate database
    log_info "Dropping existing database..."
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true

    log_info "Creating fresh database..."
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};" 2>/dev/null

    log_info "Restoring backup..."
    gunzip -c "$backup_file" | sudo -u postgres psql "$DB_NAME" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        # Grant privileges back to app user
        local DB_APP_USER="${APP_NAME//-/_}_user"
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_APP_USER};" 2>/dev/null
        sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL ON SCHEMA public TO ${DB_APP_USER};" 2>/dev/null
        sudo -u postgres psql -d "${DB_NAME}" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_APP_USER};" 2>/dev/null
        sudo -u postgres psql -d "${DB_NAME}" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_APP_USER};" 2>/dev/null

        log_success "Database restored successfully"
        return 0
    else
        log_error "Database restore failed"
        return 1
    fi
}

# Function: Log restore operation
log_restore() {
    local backup_file="$1"
    local status="$2"

    local restore_log="${LOG_DIR}/restore.log"
    echo "[$(date)] Restore ${status}: $(basename $backup_file)" >> "$restore_log"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "Database Restore Utility for ${APP_DISPLAY_NAME}"
    echo ""

    # Check if running as deploy user
    if [ "$(whoami)" != "$DEPLOY_USER" ]; then
        log_error "This script must be run as user: ${DEPLOY_USER}"
        log_info "Run: sudo -u ${DEPLOY_USER} bash ${SCRIPT_DIR}/restore.sh"
        exit 1
    fi

    local backup_file=""

    # Check if backup file was provided as argument
    if [ $# -eq 1 ]; then
        backup_file="$1"

        # Check if file exists
        if [ ! -f "$backup_file" ]; then
            log_error "Backup file not found: ${backup_file}"
            exit 1
        fi
    else
        # Interactive selection
        backup_file=$(select_backup)
    fi

    log_info "Selected backup: $(basename $backup_file)"

    # Confirm restore
    confirm_restore "$backup_file"

    # Stop application
    stop_application || exit 1

    # Backup current database
    backup_current_database || exit 1

    # Restore database
    if restore_database "$backup_file"; then
        log_restore "$backup_file" "SUCCESS"

        # Start application
        start_application

        # Send notification
        send_mailgun_notification \
            "${APP_DISPLAY_NAME} - Database Restored" \
            "Database has been restored from backup.

Timestamp: $(date)
Host: $(hostname)
Backup: $(basename $backup_file)
Database: ${DB_NAME}

The application has been restarted with the restored database." \
            "$MAILGUN_API_KEY" \
            "$MAILGUN_DOMAIN" \
            "$NOTIFICATION_EMAIL"

        echo ""
        log_success "Database restore completed successfully!"
        echo ""
        log_info "Application URL: https://${DOMAIN}"
        log_info "Verify the restore by checking your application"

        exit 0
    else
        log_restore "$backup_file" "FAILED"
        log_error "Database restore failed"

        # Try to start application anyway
        start_application

        exit 1
    fi
}

# Run main function
main "$@"
