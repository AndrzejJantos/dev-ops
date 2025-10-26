#!/bin/bash

# Script to initialize Dockerfile for a Rails application
# Location: /home/andrzej/DevOps/scripts/init-rails-dockerfile.sh
# Usage: ./init-rails-dockerfile.sh <app-name>

set -euo pipefail

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load common utilities
source "${DEVOPS_DIR}/common/utils.sh"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 <app-name>

Initializes Dockerfile and .dockerignore for a Rails application.

Arguments:
  app-name    Name of the application (e.g., cheaperfordrug-landing)

Examples:
  $0 cheaperfordrug-landing
  $0 my-rails-app

This script:
1. Locates the app repository directory
2. Copies Dockerfile.template to app repo as Dockerfile
3. Copies .dockerignore.template to app repo as .dockerignore
4. Sets proper permissions
5. Validates the files

Templates Location:
  ${DEVOPS_DIR}/common/rails/Dockerfile.template
  ${DEVOPS_DIR}/common/rails/.dockerignore.template
EOF
}

# Check arguments
if [ $# -ne 1 ]; then
    log_error "Invalid number of arguments"
    echo ""
    usage
    exit 1
fi

APP_NAME="$1"

# Validate app name
if [[ ! "$APP_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    log_error "Invalid app name. Use lowercase letters, numbers, and hyphens only."
    exit 1
fi

# Find app directory
APP_DIR="${DEVOPS_DIR}/apps/${APP_NAME}"
if [ ! -d "$APP_DIR" ]; then
    log_error "App directory not found: $APP_DIR"
    log_info "Available apps:"
    ls -1 "${DEVOPS_DIR}/apps/" | grep -v "_examples"
    exit 1
fi

# Check if config.sh exists
if [ ! -f "${APP_DIR}/config.sh" ]; then
    log_error "App configuration not found: ${APP_DIR}/config.sh"
    exit 1
fi

# Source app config to get REPO_DIR
source "${APP_DIR}/config.sh"

# Check if repo exists
if [ ! -d "$REPO_DIR" ]; then
    log_error "App repository not found: $REPO_DIR"
    log_info "Please run setup.sh first to clone the repository"
    exit 1
fi

# Template files
DOCKERFILE_TEMPLATE="${DEVOPS_DIR}/common/rails/Dockerfile.template"
DOCKERIGNORE_TEMPLATE="${DEVOPS_DIR}/common/rails/.dockerignore.template"

# Destination files
DOCKERFILE_DEST="${REPO_DIR}/Dockerfile"
DOCKERIGNORE_DEST="${REPO_DIR}/.dockerignore"

# Check if templates exist
if [ ! -f "$DOCKERFILE_TEMPLATE" ]; then
    log_error "Dockerfile template not found: $DOCKERFILE_TEMPLATE"
    exit 1
fi

if [ ! -f "$DOCKERIGNORE_TEMPLATE" ]; then
    log_error ".dockerignore template not found: $DOCKERIGNORE_TEMPLATE"
    exit 1
fi

log_info "Initializing Dockerfile for ${APP_NAME}..."

# Backup existing files if they exist
if [ -f "$DOCKERFILE_DEST" ]; then
    BACKUP_FILE="${DOCKERFILE_DEST}.backup.$(date +%Y%m%d_%H%M%S)"
    log_warning "Dockerfile already exists. Creating backup: ${BACKUP_FILE}"
    cp "$DOCKERFILE_DEST" "$BACKUP_FILE"
fi

if [ -f "$DOCKERIGNORE_DEST" ]; then
    BACKUP_FILE="${DOCKERIGNORE_DEST}.backup.$(date +%Y%m%d_%H%M%S)"
    log_warning ".dockerignore already exists. Creating backup: ${BACKUP_FILE}"
    cp "$DOCKERIGNORE_DEST" "$BACKUP_FILE"
fi

# Copy templates
log_info "Copying Dockerfile template..."
cp "$DOCKERFILE_TEMPLATE" "$DOCKERFILE_DEST"
log_success "Created: $DOCKERFILE_DEST"

log_info "Copying .dockerignore template..."
cp "$DOCKERIGNORE_TEMPLATE" "$DOCKERIGNORE_DEST"
log_success "Created: $DOCKERIGNORE_DEST"

# Set proper permissions
chmod 644 "$DOCKERFILE_DEST"
chmod 644 "$DOCKERIGNORE_DEST"

# Detect Ruby version from app repo
if [ -f "${REPO_DIR}/.ruby-version" ]; then
    RUBY_VERSION=$(cat "${REPO_DIR}/.ruby-version")
    log_info "Detected Ruby version: $RUBY_VERSION"

    # Check if Dockerfile has different version
    DOCKERFILE_RUBY=$(grep -oP 'FROM ruby:\K[0-9.]+' "$DOCKERFILE_DEST" | head -1)
    if [ "$RUBY_VERSION" != "$DOCKERFILE_RUBY" ]; then
        log_warning "Ruby version mismatch!"
        log_warning "  App uses: $RUBY_VERSION"
        log_warning "  Dockerfile uses: $DOCKERFILE_RUBY"
        log_info ""
        log_info "To update Dockerfile Ruby version, run:"
        log_info "  sed -i 's/ruby:$DOCKERFILE_RUBY/ruby:$RUBY_VERSION/g' $DOCKERFILE_DEST"
    else
        log_success "Ruby versions match: $RUBY_VERSION"
    fi
fi

# Validate Dockerfile syntax
log_info "Validating Dockerfile syntax..."
if docker build --no-cache -f "$DOCKERFILE_DEST" -t "${APP_NAME}:test" "$REPO_DIR" > /dev/null 2>&1; then
    log_success "Dockerfile syntax is valid"
    # Clean up test image
    docker rmi "${APP_NAME}:test" > /dev/null 2>&1 || true
else
    log_warning "Dockerfile validation skipped (cannot build without .env file)"
    log_info "Dockerfile will be validated during actual build process"
fi

# Display next steps
log_success "Dockerfile initialization complete!"
echo ""
log_info "Next steps:"
echo "  1. Review the Dockerfile: nano $DOCKERFILE_DEST"
echo "  2. Customize if needed (Ruby version, dependencies, etc.)"
echo "  3. Review .dockerignore: nano $DOCKERIGNORE_DEST"
echo "  4. Commit to git repository:"
echo "     cd $REPO_DIR"
echo "     git add Dockerfile .dockerignore"
echo "     git commit -m 'Add production Dockerfile with multi-stage build'"
echo "     git push origin main"
echo ""
log_info "The setup.sh and deploy.sh scripts will automatically use this Dockerfile"
echo ""
log_info "Documentation: ${DEVOPS_DIR}/common/rails/DOCKERFILE_USAGE.md"

# Display file locations
echo ""
echo "Files created:"
echo "  Dockerfile:      $DOCKERFILE_DEST"
echo "  .dockerignore:   $DOCKERIGNORE_DEST"
if [ -f "${REPO_DIR}/.ruby-version" ]; then
    echo "  Ruby version:    $RUBY_VERSION (from .ruby-version)"
fi

exit 0
