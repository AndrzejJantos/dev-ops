#!/bin/bash

# Setup Local Scraper Access
# This script installs nginx configuration for local scraper communication
# Allows scraper to connect via http://api-scraper.localtest.me:4100

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_CONFIG="$SCRIPT_DIR/nginx-local-scraper.conf"
NGINX_AVAILABLE="/etc/nginx/sites-available/api-scraper-local"
NGINX_ENABLED="/etc/nginx/sites-enabled/api-scraper-local"

echo "=========================================="
echo "Local Scraper Access Setup"
echo "=========================================="
echo ""

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    echo "Usage: sudo $0"
    exit 1
fi

# Check if config file exists
if [ ! -f "$NGINX_CONFIG" ]; then
    echo "Error: nginx-local-scraper.conf not found"
    echo "Expected location: $NGINX_CONFIG"
    exit 1
fi

echo "Step 1: Installing nginx configuration..."
cp "$NGINX_CONFIG" "$NGINX_AVAILABLE"
echo "✓ Copied to $NGINX_AVAILABLE"

echo ""
echo "Step 2: Enabling configuration..."
if [ -L "$NGINX_ENABLED" ]; then
    echo "  Configuration already enabled, updating symlink..."
    rm "$NGINX_ENABLED"
fi
ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"
echo "✓ Enabled in sites-enabled"

echo ""
echo "Step 3: Testing nginx configuration..."
nginx -t

echo ""
echo "Step 4: Reloading nginx..."
systemctl reload nginx
echo "✓ Nginx reloaded"

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "The scraper can now connect via:"
echo "  http://api-scraper.localtest.me:4100"
echo ""
echo "Test the connection:"
echo "  curl http://api-scraper.localtest.me:4100/up"
echo "  curl http://localhost:4100/up"
echo ""
echo "View logs:"
echo "  sudo tail -f /var/log/nginx/api-scraper-local-access.log"
echo "  sudo tail -f /var/log/nginx/api-scraper-local-error.log"
echo ""
