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

    if ! check_database_exists "$DB_NAME"; then
        create_database "$DB_NAME" "$DB_USER"
        if [ $? -ne 0 ]; then
            log_error "Failed to create database"
            return 1
        fi
    else
        log_info "Database ${DB_NAME} already exists"
    fi

    # Generate database URL
    if [ -n "$DB_PASSWORD" ]; then
        DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@localhost/${DB_NAME}"
    else
        DATABASE_URL="postgresql://localhost/${DB_NAME}"
    fi

    log_success "Database configured: ${DB_NAME}"
    return 0
}

# Function: Create Rails environment file
rails_create_env_file() {
    log_info "Creating Rails environment file: ${ENV_FILE}"

    if [ -f "$ENV_FILE" ]; then
        log_warning "Environment file already exists. Backing up..."
        cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Generate SECRET_KEY_BASE
    SECRET_KEY_BASE=$(get_or_generate_secret "$ENV_FILE" "SECRET_KEY_BASE" "openssl rand -hex 64")

    # Create production env file
    cat > "$ENV_FILE" << EOF
# Production Environment Variables for ${APP_NAME}
# Generated on $(date)
# Location: ${ENV_FILE}

# Database Configuration
DATABASE_URL=${DATABASE_URL}

# Rails Configuration
SECRET_KEY_BASE=${SECRET_KEY_BASE}
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

# Redis Configuration (Dedicated database)
REDIS_URL=${REDIS_URL}

# Mailgun Configuration (for application emails)
MAILGUN_API_KEY=${MAILGUN_API_KEY}
MAILGUN_DOMAIN=${MAILGUN_DOMAIN}
MAILGUN_FROM_EMAIL=${MAILGUN_FROM_EMAIL}
MAIL_DELIVERY_METHOD=mailgun_api

# Application Port
PORT=80
WEB_CONCURRENCY=2
RAILS_MAX_THREADS=5

EOF

    # Add app-specific environment variables if defined
    if [ -n "${APP_ENV_VARS[*]}" ]; then
        for env_var in "${APP_ENV_VARS[@]}"; do
            echo "$env_var" >> "$ENV_FILE"
        done
    fi

    log_success "Environment file created: ${ENV_FILE}"
    log_warning "IMPORTANT: Edit ${ENV_FILE} and update the credentials marked with 'your_' prefixes!"

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

    # Install application gems for production use
    log_info "Installing application gems (this may take a few minutes)..."
    RAILS_ENV=production bundle install --path vendor/bundle --without development test

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
    log_info "Precompiling assets..."
    cd "$REPO_DIR"

    RAILS_ENV=production bundle exec rails assets:precompile

    if [ $? -eq 0 ]; then
        log_success "Assets precompiled successfully"
        return 0
    else
        log_warning "Asset precompilation failed (non-critical, continuing...)"
        return 0  # Non-critical, don't fail setup
    fi
}

# Function: Run Rails migrations
rails_run_migrations() {
    log_info "Running database migrations..."
    cd "$REPO_DIR"

    # Load environment variables and run migrations
    set -a
    source "$ENV_FILE"
    set +a

    RAILS_ENV=production bundle exec rails db:migrate

    if [ $? -eq 0 ]; then
        log_success "Migrations completed successfully"
        return 0
    else
        log_error "Migrations failed"
        return 1
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
    docker build \
        --build-arg MAILGUN_API_KEY=dummy_key_for_build \
        --build-arg STRIPE_PUBLISHABLE_KEY=pk_test_dummy \
        --build-arg STRIPE_SECRET_KEY=sk_test_dummy \
        --build-arg GOOGLE_ANALYTICS_ID=G-XXXXXXXXXX \
        --build-arg GOOGLE_TAG_MANAGER_ID=GTM-XXXXXXX \
        --build-arg FACEBOOK_PIXEL_ID=000000000000000 \
        --build-arg ROLLBAR_ACCESS_TOKEN=dummy_token \
        -t "${DOCKER_IMAGE_NAME}:latest" "$REPO_DIR"

    if [ $? -ne 0 ]; then
        log_error "Failed to build Docker image"
        return 1
    fi

    log_success "Docker image built successfully"

    # Run migrations
    rails_run_migrations || return 1

    log_success "Rails setup workflow completed"
    return 0
}
