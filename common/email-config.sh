#!/bin/bash

# Global Email Notification Configuration
# Location: /home/andrzej/DevOps/common/email-config.sh
#
# This file provides OPTIONAL centralized email configuration for all apps.
# If this file exists and is sourced, it will override individual app configs.
#
# Note: Individual apps already have email configuration in their config.sh files.
# Use this file only if you want to centralize and override app-specific settings.
#
# This file is sourced by test-email-notification.sh and can be optionally
# sourced by deployment scripts to override per-app email settings.

# ==============================================================================
# ENABLE/DISABLE EMAIL NOTIFICATIONS
# ==============================================================================
export DEPLOYMENT_EMAIL_ENABLED=true

# ==============================================================================
# EMAIL ADDRESSES
# ==============================================================================
export DEPLOYMENT_EMAIL_FROM="biuro@webet.pl"
export DEPLOYMENT_EMAIL_TO="andrzej@webet.pl"

# ==============================================================================
# SENDGRID API CONFIGURATION
# ==============================================================================
# SendGrid API Key - REQUIRED for sending emails
# Get your API key from: https://app.sendgrid.com/settings/api_keys
#
# IMPORTANT: Keep this key secure!
# - Do not commit this file with the real API key to version control
# - Consider using environment variables instead: export SENDGRID_API_KEY="your-key"
# - Or use a secrets management system for production
#

# Try to load SENDGRID_API_KEY from /etc/environment if not already set
if [ -z "${SENDGRID_API_KEY:-}" ] && [ -f /etc/environment ]; then
    # Source /etc/environment to get the API key
    # Use set +a to avoid exporting all variables
    set -a
    source /etc/environment
    set +a
fi

export SENDGRID_API_KEY="${SENDGRID_API_KEY:-}"

# ==============================================================================
# SETUP INSTRUCTIONS
# ==============================================================================
#
# 1. Get SendGrid API Key:
#    - Sign up at https://sendgrid.com (Free tier: 100 emails/day)
#    - Go to Settings > API Keys > Create API Key
#    - Give it "Mail Send" permission (Full Access)
#    - Copy the API key (you'll only see it once!)
#
# 2. Configure the API key (choose one method):
#
#    Method A - Set in /etc/environment (RECOMMENDED - works for all sessions):
#      sudo sh -c 'echo "SENDGRID_API_KEY=SG.xxxxxxxxxxxxxxxxxxxx" >> /etc/environment'
#      Note: This file will automatically load the key from /etc/environment
#
#    Method B - Set in this file (easier for testing):
#      Uncomment and set the key below (before the auto-load block above)
#      export SENDGRID_API_KEY="SG.xxxxxxxxxxxxxxxxxxxx"
#
#    Method C - Set in ~/.bashrc (only works for interactive sessions):
#      echo 'export SENDGRID_API_KEY="SG.xxxxxxxxxxxxxxxxxxxx"' >> ~/.bashrc
#      Note: Won't work for non-interactive deployments - use Method A instead
#
#    Method D - Set in app's .env file:
#      Add to ~/apps/APP_NAME/.env.production:
#        SENDGRID_API_KEY=SG.xxxxxxxxxxxxxxxxxxxx
#
# 3. Verify sender email:
#    - SendGrid requires sender verification
#    - Go to Settings > Sender Authentication
#    - Add and verify your sender email (biuro@webet.pl)
#    - Or set up domain authentication for better deliverability
#
# 4. Test the configuration:
#    cd /path/to/DevOps
#    ./scripts/test-email-notification.sh
#
# ==============================================================================
# MIGRATION FROM OLD SYSTEM
# ==============================================================================
#
# If you were using the old email system with AWS SES, SMTP, or sendmail:
#
# OLD (multiple methods):
#   export DEPLOYMENT_EMAIL_METHOD="sendmail"  # or "aws-ses" or "smtp"
#   export SMTP_HOST="smtp.gmail.com"
#   export SMTP_PORT="587"
#   ... (many configuration options)
#
# NEW (SendGrid only - simpler!):
#   export SENDGRID_API_KEY="SG.xxxxxxxxxxxxxxxxxxxx"
#
# That's it! Just one configuration value needed.
#
# ==============================================================================
# TROUBLESHOOTING
# ==============================================================================
#
# Issue: "SENDGRID_API_KEY is not set"
# Fix: Make sure you've set the API key using one of the methods above
#
# Issue: "SendGrid API request failed with HTTP code: 401"
# Fix: Invalid API key - check that you copied it correctly
#
# Issue: "SendGrid API request failed with HTTP code: 403"
# Fix: API key doesn't have "Mail Send" permission - create a new key with correct permissions
#
# Issue: Emails not arriving
# Fix: Check SendGrid dashboard > Activity for delivery status
# Fix: Verify sender email is authenticated in SendGrid
# Fix: Check spam folder
#
# ==============================================================================
# ADVANTAGES OF SENDGRID API VS OLD METHODS
# ==============================================================================
#
# Why SendGrid API is better than the old system:
#
# 1. Simpler Configuration:
#    - Old: ~15 config variables across AWS SES, SMTP, sendmail
#    - New: 1 config variable (SENDGRID_API_KEY)
#
# 2. No Server Dependencies:
#    - Old: Required sendmail/mailutils, AWS CLI, or Python with SMTP libs
#    - New: Just curl (already installed everywhere)
#
# 3. Better Reliability:
#    - Old: sendmail often fails, SMTP has firewall issues, AWS SES needs credentials
#    - New: Simple HTTPS API call, works everywhere
#
# 4. Better Deliverability:
#    - SendGrid has excellent reputation and handles SPF/DKIM automatically
#
# 5. Easy Monitoring:
#    - SendGrid dashboard shows delivery status, opens, clicks, bounces
#
# 6. Free Tier Sufficient:
#    - 100 emails/day free - plenty for deployment notifications
#
