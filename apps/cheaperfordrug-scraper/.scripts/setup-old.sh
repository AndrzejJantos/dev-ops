#!/bin/bash

# CheaperForDrug Scraper Initial Setup Script
# Sets up directories, clones repository, and configures environment

set -e

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common utilities
source "$DEVOPS_DIR/common/utils.sh"

# Load app configuration
APP_CONFIG="$SCRIPT_DIR/config.sh"
if [ -f "$APP_CONFIG" ]; then
    source "$APP_CONFIG"
    log_success "Configuration loaded from $APP_CONFIG"
else
    log_error "Configuration file not found: $APP_CONFIG"
    exit 1
fi

# ============================================================================
# Setup Functions
# ============================================================================

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."

    local missing_commands=()

    # Check for required commands
    for cmd in docker docker-compose git curl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error "Please install the missing dependencies"
        exit 1
    fi

    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi

    log_success "All system requirements met"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."

    # Main directories
    mkdir -p "$APP_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$IMAGE_BACKUP_DIR"

    # Country-specific directories
    mkdir -p "$POLAND_LOG_DIR"
    mkdir -p "$GERMANY_LOG_DIR"
    mkdir -p "$CZECH_LOG_DIR"

    mkdir -p "$POLAND_OUTPUT_DIR"
    mkdir -p "$GERMANY_OUTPUT_DIR"
    mkdir -p "$CZECH_OUTPUT_DIR"

    mkdir -p "$POLAND_STATE_DIR"
    mkdir -p "$GERMANY_STATE_DIR"
    mkdir -p "$CZECH_STATE_DIR"

    log_success "Directories created"
}

# Clone repository
clone_repository() {
    log_info "Cloning repository..."

    if [ -d "$REPO_DIR" ]; then
        log_warning "Repository directory already exists: $REPO_DIR"
        log_info "Updating existing repository..."

        cd "$REPO_DIR"
        git fetch origin
        git checkout "$REPO_BRANCH"
        git pull origin "$REPO_BRANCH"

        log_success "Repository updated"
    else
        log_info "Cloning from: $REPO_URL"
        log_info "Branch: $REPO_BRANCH"

        if git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"; then
            log_success "Repository cloned successfully"
        else
            log_error "Failed to clone repository"
            exit 1
        fi
    fi
}

# Setup environment file
setup_environment() {
    log_info "Setting up environment file..."

    # Check if .env file already exists
    if [ -f "$ENV_FILE" ]; then
        log_warning "Environment file already exists: $ENV_FILE"
        log_warning "Skipping environment setup"
        return 0
    fi

    # Copy template
    local template_file="$SCRIPT_DIR/.env.production.template"

    if [ ! -f "$template_file" ]; then
        log_error "Environment template not found: $template_file"
        exit 1
    fi

    cp "$template_file" "$ENV_FILE"

    log_info "Environment file created: $ENV_FILE"
    log_warning "Please edit $ENV_FILE and set required values:"
    log_warning "  - NORDVPN_TOKEN"
    log_warning "  - API_TOKEN"
    log_warning "  - SCRAPER_AUTH_TOKEN"

    # Prompt for NordVPN token
    echo ""
    read -p "Enter NordVPN Token (or press Enter to skip): " nordvpn_token

    if [ -n "$nordvpn_token" ]; then
        sed -i.bak "s/^NORDVPN_TOKEN=.*/NORDVPN_TOKEN=$nordvpn_token/" "$ENV_FILE"
        rm -f "$ENV_FILE.bak"
        log_success "NordVPN token saved"
    fi

    # Prompt for API token
    echo ""
    read -p "Enter API Token (default: Andrzej12345): " api_token
    api_token="${api_token:-Andrzej12345}"
    sed -i.bak "s/^API_TOKEN=.*/API_TOKEN=$api_token/" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"

    # Prompt for Scraper Auth Token
    echo ""
    read -p "Enter Scraper Auth Token (default: Andrzej12345): " scraper_token
    scraper_token="${scraper_token:-Andrzej12345}"
    sed -i.bak "s/^SCRAPER_AUTH_TOKEN=.*/SCRAPER_AUTH_TOKEN=$scraper_token/" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"

    log_success "Environment file configured"
}

