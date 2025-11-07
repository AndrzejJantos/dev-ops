#!/bin/bash

# Test Email Notification System
# Location: /home/andrzej/DevOps/scripts/test-email-notification.sh
#
# This script tests the email notification system independently
# Run this to verify your SendGrid configuration before actual deployment
#
# Usage:
#   ./test-email-notification.sh

set -e

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

log_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# Load utilities
if [ -f "$DEVOPS_DIR/common/utils.sh" ]; then
    source "$DEVOPS_DIR/common/utils.sh"
fi

# Load email configuration if exists
if [ -f "$DEVOPS_DIR/common/email-config.sh" ]; then
    source "$DEVOPS_DIR/common/email-config.sh"
    log_success "Loaded email configuration from email-config.sh"
else
    log_warning "email-config.sh not found, using default values"
    log_info "You can create email-config.sh to centralize configuration"
fi

# Load email notification module
if [ -f "$DEVOPS_DIR/common/email-notification.sh" ]; then
    source "$DEVOPS_DIR/common/email-notification.sh"
    log_success "Loaded email notification module"
else
    log_error "email-notification.sh not found at $DEVOPS_DIR/common/email-notification.sh"
    exit 1
fi

# Display current configuration
log_header "Current Email Configuration"
echo "Email Enabled:    ${DEPLOYMENT_EMAIL_ENABLED:-true}"
echo "From Address:     ${EMAIL_FROM}"
echo "To Address:       ${EMAIL_TO}"
echo ""

# Check if SendGrid API key is set
if [ -z "${SENDGRID_API_KEY:-}" ]; then
    log_error "SENDGRID_API_KEY is not set!"
    echo ""
    echo "Please set your SendGrid API key using one of these methods:"
    echo ""
    echo "Method 1 - Environment variable:"
    echo "  export SENDGRID_API_KEY=\"SG.xxxxxxxxxxxxxxxxxxxx\""
    echo ""
    echo "Method 2 - In email-config.sh:"
    echo "  Edit $DEVOPS_DIR/common/email-config.sh"
    echo "  Set: export SENDGRID_API_KEY=\"SG.xxxxxxxxxxxxxxxxxxxx\""
    echo ""
    echo "Get your API key from: https://app.sendgrid.com/settings/api_keys"
    echo ""
    exit 1
else
    # Show masked API key
    local key_prefix="${SENDGRID_API_KEY:0:6}"
    local key_suffix="${SENDGRID_API_KEY: -4}"
    log_success "SendGrid API Key: ${key_prefix}...${key_suffix}"
fi

echo ""
read -p "Do you want to proceed with the test? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    log_info "Test cancelled"
    exit 0
fi

# Test 1: Check requirements
log_header "Test 1: Checking Requirements"
if check_sendgrid_requirements; then
    log_success "All requirements met for SendGrid API"
else
    log_error "Requirements check failed"
    exit 1
fi

# Test 2: Send simple test email
log_header "Test 2: Sending Test Email"
if test_email_notification; then
    log_success "Test email sent successfully!"
    echo ""
    log_info "Please check your inbox at: ${EMAIL_TO}"
else
    log_error "Failed to send test email"
    exit 1
fi

# Test 3: Send sample deployment success email
log_header "Test 3: Sending Sample Deployment Success Email"
log_info "This simulates a real deployment success notification..."

if send_deployment_success_email \
    "test-app" \
    "Test Application" \
    "test.example.com" \
    "2" \
    "$(date +%Y%m%d_%H%M%S)" \
    "true" \
    "abc1234"; then
    log_success "Sample deployment success email sent!"
else
    log_error "Failed to send sample deployment success email"
    exit 1
fi

# Test 4: Send sample deployment failure email
log_header "Test 4: Sending Sample Deployment Failure Email"
log_info "This simulates a deployment failure notification..."

if send_deployment_failure_email \
    "test-app" \
    "Test Application" \
    "This is a test failure message. In a real scenario, this would contain the actual error that caused the deployment to fail."; then
    log_success "Sample deployment failure email sent!"
else
    log_error "Failed to send sample deployment failure email"
    exit 1
fi

# Summary
log_header "Email Notification System Test Complete"
log_success "All tests passed successfully!"
echo ""
echo "You should have received the following emails:"
echo "  1. A simple test email"
echo "  2. A sample deployment success notification"
echo "  3. A sample deployment failure notification"
echo ""
echo "If you received all emails, your notification system is configured correctly."
echo "The system is now ready to send notifications during actual deployments."
echo ""
echo "Next steps:"
echo "  - Verify emails arrived in your inbox at: ${EMAIL_TO}"
echo "  - Check SendGrid dashboard for delivery status: https://app.sendgrid.com/activity"
echo "  - If emails are in spam, configure sender authentication in SendGrid"
echo ""
