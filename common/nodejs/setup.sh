#!/bin/bash

# Node.js-specific setup functions
# Location: /home/andrzej/DevOps/common/nodejs/setup.sh
# This file should be sourced by app-specific setup.sh scripts

# This file provides Node.js-specific setup functionality that can be:
# 1. Used as-is by sourcing it
# 2. Overridden by defining functions with the same name AFTER sourcing
# 3. Extended with pre/post hooks

# Function: Check Node.js prerequisites
nodejs_check_prerequisites() {
    log_info "Checking Node.js prerequisites..."

    if ! command_exists node; then
        log_error "Node.js is not installed. Please run ubuntu-init-setup.sh first."
        return 1
    fi

    if ! command_exists npm; then
        log_error "npm is not installed. Please install Node.js first."
        return 1
    fi

    # Check for optional dependencies based on app needs
    if [ "${NEEDS_POSTGRES:-false}" = "true" ]; then
        if ! command_exists psql; then
            log_error "PostgreSQL is not installed but is required by this app."
            return 1
        fi
    fi

    if [ "${NEEDS_REDIS:-false}" = "true" ]; then
        if ! command_exists redis-cli; then
            log_error "Redis is not installed but is required by this app."
            return 1
        fi

        if ! redis-cli ping > /dev/null 2>&1; then
            log_error "Redis is not running. Please start Redis service."
            return 1
        fi
    fi

    log_success "All Node.js prerequisites are installed"
    return 0
}

# Function: Setup Node.js database (if needed)
nodejs_setup_database() {
    if [ "${NEEDS_POSTGRES:-false}" != "true" ]; then
        log_info "Database not required for this Node.js app"
        return 0
    fi

    log_info "Setting up Node.js database..."

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

# Function: Create Node.js environment file
nodejs_create_env_file() {
    log_info "Creating Node.js environment file: ${ENV_FILE}"

    if [ -f "$ENV_FILE" ]; then
        log_warning "Environment file already exists. Backing up..."
        cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Create production env file
    cat > "$ENV_FILE" << EOF
# Production Environment Variables for ${APP_NAME}
# Generated on $(date)
# Location: ${ENV_FILE}

# Node Environment
NODE_ENV=production

# Application Port
PORT=80

EOF

    # Add database URL if needed
    if [ "${NEEDS_POSTGRES:-false}" = "true" ]; then
        cat >> "$ENV_FILE" << EOF
# Database Configuration
DATABASE_URL=${DATABASE_URL}

EOF
    fi

    # Add Redis URL if needed
    if [ "${NEEDS_REDIS:-false}" = "true" ]; then
        cat >> "$ENV_FILE" << EOF
# Redis Configuration (Dedicated database)
REDIS_URL=${REDIS_URL}

EOF
    fi

    # Add Mailgun configuration if enabled
    if [ "${NEEDS_MAILGUN:-false}" = "true" ]; then
        cat >> "$ENV_FILE" << EOF
# Mailgun Configuration (for application emails)
MAILGUN_API_KEY=${MAILGUN_API_KEY}
MAILGUN_DOMAIN=${MAILGUN_DOMAIN}
MAILGUN_FROM_EMAIL=${MAILGUN_FROM_EMAIL}

EOF
    fi

    # Add app-specific environment variables if defined
    if [ -n "${APP_ENV_VARS[*]}" ]; then
        for env_var in "${APP_ENV_VARS[@]}"; do
            echo "$env_var" >> "$ENV_FILE"
        done
    fi

    log_success "Environment file created: ${ENV_FILE}"
    log_warning "IMPORTANT: Edit ${ENV_FILE} and update the credentials as needed!"

    return 0
}

# Function: Setup native Node.js environment
nodejs_setup_native_environment() {
    log_info "Setting up native Node.js environment..."
    cd "$REPO_DIR"

    # Check Node version
    REQUIRED_NODE_VERSION=$(cat .nvmrc 2>/dev/null || cat .node-version 2>/dev/null || echo "20")
    CURRENT_NODE_VERSION=$(node -v | grep -oP '\d+\.\d+\.\d+' | head -1)

    log_info "Required Node version: ${REQUIRED_NODE_VERSION}"
    log_info "Current Node version: ${CURRENT_NODE_VERSION}"

    # Install dependencies
    log_info "Installing npm dependencies (this may take a few minutes)..."

    # Use npm ci if package-lock.json exists, otherwise npm install
    if [ -f "package-lock.json" ]; then
        npm ci --production
    else
        npm install --production
    fi

    if [ $? -eq 0 ]; then
        log_success "Dependencies installed successfully"
    else
        log_error "Failed to install dependencies"
        return 1
    fi

    # Create symlink to .env.production for easier access
    ln -sf "$ENV_FILE" "${REPO_DIR}/.env.production"
    log_success "Created symlink: ${REPO_DIR}/.env.production -> ${ENV_FILE}"

    # Set proper permissions
    chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$REPO_DIR"

    log_success "Native Node.js environment configured"
    return 0
}

# Function: Build Node.js application (if build step exists)
nodejs_build_application() {
    cd "$REPO_DIR"

    # Check if build script exists in package.json
    if grep -q '"build"' package.json 2>/dev/null; then
        log_info "Building Node.js application..."

        NODE_ENV=production npm run build

        if [ $? -eq 0 ]; then
            log_success "Application built successfully"
            return 0
        else
            log_error "Build failed"
            return 1
        fi
    else
        log_info "No build script found, skipping build step"
        return 0
    fi
}

# Function: Run Node.js database migrations (if applicable)
nodejs_run_migrations() {
    cd "$REPO_DIR"

    # Check for common migration commands
    if grep -q '"migrate"' package.json 2>/dev/null; then
        log_info "Running database migrations..."

        # Load environment variables
        set -a
        source "$ENV_FILE"
        set +a

        NODE_ENV=production npm run migrate

        if [ $? -eq 0 ]; then
            log_success "Migrations completed successfully"
            return 0
        else
            log_error "Migrations failed"
            return 1
        fi
    else
        log_info "No migration script found, skipping migrations"
        return 0
    fi
}

# Function: Main Node.js setup workflow
nodejs_setup_workflow() {
    # Check prerequisites
    nodejs_check_prerequisites || return 1

    # Setup database if needed
    nodejs_setup_database || return 1

    # Create environment file
    nodejs_create_env_file || return 1

    # Setup native Node.js environment
    nodejs_setup_native_environment || return 1

    # Build application if needed
    nodejs_build_application || return 1

    # Build initial Docker image
    log_info "Building initial Docker image..."
    docker build -t "${DOCKER_IMAGE_NAME}:latest" "$REPO_DIR"

    if [ $? -ne 0 ]; then
        log_error "Failed to build Docker image"
        return 1
    fi

    log_success "Docker image built successfully"

    # Run migrations if applicable
    nodejs_run_migrations || return 1

    log_success "Node.js setup workflow completed"
    return 0
}