# Validate environment file
validate_environment() {
    log_info "Validating environment file..."

    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file not found: $ENV_FILE"
        log_error "Please run setup to create it"
        exit 1
    fi

    # Source the environment file
    source "$ENV_FILE"

    # Check required variables
    local missing_vars=()

    if [ -z "$NORDVPN_TOKEN" ]; then
        missing_vars+=("NORDVPN_TOKEN")
    fi

    if [ -z "$API_TOKEN" ]; then
        missing_vars+=("API_TOKEN")
    fi

    if [ -z "$SCRAPER_AUTH_TOKEN" ]; then
        missing_vars+=("SCRAPER_AUTH_TOKEN")
    fi

    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Please edit $ENV_FILE and set these values"
        exit 1
    fi

    log_success "Environment validation passed"
}

# Setup systemd service (optional)
setup_systemd_service() {
    log_info "Do you want to set up systemd service for auto-start?"
    read -p "Setup systemd service? (y/n): " setup_systemd

    if [ "$setup_systemd" != "y" ]; then
        log_info "Skipping systemd setup"
        return 0
    fi

    local service_file="/etc/systemd/system/cheaperfordrug-scraper.service"

    log_info "Creating systemd service file..."

    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=CheaperForDrug Scraper Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$REPO_DIR
ExecStart=$SCRIPT_DIR/deploy.sh start
ExecStop=$SCRIPT_DIR/deploy.sh stop
User=$USER

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable cheaperfordrug-scraper.service

    log_success "Systemd service created and enabled"
    log_info "Use: sudo systemctl start cheaperfordrug-scraper"
}

# Setup log rotation
setup_log_rotation() {
    log_info "Setting up log rotation..."

    local logrotate_file="/etc/logrotate.d/cheaperfordrug-scraper"

    sudo tee "$logrotate_file" > /dev/null <<EOF
$LOG_DIR/*/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    missingok
    create 0644 $USER $USER
}
EOF

    log_success "Log rotation configured"
}

# Print setup summary
print_summary() {
    log_success "================================================================"
    log_success "Setup completed successfully!"
    log_success "================================================================"

    echo ""
    log_info "Application Directory: $APP_DIR"
    log_info "Repository: $REPO_DIR"
    log_info "Environment File: $ENV_FILE"
    echo ""
    log_info "Country-specific log directories:"
    log_info "  Poland:  $POLAND_LOG_DIR"
    log_info "  Germany: $GERMANY_LOG_DIR"
    log_info "  Czech:   $CZECH_LOG_DIR"
    echo ""
    log_info "Next steps:"
    echo "  1. Review and edit environment file: $ENV_FILE"
    echo "  2. Ensure NordVPN token is set correctly"
    echo "  3. Run deployment: $SCRIPT_DIR/deploy.sh"
    echo ""
    log_info "Useful commands:"
    echo "  Deploy:  $SCRIPT_DIR/deploy.sh deploy"
    echo "  Status:  $SCRIPT_DIR/deploy.sh status"
    echo "  Logs:    $SCRIPT_DIR/deploy.sh logs"
    echo "  Stop:    $SCRIPT_DIR/deploy.sh stop"
    echo ""
}

# ============================================================================
# Main Setup Flow
# ============================================================================

main() {
    log_info "================================================================"
    log_info "CheaperForDrug Scraper - Initial Setup"
    log_info "================================================================"

    # Check requirements
    check_requirements

    # Create directories
    create_directories

    # Clone repository
    clone_repository

    # Setup environment
    setup_environment

    # Validate environment
    if [ -f "$ENV_FILE" ]; then
        validate_environment || log_warning "Environment validation failed - please complete configuration"
    fi

    # Optional: Setup systemd service
    # setup_systemd_service

    # Optional: Setup log rotation
    # setup_log_rotation

    # Print summary
    print_summary
}

# Run main function
main "$@"
