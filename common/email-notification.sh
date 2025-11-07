#!/bin/bash

# Email Notification Orchestrator for Deployment Events
# Location: /home/andrzej/DevOps/common/email-notification.sh
#
# This script orchestrates email notifications by combining:
#   - Email templates (from email-templates.sh)
#   - SendGrid API sender (from sendgrid-api.sh)
#
# Simple, clean architecture:
#   Part 1: SendGrid API sending logic (sendgrid-api.sh)
#   Part 2: Email content templates (email-templates.sh)
#   Part 3: Public API that orchestrates the above (THIS FILE)
#
# Usage:
#   source email-notification.sh
#   send_deployment_success_email <app_name> <deployment_details>
#   send_deployment_failure_email <app_name> <error_details>

set -e

# ==============================================================================
# EMAIL CONFIGURATION
# ==============================================================================

# Email addresses
EMAIL_FROM="${DEPLOYMENT_EMAIL_FROM:-biuro@webet.pl}"
EMAIL_TO="${DEPLOYMENT_EMAIL_TO:-andrzej@webet.pl}"

# SendGrid API Key (must be set in environment or email-config.sh)
# SENDGRID_API_KEY should be set externally

# ==============================================================================
# LOAD MODULES
# ==============================================================================

# Get the directory where this script is located
SCRIPT_DIR_EMAIL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load SendGrid API sender
if [ -f "$SCRIPT_DIR_EMAIL/sendgrid-api.sh" ]; then
    source "$SCRIPT_DIR_EMAIL/sendgrid-api.sh"
else
    log_error "sendgrid-api.sh not found at $SCRIPT_DIR_EMAIL/sendgrid-api.sh"
    return 1
fi

# Load email templates
if [ -f "$SCRIPT_DIR_EMAIL/email-templates.sh" ]; then
    source "$SCRIPT_DIR_EMAIL/email-templates.sh"
else
    log_error "email-templates.sh not found at $SCRIPT_DIR_EMAIL/email-templates.sh"
    return 1
fi

# ==============================================================================
# PUBLIC API FUNCTIONS
# ==============================================================================

# Send deployment success email
# Arguments:
#   $1 - app_name (e.g., "cheaperfordrug-api")
#   $2 - app_display_name (e.g., "CheaperForDrug API")
#   $3 - domain (e.g., "api.cheaperfordrug.com")
#   $4 - scale (number of containers)
#   $5 - image_tag (Docker image tag)
#   $6 - migrations_run (true/false/N/A) [optional, default: N/A]
#   $7 - git_commit (short hash) [optional, default: N/A]
# Returns:
#   0 on success, 1 on failure
send_deployment_success_email() {
    local app_name="$1"
    local app_display_name="$2"
    local domain="$3"
    local scale="$4"
    local image_tag="$5"
    local migrations_run="${6:-N/A}"
    local git_commit="${7:-N/A}"

    # Check if email is enabled
    if [ "${DEPLOYMENT_EMAIL_ENABLED:-true}" != "true" ]; then
        log_info "Email notifications disabled (DEPLOYMENT_EMAIL_ENABLED=false)"
        return 0
    fi

    # Check SendGrid requirements
    if ! check_sendgrid_requirements; then
        log_warning "SendGrid requirements not met, skipping notification"
        return 1
    fi

    # Generate email content using template
    generate_deployment_success_email \
        "$app_name" \
        "$app_display_name" \
        "$domain" \
        "$scale" \
        "$image_tag" \
        "$migrations_run" \
        "$git_commit"

    # Send email via SendGrid API
    send_email_via_sendgrid \
        "$EMAIL_FROM" \
        "$EMAIL_TO" \
        "$EMAIL_SUBJECT" \
        "$EMAIL_TEXT_BODY" \
        "$EMAIL_HTML_BODY"

    return $?
}

# Send deployment failure email
# Arguments:
#   $1 - app_name (e.g., "cheaperfordrug-api")
#   $2 - app_display_name (e.g., "CheaperForDrug API")
#   $3 - error_message (error details)
# Returns:
#   0 on success, 1 on failure
send_deployment_failure_email() {
    local app_name="$1"
    local app_display_name="$2"
    local error_message="$3"

    # Check if email is enabled
    if [ "${DEPLOYMENT_EMAIL_ENABLED:-true}" != "true" ]; then
        log_info "Email notifications disabled (DEPLOYMENT_EMAIL_ENABLED=false)"
        return 0
    fi

    # Check SendGrid requirements
    if ! check_sendgrid_requirements; then
        log_warning "SendGrid requirements not met, skipping notification"
        return 1
    fi

    # Generate email content using template
    generate_deployment_failure_email \
        "$app_name" \
        "$app_display_name" \
        "$error_message"

    # Send email via SendGrid API
    send_email_via_sendgrid \
        "$EMAIL_FROM" \
        "$EMAIL_TO" \
        "$EMAIL_SUBJECT" \
        "$EMAIL_TEXT_BODY" \
        "$EMAIL_HTML_BODY"

    return $?
}

# ==============================================================================
# TEST FUNCTION
# ==============================================================================

# Test email notification system
test_email_notification() {
    log_info "Testing email notification system..."
    log_info "From: $EMAIL_FROM"
    log_info "To: $EMAIL_TO"

    # Check SendGrid requirements
    if ! check_sendgrid_requirements; then
        log_error "SendGrid requirements check failed"
        return 1
    fi

    # Build test email content
    local subject="Test Email from CheaperForDrug Deployment System"
    local text_body="This is a test email to verify that the SendGrid email notification system is working correctly.

Configuration:
- From: $EMAIL_FROM
- To: $EMAIL_TO
- Server: $(hostname)
- Date: $(date)

If you received this email, the notification system is configured correctly."

    local html_body="<html>
<head>
    <meta charset=\"UTF-8\">
    <style>
        body { font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #667eea; color: white; padding: 20px; border-radius: 8px; }
        .content { background: #f8f9fa; padding: 20px; margin-top: 20px; border-radius: 8px; }
        .info { background: white; padding: 15px; border-left: 4px solid #667eea; margin: 10px 0; }
    </style>
</head>
<body>
    <div class=\"header\">
        <h2>Test Email - CheaperForDrug Deployment System</h2>
    </div>
    <div class=\"content\">
        <p>This is a test email to verify that the SendGrid email notification system is working correctly.</p>
        <div class=\"info\">
            <strong>Configuration:</strong><br>
            From: $EMAIL_FROM<br>
            To: $EMAIL_TO<br>
            Server: $(hostname)<br>
            Date: $(date)
        </div>
        <p>If you received this email, the notification system is configured correctly.</p>
    </div>
</body>
</html>"

    # Send test email
    send_email_via_sendgrid \
        "$EMAIL_FROM" \
        "$EMAIL_TO" \
        "$subject" \
        "$text_body" \
        "$html_body"

    return $?
}

# ==============================================================================
# ADDING NEW EMAIL TYPES
# ==============================================================================

# To add a new email notification type:
#
# 1. Add a template function in email-templates.sh:
#    generate_new_notification_email() { ... }
#
# 2. Add a public API function here:
#    send_new_notification_email() {
#        generate_new_notification_email "$@"
#        send_email_via_sendgrid "$EMAIL_FROM" "$EMAIL_TO" "$EMAIL_SUBJECT" "$EMAIL_TEXT_BODY" "$EMAIL_HTML_BODY"
#    }
#
# That's it! Simple and easy to extend.
