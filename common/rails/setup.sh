#!/bin/bash

# Rails-specific setup functions
# Location: /home/andrzej/DevOps/common/rails/setup.sh
# This file should be sourced by app-specific setup.sh scripts

# This file provides Rails-specific setup functionality that can be:
# 1. Used as-is by sourcing it
# 2. Overridden by defining functions with the same name AFTER sourcing
# 3. Extended with pre/post hooks

# Function: Check Rails prerequisites
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

# Function: Setup Rails database
rails_setup_database() {
    log_info "Setting up Rails database..."

    # Generate database user name from app name (don't use 'local' - we need to export these)
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

# Function: Create Rails environment file
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
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

# Redis Configuration (Dedicated database)
REDIS_URL=${REDIS_URL}

# Mailgun Configuration (for application emails)
MAILGUN_API_KEY=${MAILGUN_API_KEY:-dummy_mailgun_key}
MAILGUN_DOMAIN=${MAILGUN_DOMAIN:-mg.example.com}
MAILGUN_FROM_EMAIL=${MAILGUN_FROM_EMAIL:-noreply@example.com}
MAIL_DELIVERY_METHOD=mailgun_api

# Application Port
PORT=80
WEB_CONCURRENCY=2
RAILS_MAX_THREADS=5

# App-specific environment variables
EOF

    # Add app-specific environment variables if defined
    if [ -n "${APP_ENV_VARS[*]}" ]; then
        for env_var in "${APP_ENV_VARS[@]}"; do
            echo "$env_var" >> "$ENV_FILE"
        done
    fi

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

# Function: Setup native Rails environment
rails_setup_native_environment() {
    log_info "Setting up native Rails environment for console access..."
    cd "$REPO_DIR"

    # Check Ruby version
    REQUIRED_RUBY_VERSION=$(cat .ruby-version 2>/dev/null || echo "3.3.4")
    CURRENT_RUBY_VERSION=$(ruby -v | grep -oP '\d+\.\d+\.\d+' | head -1)

    log_info "Required Ruby version: ${REQUIRED_RUBY_VERSION}"
    log_info "Current Ruby version: ${CURRENT_RUBY_VERSION}"

    # Install bundler if not present
    if ! command_exists bundle; then
        log_info "Installing bundler..."
        gem install bundler
    fi

    # Configure bundler to use .bundle/vendor
    log_info "Configuring bundler to use .bundle/vendor..."
    bundle config set --local path '.bundle/vendor'
    bundle config set --local without 'development test'

    # Install application gems for production use
    log_info "Installing application gems (this may take a few minutes)..."
    RAILS_ENV=production bundle install

    if [ $? -eq 0 ]; then
        log_success "Gems installed successfully"
    else
        log_error "Failed to install gems"
        return 1
    fi

    # Create symlink to .env.production for easier access
    ln -sf "$ENV_FILE" "${REPO_DIR}/.env.production"
    log_success "Created symlink: ${REPO_DIR}/.env.production -> ${ENV_FILE}"

    # Set proper permissions
    chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$REPO_DIR"

    log_success "Native Rails environment configured"
    return 0
}

# Function: Precompile Rails assets
rails_precompile_assets() {
    log_info "Skipping native asset precompilation (will be done in Docker)..."
    log_success "Asset precompilation will occur during Docker build"
    return 0
}

# Function: Run Rails migrations
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

    bundle exec rails db:migrate

    if [ $? -eq 0 ]; then
        log_success "Migrations completed successfully"
        return 0
    else
        log_warning "Migrations failed (may need to run manually after fixing env vars)"
        return 0  # Don't fail setup, migrations can be run later
    fi
}

# Function: Main Rails setup workflow
# This can be called from app-specific setup.sh or individual functions can be called
rails_setup_workflow() {
    # Check prerequisites
    rails_check_prerequisites || return 1

    # Setup database
    rails_setup_database || return 1

    # Create environment file
    rails_create_env_file || return 1

    # Setup native Rails environment
    rails_setup_native_environment || return 1

    # Precompile assets
    rails_precompile_assets || return 1

    # Build initial Docker image
    log_info "Building initial Docker image..."

    # Create temporary .env file with dummy values for Docker build
    # This prevents errors when Rails loads environment during asset precompilation
    log_info "Creating temporary .env file for Docker build..."

    # Copy ALL env vars from production .env to Docker build .env
    # This ensures Docker build has access to all required env vars
    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "${REPO_DIR}/.env"
        log_info "Copied .env.production to .env for Docker build"
    else
        log_error "Environment file not found: $ENV_FILE"
        return 1
    fi

    if docker build -t "${DOCKER_IMAGE_NAME}:latest" "$REPO_DIR"; then
        log_success "Docker image built successfully"
    else
        log_warning "Docker build failed (will retry during deploy with real env vars)"
        log_info "Edit ${ENV_FILE} with real values, then run deploy"
    fi

    # Remove temporary .env file after build
    rm -f "${REPO_DIR}/.env"
    log_info "Removed temporary build .env file"

    # Run migrations (non-critical, user can run manually)
    rails_run_migrations || true

    log_success "Rails setup workflow completed"
    return 0
}
