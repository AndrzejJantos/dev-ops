#!/bin/bash

# Fix Domain Conflicts and Setup SSL for CheaperForDrug Web
# This script resolves nginx conflicts and sets up SSL certificates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$DEVOPS_DIR/common/utils.sh"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "=========================================================================="
echo "  Domain Conflict Resolver & SSL Setup"
echo "  Application: ${APP_DISPLAY_NAME}"
echo "  Domain: ${DOMAIN}"
echo "=========================================================================="
echo ""

# Step 1: Check for domain conflicts
log_info "Step 1: Checking for domain conflicts in nginx configs..."

conflicting_configs=()
for config in /etc/nginx/sites-enabled/*; do
    if [ -f "$config" ] && [ "$config" != "/etc/nginx/sites-enabled/${APP_NAME}" ]; then
        if grep -q "server_name.*${DOMAIN}" "$config" 2>/dev/null; then
            config_name=$(basename "$config")
            conflicting_configs+=("$config_name")
            log_warning "Found conflict in: $config_name"
        fi
    fi
done

if [ ${#conflicting_configs[@]} -eq 0 ]; then
    log_success "No domain conflicts found"
else
    log_error "Found ${#conflicting_configs[@]} conflicting nginx configuration(s)"
    echo ""
    echo "The following configs are claiming ${DOMAIN}:"
    for config in "${conflicting_configs[@]}"; do
        echo "  - $config"
    done
    echo ""
    echo "Conflicts found in these files:"
    for config in "${conflicting_configs[@]}"; do
        echo ""
        echo "File: /etc/nginx/sites-available/$config"
        grep -n "server_name.*${DOMAIN}" "/etc/nginx/sites-available/$config" 2>/dev/null | sed 's/^/  Line /'
    done
    echo ""

    read -p "Do you want to automatically remove ${DOMAIN} from these configs? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for config in "${conflicting_configs[@]}"; do
            config_file="/etc/nginx/sites-available/$config"
            backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"

            log_info "Backing up $config to ${backup_file}..."
            sudo cp "$config_file" "$backup_file"

            log_info "Removing ${DOMAIN} from $config..."
            # Remove the domain from server_name lines
            sudo sed -i "s/\s*${DOMAIN}//g" "$config_file"
            sudo sed -i "s/\s*www\.${DOMAIN}//g" "$config_file"

            # Clean up any empty or malformed server_name lines
            sudo sed -i '/server_name\s*;/d' "$config_file"

            log_success "Updated $config (backup saved)"
        done

        log_success "All conflicts resolved"
    else
        log_error "Cannot proceed with conflicts present"
        log_info "Please manually edit these files to remove ${DOMAIN}:"
        for config in "${conflicting_configs[@]}"; do
            echo "  sudo nano /etc/nginx/sites-available/$config"
        done
        exit 1
    fi
fi

# Step 2: Test nginx configuration
log_info "Step 2: Testing nginx configuration..."
if sudo nginx -t 2>&1 | grep -q "successful"; then
    log_success "Nginx configuration is valid"
else
    log_error "Nginx configuration test failed"
    sudo nginx -t
    exit 1
fi

# Step 3: Reload nginx
log_info "Step 3: Reloading nginx..."
if sudo systemctl reload nginx; then
    log_success "Nginx reloaded successfully"
else
    log_error "Failed to reload nginx"
    exit 1
fi

# Step 4: Check DNS configuration
log_info "Step 4: Checking DNS configuration..."
server_ip=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org)
domain_ip=$(dig +short "$DOMAIN" A | tail -1)

echo "  Server IP: ${server_ip}"
echo "  Domain IP: ${domain_ip}"

if [ -z "$domain_ip" ]; then
    log_error "DNS not configured for ${DOMAIN}"
    echo ""
    echo "Please configure your DNS with these A records:"
    echo "  ${DOMAIN}     A    ${server_ip}"
    echo "  www.${DOMAIN} A    ${server_ip}"
    echo ""
    echo "After DNS is configured, run this script again."
    exit 1
elif [ "$domain_ip" != "$server_ip" ]; then
    log_warning "DNS mismatch detected!"
    echo ""
    echo "Expected: ${DOMAIN} -> ${server_ip}"
    echo "Current:  ${DOMAIN} -> ${domain_ip}"
    echo ""
    read -p "DNS may still be propagating. Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Waiting for DNS to propagate..."
        exit 0
    fi
else
    log_success "DNS correctly configured: ${DOMAIN} -> ${server_ip}"
fi

# Step 5: Check if SSL certificates already exist
log_info "Step 5: Checking for existing SSL certificates..."
if sudo certbot certificates 2>/dev/null | grep -q "Certificate Name: ${DOMAIN}"; then
    log_success "SSL certificates already exist for ${DOMAIN}"

    # Check if they're expiring soon
    expiry_date=$(sudo certbot certificates 2>/dev/null | grep -A 10 "Certificate Name: ${DOMAIN}" | grep "Expiry Date" | cut -d: -f2- | xargs)
    log_info "Certificate expiry: ${expiry_date}"

    read -p "Do you want to renew/reinstall certificates? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping SSL setup"
        ssl_needed=false
    else
        ssl_needed=true
    fi
else
    log_info "No SSL certificates found for ${DOMAIN}"
    ssl_needed=true
fi

# Step 6: Install certbot if needed
if [ "$ssl_needed" = true ]; then
    if ! command -v certbot >/dev/null 2>&1; then
        log_info "Installing certbot..."
        sudo apt-get update -qq
        sudo apt-get install -y certbot python3-certbot-nginx
        log_success "Certbot installed"
    fi

    # Step 7: Obtain SSL certificates
    log_info "Step 6: Obtaining SSL certificates from Let's Encrypt..."
    echo ""
    echo "This will:"
    echo "  1. Request SSL certificates for ${DOMAIN} and www.${DOMAIN}"
    echo "  2. Automatically configure nginx to use HTTPS"
    echo "  3. Set up automatic certificate renewal"
    echo ""

    # Try to get email from existing certbot registration
    existing_email=$(sudo certbot show_account 2>/dev/null | grep -oP 'Email contact: \K.*' || echo "")

    if [ -n "$existing_email" ]; then
        log_info "Using existing certbot account: ${existing_email}"
        certbot_email_arg="--email ${existing_email}"
    else
        read -p "Enter your email address for Let's Encrypt notifications: " email
        certbot_email_arg="--email ${email} --agree-tos"
    fi

    if sudo certbot --nginx \
        -d "$DOMAIN" \
        -d "www.$DOMAIN" \
        ${certbot_email_arg} \
        --non-interactive \
        --redirect; then
        log_success "SSL certificates obtained and configured successfully!"

        # Enable auto-renewal
        if ! sudo systemctl is-active --quiet certbot.timer; then
            sudo systemctl enable certbot.timer
            sudo systemctl start certbot.timer
            log_success "SSL auto-renewal enabled"
        fi
    else
        log_error "Failed to obtain SSL certificates"
        echo ""
        echo "Common reasons for failure:"
        echo "  1. DNS not pointing to this server"
        echo "  2. Port 80/443 not accessible from internet"
        echo "  3. Firewall blocking connections"
        echo "  4. Rate limit reached (try again later)"
        echo ""
        echo "You can try manually:"
        echo "  sudo certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
        exit 1
    fi
fi

# Step 8: Final verification
log_info "Step 7: Verifying site accessibility..."
echo ""

# Test HTTP redirect
log_info "Testing HTTP (should redirect to HTTPS)..."
http_status=$(curl -s -o /dev/null -w "%{http_code}" http://${DOMAIN}/ 2>/dev/null || echo "000")
if [ "$http_status" = "301" ] || [ "$http_status" = "302" ]; then
    log_success "HTTP redirects to HTTPS (${http_status})"
else
    log_warning "HTTP returned status: ${http_status}"
fi

# Test HTTPS
log_info "Testing HTTPS..."
https_status=$(curl -s -o /dev/null -w "%{http_code}" https://${DOMAIN}/ 2>/dev/null || echo "000")
if [[ "$https_status" =~ ^2[0-9][0-9]$ ]]; then
    log_success "HTTPS working! (${https_status})"
elif [[ "$https_status" =~ ^3[0-9][0-9]$ ]]; then
    log_success "HTTPS working with redirect (${https_status})"
else
    log_error "HTTPS returned status: ${https_status}"
fi

# Test container health
log_info "Testing container directly..."
container_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3030/ 2>/dev/null)
if [[ "$container_status" =~ ^2[0-9][0-9]$ ]]; then
    log_success "Container responding (${container_status})"
else
    log_warning "Container returned status: ${container_status}"
fi

# Final summary
echo ""
echo "=========================================================================="
echo "  Setup Complete!"
echo "=========================================================================="
echo ""
echo "Site Status:"
echo "  Primary URL:  https://${DOMAIN}"
echo "  Alternative:  https://www.${DOMAIN}"
echo ""
echo "Test your site:"
echo "  curl -I https://${DOMAIN}"
echo "  curl -I https://www.${DOMAIN}"
echo ""
echo "View logs:"
echo "  Nginx access: sudo tail -f /var/log/nginx/${APP_NAME}-access.log"
echo "  Nginx errors: sudo tail -f /var/log/nginx/${APP_NAME}-error.log"
echo "  Container:    docker logs ${APP_NAME}_web_1 -f"
echo ""
echo "SSL Certificate Management:"
echo "  Check status:  sudo certbot certificates"
echo "  Renew:         sudo certbot renew"
echo "  Auto-renewal:  sudo systemctl status certbot.timer"
echo ""
echo "=========================================================================="
echo ""
