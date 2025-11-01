#!/bin/bash
set -euo pipefail

# CDN Deployment Script
# Deploys the nginx-based CDN solution for Active Storage files
#
# Usage:
#   CDN_DOMAIN=cdn.yourdomain.com ./deploy-cdn.sh
#   Or set CDN_DOMAIN in app config.sh and it will be used automatically

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Use CDN_DOMAIN from environment or default to cdn.webet.pl
CDN_DOMAIN="${CDN_DOMAIN:-cdn.webet.pl}"

echo "=========================================="
echo "CDN Deployment Script"
echo "Domain: ${CDN_DOMAIN}"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo "  $1"
}

# Check if we're on local machine
if [ ! -f "${DEVOPS_DIR}/common/nginx/cdn.conf" ]; then
    print_error "CDN nginx config not found at ${DEVOPS_DIR}/common/nginx/cdn.conf"
    exit 1
fi

print_success "Found CDN nginx configuration"

# Check SSH connection
echo ""
echo "Step 1: Checking SSH connection to server..."
if ssh hetzner-andrzej "echo 'Connection successful'" &> /dev/null; then
    print_success "SSH connection to hetzner-andrzej is working"
else
    print_error "Cannot connect to hetzner-andrzej via SSH"
    print_info "Please check your SSH configuration"
    exit 1
fi

# Copy nginx config to server
echo ""
echo "Step 2: Copying nginx configuration to server..."
scp "${DEVOPS_DIR}/common/nginx/cdn.conf" hetzner-andrzej:~/DevOps/common/nginx/cdn.conf
print_success "Nginx configuration copied to server"

# Deploy on server
echo ""
echo "Step 3: Deploying nginx configuration on server..."
ssh hetzner-andrzej << 'ENDSSH'
set -e

# Copy to nginx sites-available
sudo cp ~/DevOps/common/nginx/cdn.conf /etc/nginx/sites-available/cdn.conf
echo "✓ Copied to /etc/nginx/sites-available/cdn.conf"

# Create symbolic link if it doesn't exist
if [ ! -L /etc/nginx/sites-enabled/cdn.conf ]; then
    sudo ln -s /etc/nginx/sites-available/cdn.conf /etc/nginx/sites-enabled/cdn.conf
    echo "✓ Created symlink in sites-enabled"
else
    echo "✓ Symlink already exists in sites-enabled"
fi

# Test nginx configuration
echo "✓ Testing nginx configuration..."
sudo nginx -t

ENDSSH

print_success "Nginx configuration deployed"

# Check SSL certificate
echo ""
echo "Step 4: Checking SSL certificate..."
if ssh hetzner-andrzej "sudo test -f /etc/letsencrypt/live/${CDN_DOMAIN}/fullchain.pem"; then
    print_success "SSL certificate exists for ${CDN_DOMAIN}"
else
    print_warning "SSL certificate not found for ${CDN_DOMAIN}"
    print_info "You need to obtain an SSL certificate:"
    print_info "  ssh hetzner-andrzej"
    print_info "  sudo certbot certonly --nginx -d ${CDN_DOMAIN}"
    echo ""
    read -p "Do you want to obtain the certificate now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ssh hetzner-andrzej "sudo certbot certonly --nginx -d ${CDN_DOMAIN}"
        print_success "SSL certificate obtained"
    else
        print_warning "Skipping SSL certificate - you'll need to obtain it manually"
        print_info "The nginx configuration won't work without SSL certificate"
        exit 1
    fi
fi

# Reload nginx
echo ""
echo "Step 5: Reloading nginx..."
ssh hetzner-andrzej "sudo systemctl reload nginx"
print_success "Nginx reloaded"

# Check storage directory
echo ""
echo "Step 6: Checking storage directory..."
ssh hetzner-andrzej << 'ENDSSH'
set -e

if [ ! -d /var/storage/brokik-api/active_storage ]; then
    echo "⚠ Storage directory doesn't exist, creating it..."
    sudo mkdir -p /var/storage/brokik-api/active_storage
    sudo chown -R andrzej:andrzej /var/storage/brokik-api
    echo "✓ Storage directory created"
else
    echo "✓ Storage directory exists"
fi

# Show storage info
echo "Storage directory info:"
ls -lhd /var/storage/brokik-api/active_storage

ENDSSH

print_success "Storage directory ready"

# Test CDN health endpoint
echo ""
echo "Step 7: Testing CDN health endpoint..."
if curl -sf "https://${CDN_DOMAIN}/health" > /dev/null; then
    print_success "CDN health check passed"
    print_info "URL: https://${CDN_DOMAIN}/health"
else
    print_error "CDN health check failed"
    print_info "Check nginx error logs: ssh hetzner-andrzej 'sudo tail -f /var/log/nginx/cdn-error.log'"
    exit 1
fi

# Summary
echo ""
echo "=========================================="
echo "CDN Deployment Complete!"
echo "=========================================="
echo ""
print_success "Nginx CDN is deployed and running"
print_info "Domain: https://${CDN_DOMAIN}"
print_info "Health: https://${CDN_DOMAIN}/health"
echo ""
echo "Next steps:"
echo "1. Update brokik-api environment variables:"
echo "   CDN_HOST=https://${CDN_DOMAIN}"
echo "   APP_NAME=brokik-api"
echo ""
echo "2. Restart brokik-api to apply changes"
echo ""
echo "3. Deploy updated brokik-api code (Active Storage initializer)"
echo ""
echo "4. Deploy updated brokik-web code (next.config.js)"
echo ""
echo "5. Test with: curl https://${CDN_DOMAIN}/brokik-api/blobs/{blob-key}"
echo ""
print_info "See docs/cdn-setup.md for detailed documentation"
echo ""
