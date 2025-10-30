#!/bin/bash

################################################################################
# Nginx Configuration Rebuild Script
#
# This script cleanly rebuilds all nginx configurations from templates,
# verifies container connectivity, validates SSL certificates, and safely
# applies the new configurations.
#
# Author: DevOps Team
# Date: 2025-10-30
################################################################################

set -e  # Exit on error

# ANSI color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$SCRIPT_DIR"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/nginx_backup_${BACKUP_TIMESTAMP}"
DRY_RUN=false
SKIP_SSL_CHECK=false
FORCE=false

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

log_step() {
    echo -e "\n${GREEN}==>${NC} ${BLUE}$1${NC}\n"
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Rebuild all nginx configurations from templates.

OPTIONS:
    -d, --dry-run       Show what would be done without making changes
    -s, --skip-ssl      Skip SSL certificate validation
    -f, --force         Force rebuild even if issues are found
    -h, --help          Show this help message

EXAMPLES:
    # Dry run to see what will be done
    $0 --dry-run

    # Full rebuild with SSL validation
    $0

    # Rebuild without checking SSL certificates
    $0 --skip-ssl

    # Force rebuild even if validation fails
    $0 --force

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--skip-ssl)
            SKIP_SSL_CHECK=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Show banner
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     NGINX Configuration Rebuild Script                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No changes will be made"
    echo ""
fi

################################################################################
# STEP 1: PRE-FLIGHT CHECKS
################################################################################

log_step "Step 1: Pre-flight Checks"

# Check if running with sudo privileges for nginx operations
if [ "$EUID" -eq 0 ]; then
    log_warning "Running as root - this is not recommended"
    log_info "Script will use sudo commands where needed"
fi

# Check if nginx is installed
if ! command -v nginx >/dev/null 2>&1; then
    log_error "Nginx is not installed"
    exit 1
fi
log_success "Nginx is installed"

# Check if perl is available (needed for config generation)
if ! command -v perl >/dev/null 2>&1; then
    log_error "Perl is not installed (required for config generation)"
    exit 1
fi
log_success "Perl is available"

# Check if DevOps directory structure exists
if [ ! -d "$DEVOPS_DIR/apps" ]; then
    log_error "DevOps apps directory not found: $DEVOPS_DIR/apps"
    exit 1
fi
log_success "DevOps directory structure found"

# Check if docker is available for container checks
if ! command -v docker >/dev/null 2>&1; then
    log_warning "Docker is not installed - container checks will be skipped"
    SKIP_CONTAINER_CHECK=true
else
    log_success "Docker is available"
    SKIP_CONTAINER_CHECK=false
fi

################################################################################
# STEP 2: DISCOVER APPLICATIONS
################################################################################

log_step "Step 2: Discovering Applications"

declare -a APPS
declare -A APP_CONFIGS

