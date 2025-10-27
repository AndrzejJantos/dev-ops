#!/bin/bash

# Upgrade Ruby Version Script
# This script upgrades Ruby to version 3.4.4 using rbenv

set -e

# Configuration
TARGET_RUBY_VERSION="3.4.4"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "========================================================================"
echo "Ruby Upgrade Script"
echo "Target Version: ${TARGET_RUBY_VERSION}"
echo "========================================================================"
echo ""

# Check if rbenv is installed
if ! command -v rbenv &> /dev/null; then
    log_error "rbenv is not installed. Please run ubuntu-init-setup.sh first."
    exit 1
fi

# Check current Ruby version
CURRENT_VERSION=$(ruby -v | grep -oP '\d+\.\d+\.\d+' | head -1 2>/dev/null || echo "none")
log_info "Current Ruby version: ${CURRENT_VERSION}"

if [ "$CURRENT_VERSION" = "$TARGET_RUBY_VERSION" ]; then
    log_success "Ruby ${TARGET_RUBY_VERSION} is already installed!"
    exit 0
fi

# Install Ruby 3.4.4
log_info "Installing Ruby ${TARGET_RUBY_VERSION}..."
log_info "This may take several minutes..."

# Update rbenv and ruby-build
cd ~/.rbenv/plugins/ruby-build && git pull

# Install Ruby
rbenv install -s ${TARGET_RUBY_VERSION}

# Set as global default
rbenv global ${TARGET_RUBY_VERSION}

# Verify installation
log_info "Verifying installation..."
source ~/.bashrc
INSTALLED_VERSION=$(ruby -v | grep -oP '\d+\.\d+\.\d+' | head -1)

if [ "$INSTALLED_VERSION" = "$TARGET_RUBY_VERSION" ]; then
    log_success "Ruby ${TARGET_RUBY_VERSION} installed successfully!"

    # Install bundler
    log_info "Installing bundler..."
    gem install bundler

    log_success "Ruby upgrade complete!"
    echo ""
    echo "Ruby version: $(ruby -v)"
    echo "Bundler version: $(bundle -v)"
    echo ""
    log_info "You may need to restart your shell or run: source ~/.bashrc"
else
    log_error "Ruby installation verification failed"
    log_error "Expected: ${TARGET_RUBY_VERSION}, Got: ${INSTALLED_VERSION}"
    exit 1
fi

echo ""
echo "========================================================================"
echo "Next Steps:"
echo "========================================================================"
echo "1. Restart your shell or run: source ~/.bashrc"
echo "2. Verify Ruby version: ruby -v"
echo "3. Redeploy your Rails apps to install gems with correct Ruby version"
echo ""
