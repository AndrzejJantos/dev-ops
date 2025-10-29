#!/bin/bash

# ==============================================================================
# REDIS UPDATE SCRIPT
# ==============================================================================
# Updates Redis to the latest version from official Redis repository
#
# Usage:
#   sudo ./update-redis.sh              # Interactive update
#   sudo ./update-redis.sh --yes        # Auto-confirm
#
# This script:
#   1. Adds Redis official repository if not present
#   2. Updates to latest Redis version
#   3. Backs up and deploys clean configuration
#   4. Restarts Redis safely
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(dirname "$SCRIPT_DIR")"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)"
    exit 1
fi

# Parse arguments
AUTO_CONFIRM=false
if [ "$1" = "--yes" ] || [ "$1" = "-y" ]; then
    AUTO_CONFIRM=true
fi

# Helper functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

ask_yes_no() {
    if [ "$AUTO_CONFIRM" = true ]; then
        return 0
    fi

    local question="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    echo -n "$question $prompt "
    read -r response

    if [ -z "$response" ]; then
        response="$default"
    fi

    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

echo ""
echo "=============================================================================="
echo "  Redis Update to Latest Version"
echo "=============================================================================="
echo ""

# Check if Redis is installed
if ! command -v redis-server &> /dev/null; then
    print_error "Redis is not installed. Use ubuntu-init-setup.sh to install it."
    exit 1
fi

# Show current version
CURRENT_VERSION=$(redis-server --version | grep -oP 'v=\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
print_info "Current Redis version: $CURRENT_VERSION"

# Check if Redis repository is configured
if [ ! -f /etc/apt/sources.list.d/redis.list ]; then
    print_warning "Redis official repository not configured"

    if ! ask_yes_no "Add Redis official repository?" "y"; then
        print_info "Update cancelled"
        exit 0
    fi

    print_info "Adding Redis official repository..."

    # Install prerequisites
    apt-get install -y -qq lsb-release curl gpg

    # Add Redis GPG key
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg

    # Add Redis repository
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list

    print_info "Redis repository added"
fi

# Update package list
print_info "Updating package list..."
apt-get update -qq

# Check available version
AVAILABLE_VERSION=$(apt-cache policy redis | grep Candidate | awk '{print $2}' | cut -d: -f2 | cut -d- -f1)
print_info "Available Redis version: $AVAILABLE_VERSION"

if [ "$CURRENT_VERSION" = "$AVAILABLE_VERSION" ]; then
    print_info "Redis is already at the latest version"

    if ! ask_yes_no "Reinstall Redis $AVAILABLE_VERSION?" "n"; then
        print_info "Update cancelled"
        exit 0
    fi
fi

# Confirm update
if ! ask_yes_no "Update Redis from $CURRENT_VERSION to $AVAILABLE_VERSION?" "y"; then
    print_info "Update cancelled"
    exit 0
fi

# Stop Redis
print_info "Stopping Redis..."
systemctl stop redis-server || true

# Backup current configuration
print_info "Backing up Redis configuration..."
REDIS_CONF="/etc/redis/redis.conf"
BACKUP_FILE="${REDIS_CONF}.backup-$(date +%Y%m%d-%H%M%S)"
if [ -f "$REDIS_CONF" ]; then
    cp "$REDIS_CONF" "$BACKUP_FILE"
    print_info "Backed up to: $BACKUP_FILE"
fi

# Backup data
print_info "Backing up Redis data..."
if [ -d /var/lib/redis ]; then
    tar -czf "/var/lib/redis-backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C /var/lib redis 2>/dev/null || true
fi

# Upgrade Redis
print_info "Upgrading Redis..."
if apt-get install -y -qq redis; then
    print_info "Redis upgraded successfully"
else
    print_error "Failed to upgrade Redis"
    exit 1
fi

# Deploy clean configuration from template
TEMPLATE_CONF="${DEVOPS_DIR}/common/templates/redis.conf"

if [ -f "$TEMPLATE_CONF" ]; then
    print_info "Deploying clean configuration from template..."
    cp "$TEMPLATE_CONF" "$REDIS_CONF"
    chown redis:redis "$REDIS_CONF"
    chmod 640 "$REDIS_CONF"

    # Test configuration
    if redis-server "$REDIS_CONF" --test-memory 1 2>&1 | grep -q "Configuration passed"; then
        print_info "Configuration syntax is valid"
    else
        print_warning "Configuration test failed"
        print_warning "Restoring backup configuration..."
        cp "$BACKUP_FILE" "$REDIS_CONF"
    fi
else
    print_warning "Redis config template not found: $TEMPLATE_CONF"
    print_warning "Using existing configuration"
fi

# Start Redis
print_info "Starting Redis..."
systemctl enable redis-server &>/dev/null
systemctl start redis-server

# Wait for Redis to start
sleep 3

# Verify Redis is running
if redis-cli ping > /dev/null 2>&1; then
    NEW_VERSION=$(redis-server --version | grep -oP 'v=\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    print_info "✅ Redis updated successfully!"
    print_info "   Previous version: $CURRENT_VERSION"
    print_info "   Current version:  $NEW_VERSION"

    # Show configuration summary
    echo ""
    print_info "Configuration summary:"
    echo "  AOF Persistence: $(redis-cli CONFIG GET appendonly | tail -1)"
    echo "  Max Memory: $(redis-cli CONFIG GET maxmemory | tail -1 | numfmt --to=iec 2>/dev/null || redis-cli CONFIG GET maxmemory | tail -1)"
    echo "  Eviction Policy: $(redis-cli CONFIG GET maxmemory-policy | tail -1)"

    echo ""
    print_info "Backup locations:"
    echo "  Config: $BACKUP_FILE"
    ls -lh /var/lib/redis-backup-*.tar.gz 2>/dev/null | tail -1 | awk '{print "  Data:  ", $9}' || echo "  Data:   No backup created"
else
    print_error "Redis failed to start!"
    print_warning "Check logs: sudo journalctl -xeu redis-server.service"
    print_warning "Restore backup: sudo cp $BACKUP_FILE $REDIS_CONF && sudo systemctl start redis-server"
    exit 1
fi

echo ""
echo "=============================================================================="
echo "  Update Complete!"
echo "=============================================================================="
echo ""
