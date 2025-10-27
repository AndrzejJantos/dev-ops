#!/bin/bash

# Centralized Cleanup Script for All Applications
# Location: /home/andrzej/DevOps/scripts/cleanup-all-apps.sh
# This script is run daily by cron to clean up all applications
#
# Installation (run as user, not root):
#   sudo cp this_script.sh /etc/cron.daily/devops-cleanup
#   sudo chmod +x /etc/cron.daily/devops-cleanup
#
# Or use crontab:
#   0 2 * * * /home/andrzej/DevOps/scripts/cleanup-all-apps.sh >> /home/andrzej/DevOps/logs/cleanup-all.log 2>&1

set -e

# Configuration
DEVOPS_DIR="${DEVOPS_DIR:-$HOME/DevOps}"
APPS_DIR="$DEVOPS_DIR/apps"
LOG_FILE="${LOG_FILE:-$DEVOPS_DIR/logs/cleanup-all.log}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========================================================================"
log "Starting centralized cleanup for all applications"
log "========================================================================"

# Load common utilities
if [ -f "$DEVOPS_DIR/common/utils.sh" ]; then
    source "$DEVOPS_DIR/common/utils.sh"
fi

if [ -f "$DEVOPS_DIR/common/docker-utils.sh" ]; then
    source "$DEVOPS_DIR/common/docker-utils.sh"
fi

# Count apps processed
APPS_PROCESSED=0
APPS_FAILED=0

# Find all apps with config.sh
for app_dir in "$APPS_DIR"/*; do
    # Skip if not a directory
    if [ ! -d "$app_dir" ]; then
        continue
    fi

    # Skip example directories
    if [[ "$(basename "$app_dir")" == _* ]]; then
        log "Skipping example directory: $(basename "$app_dir")"
        continue
    fi

    # Check if config.sh exists
    if [ ! -f "$app_dir/config.sh" ]; then
        log "Skipping $(basename "$app_dir"): no config.sh found"
        continue
    fi

    APP_NAME="$(basename "$app_dir")"
    log "------------------------------------------------------------------------"
    log "Processing app: $APP_NAME"

    # Load app configuration
    source "$app_dir/config.sh"

    # Cleanup old image backups (keep last N)
    if [ -d "$IMAGE_BACKUP_DIR" ]; then
        log "  Cleaning up image backups in $IMAGE_BACKUP_DIR"
        OLD_COUNT=$(ls -1 "$IMAGE_BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')

        if [ "$OLD_COUNT" -gt "${MAX_IMAGE_BACKUPS:-20}" ]; then
            cleanup_old_image_backups "$IMAGE_BACKUP_DIR" "${MAX_IMAGE_BACKUPS:-20}"
            NEW_COUNT=$(ls -1 "$IMAGE_BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
            log "  Image backups: $OLD_COUNT -> $NEW_COUNT"
        else
            log "  Image backups: $OLD_COUNT (no cleanup needed)"
        fi
    fi

    # Cleanup old Docker images (keep last N)
    log "  Cleaning up old Docker images for $DOCKER_IMAGE_NAME"
    IMAGES_BEFORE=$(docker images "$DOCKER_IMAGE_NAME" --format "{{.ID}}" | wc -l | tr -d ' ')

    if [ "$IMAGES_BEFORE" -gt "${MAX_IMAGE_VERSIONS:-20}" ]; then
        cleanup_old_images "$DOCKER_IMAGE_NAME" "${MAX_IMAGE_VERSIONS:-20}"
        IMAGES_AFTER=$(docker images "$DOCKER_IMAGE_NAME" --format "{{.ID}}" | wc -l | tr -d ' ')
        log "  Docker images: $IMAGES_BEFORE -> $IMAGES_AFTER"
    else
        log "  Docker images: $IMAGES_BEFORE (no cleanup needed)"
    fi

    # Cleanup database backups (Rails only)
    if [ "$APP_TYPE" = "rails" ] && [ -d "$BACKUP_DIR" ]; then
        log "  Cleaning up database backups older than ${BACKUP_RETENTION_DAYS:-30} days"
        OLD_DB_BACKUPS=$(find "$BACKUP_DIR" -name "*.sql.gz" -mtime +${BACKUP_RETENTION_DAYS:-30} 2>/dev/null | wc -l | tr -d ' ')

        if [ "$OLD_DB_BACKUPS" -gt 0 ]; then
            cleanup_old_backups "$BACKUP_DIR" "${BACKUP_RETENTION_DAYS:-30}"
            log "  Removed $OLD_DB_BACKUPS old database backups"
        else
            log "  Database backups: no old backups to remove"
        fi
    fi

    # Cleanup old logs (keep last 30 days)
    if [ -d "$LOG_DIR" ]; then
        log "  Cleaning up old logs (older than 30 days)"
        OLD_LOGS=$(find "$LOG_DIR" -name "*.log" -mtime +30 2>/dev/null | wc -l | tr -d ' ')

        if [ "$OLD_LOGS" -gt 0 ]; then
            find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
            log "  Removed $OLD_LOGS old log files"
        else
            log "  Logs: no old logs to remove"
        fi
    fi

    APPS_PROCESSED=$((APPS_PROCESSED + 1))
    log "  Cleanup completed for $APP_NAME"
done

# Cleanup dangling Docker images (no tag)
log "------------------------------------------------------------------------"
log "Cleaning up dangling Docker images..."
DANGLING_BEFORE=$(docker images -f "dangling=true" -q | wc -l | tr -d ' ')

if [ "$DANGLING_BEFORE" -gt 0 ]; then
    docker image prune -f >/dev/null 2>&1 || true
    DANGLING_AFTER=$(docker images -f "dangling=true" -q | wc -l | tr -d ' ')
    log "Dangling images: $DANGLING_BEFORE -> $DANGLING_AFTER"
else
    log "No dangling images to clean up"
fi

# Cleanup stopped containers (older than 7 days)
log "------------------------------------------------------------------------"
log "Cleaning up stopped containers (older than 7 days)..."
STOPPED_CONTAINERS=$(docker ps -a -f "status=exited" --format "{{.ID}}" | wc -l | tr -d ' ')

if [ "$STOPPED_CONTAINERS" -gt 0 ]; then
    docker container prune -f --filter "until=168h" >/dev/null 2>&1 || true
    CONTAINERS_AFTER=$(docker ps -a -f "status=exited" --format "{{.ID}}" | wc -l | tr -d ' ')
    log "Stopped containers: $STOPPED_CONTAINERS -> $CONTAINERS_AFTER"
else
    log "No stopped containers to clean up"
fi

# Summary
log "========================================================================"
log "Cleanup summary:"
log "  Apps processed: $APPS_PROCESSED"
log "  Apps failed: $APPS_FAILED"
log "  Status: SUCCESS"
log "========================================================================"

exit 0
