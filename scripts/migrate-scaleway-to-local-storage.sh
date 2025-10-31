#!/bin/bash

# Migration Script: Scaleway S3 to Local Host Storage
# This script migrates Active Storage files from Scaleway to local disk
#
# Usage:
#   Run on server via SSH:
#   ssh hetzner-andrzej "bash -s" < migrate-scaleway-to-local-storage.sh
#
#   Or run directly on server:
#   ./migrate-scaleway-to-local-storage.sh
#
# What it does:
#   1. Creates local storage directory structure
#   2. Downloads all files from Scaleway to local storage
#   3. Preserves Active Storage's directory structure
#   4. Updates .env.production to use host_disk service
#   5. Validates migration by checking file counts
#   6. Provides rollback instructions

set -e

# ==============================================================================
# CONFIGURATION
# ==============================================================================

APP_NAME="brokik-api"
APP_DIR="$HOME/apps/$APP_NAME"
ENV_FILE="$APP_DIR/.env.production"
REPO_DIR="$APP_DIR/repo"

# Colors for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

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

# ==============================================================================
# PREFLIGHT CHECKS
# ==============================================================================

preflight_checks() {
    log_info "=== Preflight Checks ==="

    # Check if app directory exists
    if [ ! -d "$APP_DIR" ]; then
        log_error "App directory not found: $APP_DIR"
        exit 1
    fi

    # Check if env file exists
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file not found: $ENV_FILE"
        exit 1
    fi

    # Check if containers are running
    local container_count=$(docker ps --filter "name=${APP_NAME}" --format "{{.Names}}" | wc -l)
    if [ $container_count -eq 0 ]; then
        log_error "No ${APP_NAME} containers are running"
        log_error "Please start the application first: cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh deploy"
        exit 1
    fi

    log_success "Preflight checks passed"
    echo ""
}

# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================

load_configuration() {
    log_info "=== Loading Configuration ==="

    # Load environment variables
    set -a
    source "$ENV_FILE"
    set +a

    # Verify Scaleway configuration exists
    if [ -z "${SCALEWAY_ENDPOINT:-}" ]; then
        log_error "SCALEWAY_ENDPOINT not found in $ENV_FILE"
        log_error "This script requires existing Scaleway configuration"
        exit 1
    fi

    # Set default storage path if not configured
    if [ -z "${ACTIVE_STORAGE_HOST_PATH:-}" ]; then
        ACTIVE_STORAGE_HOST_PATH="/var/storage/${APP_NAME}/active_storage"
        log_info "ACTIVE_STORAGE_HOST_PATH not set, using default: ${ACTIVE_STORAGE_HOST_PATH}"
    fi

    log_success "Configuration loaded"
    log_info "Current service: ${RAILS_ACTIVE_STORAGE_SERVICE:-local}"
    log_info "Target path: ${ACTIVE_STORAGE_HOST_PATH}"
    echo ""
}

# ==============================================================================
# CREATE LOCAL STORAGE STRUCTURE
# ==============================================================================

create_local_storage() {
    log_info "=== Creating Local Storage Structure ==="

    # Create base storage directory
    if [ ! -d "$ACTIVE_STORAGE_HOST_PATH" ]; then
        log_info "Creating directory: ${ACTIVE_STORAGE_HOST_PATH}"
        sudo mkdir -p "$ACTIVE_STORAGE_HOST_PATH"
        sudo chown $(whoami):$(whoami) "$ACTIVE_STORAGE_HOST_PATH"
        chmod 777 "$ACTIVE_STORAGE_HOST_PATH"
        log_success "Directory created"
    else
        log_warning "Directory already exists: ${ACTIVE_STORAGE_HOST_PATH}"
    fi

    echo ""
}

# ==============================================================================
# MIGRATE FILES
# ==============================================================================

