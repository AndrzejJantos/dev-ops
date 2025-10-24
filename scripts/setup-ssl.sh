#!/bin/bash

# SSL/HTTPS setup script using certbot
# Usage: ./setup-ssl.sh <app-name>

set -e

APP_NAME="$1"

if [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <app-name>"
    echo ""
    echo "Available apps:"
    ls -1 /home/andrzej/DevOps/apps/ 2>/dev/null | grep -v "_examples" || echo "  (none)"
    echo ""
    echo "Example:"
    echo "  $0 cheaperfordrug-landing"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(dirname "$SCRIPT_DIR")"
APP_CONFIG_DIR="${DEVOPS_DIR}/apps/${APP_NAME}"

# Load utilities
source "${DEVOPS_DIR}/common/utils.sh"

# Check if app exists
if [ ! -d "$APP_CONFIG_DIR" ]; then
    log_error "Application '${APP_NAME}' not found"
    echo "Available apps:"
    ls -1 "${DEVOPS_DIR}/apps/" | grep -v "_examples"
    exit 1
fi

# Load app configuration
if [ ! -f "${APP_CONFIG_DIR}/config.sh" ]; then
    log_error "Configuration file not found: ${APP_CONFIG_DIR}/config.sh"
    exit 1
fi

source "${APP_CONFIG_DIR}/config.sh"

log_info "Setting up SSL for ${APP_DISPLAY_NAME}"
echo ""

# Check if we're root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    log_info "Run: sudo $0 $APP_NAME"
    exit 1
fi

# Check if certbot is installed
if ! command_exists certbot; then
    log_info "Installing certbot..."
    apt-get update -qq
    apt-get install -y certbot python3-certbot-nginx
    log_success "Certbot installed"
else
    log_success "Certbot already installed"
fi

# Validate domain
if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "localhost" ]; then
    log_error "No valid domain configured in config.sh"
    log_info "Domain: ${DOMAIN}"
    exit 1
fi

# Get email from config
EMAIL="${NOTIFICATION_EMAIL:-root@localhost}"

log_info "Domain: ${DOMAIN}"
log_info "Email: ${EMAIL}"
echo ""

# Check if Nginx is configured
NGINX_CONF="/etc/nginx/sites-enabled/${APP_NAME}"
if [ ! -f "$NGINX_CONF" ]; then
    log_error "Nginx configuration not found: ${NGINX_CONF}"
    log_info "Run app setup first: ${APP_CONFIG_DIR}/setup.sh"
    exit 1
fi

# Check if domain changed in Nginx config
CURRENT_DOMAIN=$(grep -oP 'server_name \K[^;]+' "$NGINX_CONF" | tr -d ' ')
if [ "$CURRENT_DOMAIN" != "$DOMAIN" ]; then
    log_warning "Domain changed detected!"
    log_info "Current Nginx domain: ${CURRENT_DOMAIN}"
    log_info "New domain in config: ${DOMAIN}"
    echo ""
    log_info "Updating Nginx configuration..."

    # Update Nginx config with new domain
    sed -i "s/server_name ${CURRENT_DOMAIN};/server_name ${DOMAIN};/g" "$NGINX_CONF"

    # Test Nginx configuration
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        log_success "Nginx configuration updated"
    else
        log_error "Nginx configuration test failed"
        # Revert changes
        sed -i "s/server_name ${DOMAIN};/server_name ${CURRENT_DOMAIN};/g" "$NGINX_CONF"
        exit 1
    fi

    # If old domain had certificate, we'll need to get new one
    if [ -d "/etc/letsencrypt/live/${CURRENT_DOMAIN}" ]; then
        log_info "Old SSL certificate exists for: ${CURRENT_DOMAIN}"
        log_info "Will obtain new certificate for: ${DOMAIN}"
    fi
fi

# Test DNS
log_info "Testing DNS resolution..."
if ! host "$DOMAIN" > /dev/null 2>&1; then
    log_warning "DNS lookup failed for ${DOMAIN}"
    log_info "Make sure DNS is configured:"
    echo "  1. Add A record: ${DOMAIN} → Your server IP"
    echo "  2. Wait for DNS propagation (5-60 minutes)"
    echo "  3. Test: host ${DOMAIN}"
    echo ""
    read -p "DNS configured? Continue anyway? [y/N]: " continue_anyway
    if [[ ! $continue_anyway =~ ^[Yy]$ ]]; then
        log_info "Exiting. Configure DNS first."
        exit 0
    fi
else
    log_success "DNS resolves correctly"
fi

# Check if certificate already exists
if [ -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
    log_warning "Certificate already exists for ${DOMAIN}"
    read -p "Renew certificate? [y/N]: " renew_cert
    if [[ $renew_cert =~ ^[Yy]$ ]]; then
        ACTION="renew"
    else
        log_info "Skipping certificate setup"
        exit 0
    fi
else
    ACTION="obtain"
fi

echo ""
log_info "Obtaining SSL certificate from Let's Encrypt..."
echo ""

# Run certbot
if [ "$ACTION" = "renew" ]; then
    certbot --nginx -d "$DOMAIN" \
        --force-renewal \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect
else
    certbot --nginx -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect
fi

if [ $? -eq 0 ]; then
    log_success "SSL certificate obtained successfully!"
    echo ""
    log_info "Certificate details:"
    certbot certificates -d "$DOMAIN"
    echo ""
    log_info "Your site is now available at:"
    echo "  https://${DOMAIN}"
    echo ""
else
    log_error "Failed to obtain SSL certificate"
    log_info "Common issues:"
    echo "  1. DNS not configured or not propagated"
    echo "  2. Port 80/443 not accessible"
    echo "  3. Domain already has certificate"
    echo ""
    log_info "Check certbot logs:"
    echo "  sudo tail -f /var/log/letsencrypt/letsencrypt.log"
    exit 1
fi

# Test auto-renewal
log_info "Testing certificate auto-renewal..."
certbot renew --dry-run

if [ $? -eq 0 ]; then
    log_success "Auto-renewal test passed"
    log_info "Certificates will auto-renew before expiry"
else
    log_warning "Auto-renewal test failed"
    log_info "Manual renewal: sudo certbot renew"
fi

echo ""
log_success "SSL setup completed!"
echo ""

# Send notification
if [ -n "$MAILGUN_API_KEY" ] && [ -n "$MAILGUN_DOMAIN" ]; then
    send_mailgun_notification \
        "${APP_DISPLAY_NAME} - SSL Certificate Configured" \
        "SSL/HTTPS has been configured for ${APP_NAME}

Domain: ${DOMAIN}
Certificate: Let's Encrypt
Auto-renewal: Enabled

Your application is now accessible at:
https://${DOMAIN}

Certificate valid for: 90 days
Auto-renewal: 30 days before expiry

Configured on: $(date)
Server: $(hostname)" \
        "$MAILGUN_API_KEY" \
        "$MAILGUN_DOMAIN" \
        "$NOTIFICATION_EMAIL"
fi

log_info "Next steps:"
echo "  1. Test your site: https://${DOMAIN}"
echo "  2. Check SSL rating: https://www.ssllabs.com/ssltest/analyze.html?d=${DOMAIN}"
echo "  3. Monitor renewal: sudo certbot certificates"