# Find all apps with config.sh files
for app_dir in "$DEVOPS_DIR/apps"/*; do
    if [ -d "$app_dir" ]; then
        app_name=$(basename "$app_dir")
        config_file="$app_dir/config.sh"
        nginx_template="$app_dir/nginx.conf.template"

        if [ -f "$config_file" ] && [ -f "$nginx_template" ]; then
            APPS+=("$app_name")
            APP_CONFIGS["$app_name"]="$config_file"
            log_info "Found application: $app_name"
        else
            log_warning "Skipping $app_name (missing config.sh or nginx.conf.template)"
        fi
    fi
done

if [ ${#APPS[@]} -eq 0 ]; then
    log_error "No applications found with nginx templates"
    exit 1
fi

log_success "Found ${#APPS[@]} application(s) to configure"

################################################################################
# STEP 3: BACKUP EXISTING CONFIGURATIONS
################################################################################

log_step "Step 3: Backing Up Existing Configurations"

if [ "$DRY_RUN" = false ]; then
    mkdir -p "$BACKUP_DIR"

    # Backup sites-available
    if [ -d "/etc/nginx/sites-available" ]; then
        sudo cp -r /etc/nginx/sites-available "$BACKUP_DIR/"
        log_success "Backed up sites-available"
    fi

    # Backup sites-enabled (symlinks)
    if [ -d "/etc/nginx/sites-enabled" ]; then
        # Just save the list of enabled sites
        ls -la /etc/nginx/sites-enabled > "$BACKUP_DIR/sites-enabled-list.txt"
        log_success "Backed up sites-enabled list"
    fi

    log_success "Backup saved to: $BACKUP_DIR"
else
    log_info "Would create backup in: $BACKUP_DIR"
fi

################################################################################
# STEP 4: REMOVE OLD CONFIGURATIONS
################################################################################

log_step "Step 4: Removing Old Configurations"

# List of files to keep (don't delete these)
KEEP_FILES=("default" "000-default")

if [ "$DRY_RUN" = false ]; then
    # Remove from sites-enabled (symlinks)
    for config in /etc/nginx/sites-enabled/*; do
        if [ -f "$config" ] || [ -L "$config" ]; then
            filename=$(basename "$config")

            # Check if this file should be kept
            should_keep=false
            for keep_file in "${KEEP_FILES[@]}"; do
                if [ "$filename" = "$keep_file" ]; then
                    should_keep=true
                    break
                fi
            done

            if [ "$should_keep" = false ]; then
                sudo rm "$config"
                log_info "Removed from sites-enabled: $filename"
            else
                log_info "Kept: $filename"
            fi
        fi
    done

    # Remove from sites-available (but keep the files we want to preserve)
    for config in /etc/nginx/sites-available/*; do
        if [ -f "$config" ]; then
            filename=$(basename "$config")

            # Check if this file should be kept
            should_keep=false
            for keep_file in "${KEEP_FILES[@]}"; do
                if [ "$filename" = "$keep_file" ]; then
                    should_keep=true
                    break
                fi
            done

            if [ "$should_keep" = false ]; then
                sudo rm "$config"
                log_info "Removed from sites-available: $filename"
            else
                log_info "Kept: $filename"
            fi
        fi
    done

    log_success "Old configurations removed"
else
    log_info "Would remove all nginx configs except:"
    for keep_file in "${KEEP_FILES[@]}"; do
        log_info "  - $keep_file"
    done
fi

################################################################################
# STEP 5: VERIFY CONTAINERS
################################################################################

if [ "$SKIP_CONTAINER_CHECK" = false ]; then
    log_step "Step 5: Verifying Container Status"

    declare -A CONTAINER_CHECKS

    for app_name in "${APPS[@]}"; do
        config_file="${APP_CONFIGS[$app_name]}"

        # Source the config to get ports
        source "$config_file"

        log_info "Checking containers for: $app_name"
        log_info "  Expected ports: $BASE_PORT to $((BASE_PORT + DEFAULT_SCALE - 1))"

        # Check each expected port
        containers_ok=true
        for i in $(seq 1 $DEFAULT_SCALE); do
            port=$((BASE_PORT + i - 1))

            # Check if port is listening
            if command -v netstat >/dev/null 2>&1; then
                if sudo netstat -tlnp 2>/dev/null | grep -q ":$port "; then
                    log_success "  ✓ Port $port is active"
                else
                    log_warning "  ✗ Port $port is NOT listening"
                    containers_ok=false
                fi
            elif command -v ss >/dev/null 2>&1; then
                if sudo ss -tlnp 2>/dev/null | grep -q ":$port "; then
                    log_success "  ✓ Port $port is active"
                else
                    log_warning "  ✗ Port $port is NOT listening"
                    containers_ok=false
                fi
            else
                log_warning "  Cannot check port $port (netstat/ss not available)"
            fi
        done

        CONTAINER_CHECKS["$app_name"]=$containers_ok

        if [ "$containers_ok" = false ]; then
            log_warning "Some containers for $app_name are not running"
            if [ "$FORCE" = false ]; then
                log_error "Use --force to continue anyway, or start the containers first"
                exit 1
            fi
        fi
    done

    log_success "Container verification completed"
else
    log_warning "Skipping container checks (Docker not available)"
fi

################################################################################
# STEP 6: GENERATE NEW CONFIGURATIONS
################################################################################

log_step "Step 6: Generating New Nginx Configurations"

for app_name in "${APPS[@]}"; do
    config_file="${APP_CONFIGS[$app_name]}"
    app_dir=$(dirname "$config_file")
    nginx_template="$app_dir/nginx.conf.template"

    log_info "Generating config for: $app_name"

    # Source the config
    source "$config_file"

    # Generate upstream servers configuration
    UPSTREAM_SERVERS=""
    for i in $(seq 1 $DEFAULT_SCALE); do
        PORT=$((BASE_PORT + i - 1))
        UPSTREAM_SERVERS="${UPSTREAM_SERVERS}    server localhost:${PORT} max_fails=3 fail_timeout=30s;
"
    done

    log_info "  Domain: $DOMAIN"
    log_info "  Upstream: $NGINX_UPSTREAM_NAME"
    log_info "  Ports: $BASE_PORT-$((BASE_PORT + DEFAULT_SCALE - 1))"

    if [ "$DRY_RUN" = false ]; then
        # Generate nginx config using perl
        perl -pe "
            s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g;
            s|{{DOMAIN}}|${DOMAIN}|g;
            s|{{APP_NAME}}|${APP_NAME}|g;
        " "$nginx_template" | \
        perl -pe "BEGIN{undef \$/;} s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|gs" | \
        sudo tee "/etc/nginx/sites-available/$APP_NAME" > /dev/null

        log_success "  Generated: /etc/nginx/sites-available/$APP_NAME"
    else
        log_info "  Would generate: /etc/nginx/sites-available/$APP_NAME"
    fi
done

log_success "All configurations generated"

################################################################################
# STEP 7: VALIDATE SSL CERTIFICATES
################################################################################

if [ "$SKIP_SSL_CHECK" = false ]; then
    log_step "Step 7: Validating SSL Certificates"

    declare -A SSL_CHECKS

    for app_name in "${APPS[@]}"; do
        config_file="${APP_CONFIGS[$app_name]}"
        source "$config_file"

        log_info "Checking SSL for: $DOMAIN"

        # Common SSL certificate paths
        ssl_cert_path="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        ssl_key_path="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

        if sudo test -f "$ssl_cert_path" && sudo test -f "$ssl_key_path"; then
            # Check expiration
            if command -v openssl >/dev/null 2>&1; then
                expiry_date=$(sudo openssl x509 -enddate -noout -in "$ssl_cert_path" | cut -d= -f2)
                expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
                now_epoch=$(date +%s)
                days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

                if [ $days_left -gt 30 ]; then
                    log_success "  ✓ Certificate valid ($days_left days remaining)"
                    SSL_CHECKS["$app_name"]=true
                elif [ $days_left -gt 0 ]; then
                    log_warning "  ⚠ Certificate expires soon ($days_left days remaining)"
                    SSL_CHECKS["$app_name"]=true
                else
                    log_error "  ✗ Certificate expired"
                    SSL_CHECKS["$app_name"]=false
                fi
            else
                log_success "  ✓ Certificate files exist"
                SSL_CHECKS["$app_name"]=true
            fi
        else
            log_error "  ✗ Certificate not found at $ssl_cert_path"
            SSL_CHECKS["$app_name"]=false

            if command -v certbot >/dev/null 2>&1; then
                log_info "  You can create it with:"
                if [ -n "${DOMAIN_INTERNAL:-}" ]; then
                    log_info "    sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN -d $DOMAIN_INTERNAL"
                else
                    log_info "    sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN"
                fi
            fi
        fi
    done

    # Check if any SSL validation failed
    ssl_failures=false
    for app_name in "${APPS[@]}"; do
        if [ "${SSL_CHECKS[$app_name]}" = false ]; then
            ssl_failures=true
            break
        fi
    done

    if [ "$ssl_failures" = true ] && [ "$FORCE" = false ]; then
        log_error "SSL validation failed. Use --force to continue anyway"
        exit 1
    fi

    log_success "SSL certificate validation completed"
else
    log_warning "Skipping SSL certificate validation"
fi

################################################################################
# STEP 8: TEST NGINX CONFIGURATION
################################################################################

log_step "Step 8: Testing Nginx Configuration"

if [ "$DRY_RUN" = false ]; then
    # First, enable all the new configs
    for app_name in "${APPS[@]}"; do
        sudo ln -sf "/etc/nginx/sites-available/$app_name" "/etc/nginx/sites-enabled/$app_name"
        log_info "Enabled: $app_name"
    done

    # Test nginx configuration
    log_info "Running nginx configuration test..."
    if sudo nginx -t 2>&1; then
        log_success "Nginx configuration test passed!"
    else
        log_error "Nginx configuration test failed!"
        log_error "Restoring backup..."

        # Restore from backup
        sudo rm -rf /etc/nginx/sites-available/*
        sudo rm -rf /etc/nginx/sites-enabled/*
        sudo cp -r "$BACKUP_DIR/sites-available/"* /etc/nginx/sites-available/

        # Recreate symlinks (this is a simplified version)
        log_warning "Please manually recreate symlinks from backup"
        exit 1
    fi
else
    log_info "Would test nginx configuration"
fi

################################################################################
# STEP 9: RELOAD NGINX
################################################################################

log_step "Step 9: Reloading Nginx"

if [ "$DRY_RUN" = false ]; then
    sudo systemctl reload nginx

    if sudo systemctl is-active --quiet nginx; then
        log_success "Nginx reloaded successfully!"
    else
        log_error "Nginx failed to reload!"
        log_error "Check status with: sudo systemctl status nginx"
        exit 1
    fi
else
    log_info "Would reload nginx"
fi

################################################################################
# STEP 10: VERIFICATION
################################################################################

log_step "Step 10: Final Verification"

if [ "$DRY_RUN" = false ]; then
    log_info "Verifying enabled sites..."

    for app_name in "${APPS[@]}"; do
        if [ -L "/etc/nginx/sites-enabled/$app_name" ]; then
            log_success "  ✓ $app_name is enabled"
        else
            log_error "  ✗ $app_name is NOT enabled"
        fi
    done

    log_info ""
    log_info "Testing connectivity..."

    for app_name in "${APPS[@]}"; do
        config_file="${APP_CONFIGS[$app_name]}"
        source "$config_file"

        log_info "Testing $DOMAIN..."

        # Test HTTP (should redirect to HTTPS)
        if command -v curl >/dev/null 2>&1; then
            http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" || echo "failed")
            if [ "$http_status" = "301" ] || [ "$http_status" = "302" ]; then
                log_success "  ✓ HTTP redirects to HTTPS ($http_status)"
            else
                log_warning "  HTTP status: $http_status"
            fi
        fi
    done

    log_success "Verification completed"
fi

################################################################################
# SUMMARY
################################################################################

echo ""
log_step "Rebuild Complete!"

cat << EOF

${GREEN}╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║                  REBUILD SUCCESSFUL                       ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝${NC}

${BLUE}Applications Configured:${NC}
EOF

for app_name in "${APPS[@]}"; do
    config_file="${APP_CONFIGS[$app_name]}"
    source "$config_file"
    echo "  • $app_name → $DOMAIN"
done

if [ "$DRY_RUN" = false ]; then
    cat << EOF

${BLUE}Backup Location:${NC}
  $BACKUP_DIR

${BLUE}Next Steps:${NC}
  1. Test your domains in a web browser
  2. Check nginx logs: sudo tail -f /var/log/nginx/error.log
  3. Monitor container logs: docker logs <container-name>

${YELLOW}If you encounter issues:${NC}
  • Restore from backup: sudo cp -r $BACKUP_DIR/sites-available/* /etc/nginx/sites-available/
  • Check nginx status: sudo systemctl status nginx
  • View full logs: sudo journalctl -u nginx -n 100
EOF
else
    cat << EOF

${YELLOW}This was a DRY RUN - no changes were made.${NC}
Run without --dry-run to apply changes.
EOF
fi

echo ""