migrate_files() {
    log_info "=== Migrating Files from Scaleway to Local Storage ==="

    # Get container name
    local container_name="${APP_NAME}_web_1"

    # Count files in Scaleway
    log_info "Counting files in Scaleway..."
    local scaleway_count=$(docker exec "$container_name" bundle exec rails runner "puts ActiveStorage::Blob.count" 2>/dev/null || echo "0")
    log_info "Files in Scaleway: ${scaleway_count}"

    if [ "$scaleway_count" = "0" ]; then
        log_warning "No files found in Scaleway"
        echo ""
        return 0
    fi

    # Create temporary migration script
    local migration_script="/tmp/migrate_active_storage.rb"
    cat > "$migration_script" << 'RUBY_SCRIPT'
# Active Storage Migration Script
# Downloads all files from current service to local disk

require "fileutils"

target_path = ENV["ACTIVE_STORAGE_HOST_PATH"]
puts "Target path: #{target_path}"
puts "Current service: #{Rails.configuration.active_storage.service}"

total = ActiveStorage::Blob.count
puts "\nMigrating #{total} files..."

success_count = 0
error_count = 0
errors = []

ActiveStorage::Blob.find_each.with_index do |blob, index|
  begin
    # Download file from current service (Scaleway)
    file_data = blob.download

    # Build local file path matching Active Storage structure
    # ActiveStorage uses: /XX/YY/hash structure
    key = blob.key
    local_dir = File.join(target_path, key[0..1], key[2..3])
    local_file = File.join(local_dir, key)

    # Create directory structure
    FileUtils.mkdir_p(local_dir)

    # Write file
    File.binwrite(local_file, file_data)

    # Set permissions
    File.chmod(0644, local_file)

    success_count += 1
    print "\rProgress: #{index + 1}/#{total} (#{((index + 1).to_f / total * 100).round(1)}%)"
  rescue => e
    error_count += 1
    errors << "Blob #{blob.id} (#{blob.filename}): #{e.message}"
    print "\rProgress: #{index + 1}/#{total} (#{((index + 1).to_f / total * 100).round(1)}%) - #{error_count} errors"
  end
end

puts "\n\nMigration Complete!"
puts "Success: #{success_count}"
puts "Errors: #{error_count}"

if errors.any?
  puts "\nErrors encountered:"
  errors.first(10).each { |err| puts "  - #{err}" }
  puts "  ... and #{errors.size - 10} more" if errors.size > 10
end

exit(error_count > 0 ? 1 : 0)
RUBY_SCRIPT

    # Copy migration script to container
    docker cp "$migration_script" "$container_name:/tmp/migrate_active_storage.rb"

    # Run migration inside container
    log_info "Running migration (this may take several minutes)..."
    if docker exec -e ACTIVE_STORAGE_HOST_PATH="$ACTIVE_STORAGE_HOST_PATH" \
        "$container_name" \
        bundle exec rails runner /tmp/migrate_active_storage.rb; then
        log_success "Migration completed successfully"
    else
        log_error "Migration completed with errors"
        log_warning "Some files may not have been migrated"
    fi

    # Cleanup
    rm -f "$migration_script"
    docker exec "$container_name" rm -f /tmp/migrate_active_storage.rb

    echo ""
}

# ==============================================================================
# UPDATE CONFIGURATION
# ==============================================================================

update_configuration() {
    log_info "=== Updating Configuration ==="

    # Backup current env file
    local backup_file="${ENV_FILE}.backup.scaleway.$(date +%Y%m%d_%H%M%S)"
    cp "$ENV_FILE" "$backup_file"
    log_success "Backed up env file to: $backup_file"

    # Update RAILS_ACTIVE_STORAGE_SERVICE
    if grep -q "^RAILS_ACTIVE_STORAGE_SERVICE=" "$ENV_FILE"; then
        sed -i "s/^RAILS_ACTIVE_STORAGE_SERVICE=.*/RAILS_ACTIVE_STORAGE_SERVICE=host_disk/" "$ENV_FILE"
        log_success "Updated RAILS_ACTIVE_STORAGE_SERVICE=host_disk"
    else
        echo "RAILS_ACTIVE_STORAGE_SERVICE=host_disk" >> "$ENV_FILE"
        log_success "Added RAILS_ACTIVE_STORAGE_SERVICE=host_disk"
    fi

    # Add ACTIVE_STORAGE_HOST_PATH if not present
    if ! grep -q "^ACTIVE_STORAGE_HOST_PATH=" "$ENV_FILE"; then
        echo "ACTIVE_STORAGE_HOST_PATH=${ACTIVE_STORAGE_HOST_PATH}" >> "$ENV_FILE"
        log_success "Added ACTIVE_STORAGE_HOST_PATH=${ACTIVE_STORAGE_HOST_PATH}"
    fi

    # Comment out Scaleway credentials (keep for rollback)
    sed -i 's/^SCALEWAY_/#SCALEWAY_/' "$ENV_FILE"
    log_success "Commented out Scaleway credentials (kept for rollback)"

    echo ""
}

