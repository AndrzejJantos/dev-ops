#!/bin/bash

# SendGrid API Email Sender - PLAIN TEXT ONLY
# Location: /home/andrzej/DevOps/common/sendgrid-api.sh
#
# Simple, focused SendGrid API v3 sender using curl
# Single responsibility: Send emails via SendGrid API
#
# IMPORTANT: Sends PLAIN TEXT ONLY emails (no HTML)
#
# Usage:
#   source sendgrid-api.sh
#   send_email_via_sendgrid "from@example.com" "to@example.com" "Subject" "Plain text body"
#
# Requirements:
#   - SENDGRID_API_KEY environment variable must be set
#   - curl command must be available

set -e

# ==============================================================================
# SENDGRID API CONFIGURATION
# ==============================================================================

# SendGrid API endpoint
SENDGRID_API_URL="https://api.sendgrid.com/v3/mail/send"

# ==============================================================================
# SENDGRID API SENDER
# ==============================================================================

# Send email via SendGrid API v3 - PLAIN TEXT ONLY
# Arguments:
#   $1 - from_email (e.g., "sender@example.com")
#   $2 - to_email (e.g., "recipient@example.com")
#   $3 - subject
#   $4 - text_body (plain text version)
# Returns:
#   0 on success, 1 on failure
send_email_via_sendgrid() {
    local from_email="$1"
    local to_email="$2"
    local subject="$3"
    local text_body="$4"

    # Validate inputs
    if [ -z "$from_email" ] || [ -z "$to_email" ] || [ -z "$subject" ]; then
        log_error "Missing required parameters for send_email_via_sendgrid"
        log_error "Usage: send_email_via_sendgrid FROM TO SUBJECT TEXT_BODY"
        return 1
    fi

    # Check if SendGrid API key is set
    if [ -z "${SENDGRID_API_KEY:-}" ]; then
        log_error "SENDGRID_API_KEY environment variable is not set"
        log_error "Please set SENDGRID_API_KEY in your environment or email-config.sh"
        return 1
    fi

    # Check if curl is available
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl command not found. Install with: sudo apt-get install curl"
        return 1
    fi

    # Escape JSON strings (handle quotes, newlines, backslashes)
    escape_json() {
        local string="$1"
        # Use Python for robust JSON escaping if available
        if command -v python3 >/dev/null 2>&1; then
            python3 -c "import json; print(json.dumps('$string')[1:-1])" 2>/dev/null || echo "$string" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//'
        else
            # Fallback to basic sed escaping
            echo "$string" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//'
        fi
    }

    # Build JSON payload using temporary file to avoid escaping issues
    # PLAIN TEXT ONLY - NO HTML
    local json_payload=$(mktemp)

    cat > "$json_payload" <<EOF
{
  "personalizations": [
    {
      "to": [
        {
          "email": "$to_email"
        }
      ],
      "subject": "$subject"
    }
  ],
  "from": {
    "email": "$from_email",
    "name": "WebET Data Center"
  },
  "content": [
    {
      "type": "text/plain",
      "value": $(echo "$text_body" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
    }
  ]
}
EOF

    # Send request to SendGrid API
    local http_code=$(curl -s -o /tmp/sendgrid_response_$$.json -w "%{http_code}" \
        -X POST \
        "$SENDGRID_API_URL" \
        -H "Authorization: Bearer $SENDGRID_API_KEY" \
        -H "Content-Type: application/json" \
        -d @"$json_payload")

    # Clean up temp file
    rm -f "$json_payload"

    # Check HTTP response code
    if [ "$http_code" = "202" ]; then
        # log_success "Email sent successfully via SendGrid API"  # Removed: silent email sending
        rm -f /tmp/sendgrid_response_$$.json
        return 0
    else
        log_error "SendGrid API request failed with HTTP code: $http_code"
        if [ -f /tmp/sendgrid_response_$$.json ]; then
            log_error "Response: $(cat /tmp/sendgrid_response_$$.json)"
            rm -f /tmp/sendgrid_response_$$.json
        fi
        return 1
    fi
}

# Check if SendGrid API key is configured
check_sendgrid_requirements() {
    if [ -z "${SENDGRID_API_KEY:-}" ]; then
        log_error "SENDGRID_API_KEY is not set"
        log_error "Please configure SENDGRID_API_KEY in email-config.sh or your environment"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl not found. Install with: sudo apt-get install curl"
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        log_warning "python3 not found. JSON escaping may be less robust"
        log_warning "Install with: sudo apt-get install python3"
    fi

    return 0
}