# ==============================================================================
# RESTART APPLICATION
# ==============================================================================

restart_application() {
    log_info "=== Restarting Application ==="

    log_warning "Application needs to be restarted to use new storage configuration"
    log_info "The new containers will mount: ${ACTIVE_STORAGE_HOST_PATH}"

    echo ""
    read -p "Restart application now? [y/N] " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Restarting application..."
        cd ~/DevOps/apps/${APP_NAME}
        ./deploy.sh restart

        log_success "Application restarted with new storage configuration"
    else
        log_warning "Application NOT restarted"
        log_warning "Run this command manually when ready:"
        log_warning "  cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh restart"
    fi

    echo ""
}

# ==============================================================================
# VERIFY MIGRATION
# ==============================================================================

verify_migration() {
    log_info "=== Verifying Migration ==="

    # Count files in local storage
    local local_count=$(find "$ACTIVE_STORAGE_HOST_PATH" -type f 2>/dev/null | wc -l)
    log_info "Files in local storage: ${local_count}"

    # Get count from database
    local container_name="${APP_NAME}_web_1"
    local db_count=$(docker exec "$container_name" bundle exec rails runner "puts ActiveStorage::Blob.count" 2>/dev/null || echo "0")
    log_info "Files in database: ${db_count}"

    if [ "$local_count" -eq "$db_count" ]; then
        log_success "File counts match! Migration verified."
    else
        log_warning "File count mismatch!"
        log_warning "This may be expected if some files failed to migrate"
        log_warning "Check the migration output above for errors"
    fi

    echo ""
}

# ==============================================================================
# DISPLAY SUMMARY
# ==============================================================================

display_summary() {
    log_info "=== Migration Summary ==="

    cat << EOF

${GREEN}Migration Complete!${NC}

${YELLOW}What was done:${NC}
1. Created local storage directory: ${ACTIVE_STORAGE_HOST_PATH}
2. Downloaded all files from Scaleway to local storage
3. Updated .env.production to use host_disk service
4. Backed up original configuration

${YELLOW}Next Steps:${NC}
1. Restart the application (if not done already):
   ${BLUE}cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh restart${NC}

2. Test file uploads/downloads to ensure everything works

3. Monitor logs for any issues:
   ${BLUE}docker logs ${APP_NAME}_web_1 -f${NC}

${YELLOW}Rollback (if needed):${NC}
If you need to rollback to Scaleway:
1. Restore env file:
   ${BLUE}cp ${ENV_FILE}.backup.scaleway.* ${ENV_FILE}${NC}

2. Restart application:
   ${BLUE}cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh restart${NC}

${YELLOW}Storage Information:${NC}
- Local storage path: ${ACTIVE_STORAGE_HOST_PATH}
- Service: host_disk
- Files migrated: $(find "$ACTIVE_STORAGE_HOST_PATH" -type f 2>/dev/null | wc -l)

${GREEN}All done!${NC}
EOF

    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    echo ""
    log_info "==================================================="
    log_info "Active Storage Migration: Scaleway → Local Storage"
    log_info "==================================================="
    echo ""

    preflight_checks
    load_configuration
    create_local_storage
    migrate_files
    update_configuration
    verify_migration
    restart_application
    display_summary
}

# Run main function
main
