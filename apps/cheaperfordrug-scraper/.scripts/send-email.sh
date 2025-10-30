#!/bin/bash

# ============================================================================
# SendGrid Email Sender
# ============================================================================
# Sends emails via SendGrid API v3
#
# Usage:
#   ./send-email.sh "subject" "body_html"
#
# Environment Variables:
#   SENDGRID_API_KEY - SendGrid API key (required)
#
# Returns:
#   0 - Email sent successfully
#   1 - Failed to send email
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURATION
# ============================================================================

FROM_EMAIL="webet1@webet.pl"
TO_EMAIL="andrzej@webet.pl"
FROM_NAME="CheaperForDrug Scraper"
SENDGRID_API_URL="https://api.sendgrid.com/v3/mail/send"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[EMAIL]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[EMAIL]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[EMAIL]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[EMAIL]${NC} $1" >&2
}

# ============================================================================
# VALIDATION
# ============================================================================

validate_inputs() {
    # Check if API key is set
    if [ -z "${SENDGRID_API_KEY:-}" ]; then
        log_error "SENDGRID_API_KEY environment variable is not set"
        log_error "Please set it in your shell profile:"
        log_error "  export SENDGRID_API_KEY=\"SG.xxx...\""
        return 1
    fi

    # Check if subject is provided
    if [ -z "${1:-}" ]; then
        log_error "Subject is required"
        log_error "Usage: ./send-email.sh \"subject\" \"body_html\""
        return 1
    fi

    # Check if body is provided
    if [ -z "${2:-}" ]; then
        log_error "Body HTML is required"
        log_error "Usage: ./send-email.sh \"subject\" \"body_html\""
        return 1
    fi

    return 0
}

# ============================================================================
# EMAIL SENDING
# ============================================================================

send_email() {
    local subject="$1"
    local body_html="$2"

    log_info "Preparing to send email..."
    log_info "From: ${FROM_EMAIL}"
    log_info "To: ${TO_EMAIL}"
    log_info "Subject: ${subject}"

    # Create JSON payload
    # Note: Using jq would be safer, but we'll use careful escaping for portability
    local json_payload
    json_payload=$(cat <<EOF
{
  "personalizations": [
    {
      "to": [
        {
          "email": "${TO_EMAIL}"
        }
      ],
      "subject": "${subject}"
    }
  ],
  "from": {
    "email": "${FROM_EMAIL}",
    "name": "${FROM_NAME}"
  },
  "content": [
    {
      "type": "text/html",
      "value": $(echo "${body_html}" | jq -Rs .)
    }
  ]
}
EOF
)

    # Send email via SendGrid API
    local response
    local http_code

    response=$(curl --silent --write-out "\n%{http_code}" \
        --request POST \
        --url "${SENDGRID_API_URL}" \
        --header "Authorization: Bearer ${SENDGRID_API_KEY}" \
        --header 'Content-Type: application/json' \
        --data "${json_payload}" 2>&1)

    # Extract HTTP status code (last line)
    http_code=$(echo "${response}" | tail -n1)

    # Extract response body (all but last line)
    local response_body
    response_body=$(echo "${response}" | sed '$d')

    # Check HTTP status code
    if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 300 ]; then
        log_success "Email sent successfully (HTTP ${http_code})"
        return 0
    else
        log_error "Failed to send email (HTTP ${http_code})"
        if [ -n "${response_body}" ]; then
            log_error "Response: ${response_body}"
        fi
        return 1
    fi
}

# ============================================================================
# FALLBACK EMAIL SENDING (without jq)
# ============================================================================

send_email_fallback() {
    local subject="$1"
    local body_html="$2"

    log_info "Using fallback email method (no jq)..."
    log_info "From: ${FROM_EMAIL}"
    log_info "To: ${TO_EMAIL}"
    log_info "Subject: ${subject}"

    # Escape JSON manually (basic escaping)
    local escaped_body
    escaped_body=$(echo "${body_html}" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    # Create JSON payload with manual escaping
    local json_payload
    json_payload=$(cat <<EOF
{
  "personalizations": [
    {
      "to": [
        {
          "email": "${TO_EMAIL}"
        }
      ],
      "subject": "${subject}"
    }
  ],
  "from": {
    "email": "${FROM_EMAIL}",
    "name": "${FROM_NAME}"
  },
  "content": [
    {
      "type": "text/html",
      "value": "${escaped_body}"
    }
  ]
}
EOF
)

    # Send email via SendGrid API
    local response
    local http_code

    response=$(curl --silent --write-out "\n%{http_code}" \
        --request POST \
        --url "${SENDGRID_API_URL}" \
        --header "Authorization: Bearer ${SENDGRID_API_KEY}" \
        --header 'Content-Type: application/json' \
        --data "${json_payload}" 2>&1)

    # Extract HTTP status code (last line)
    http_code=$(echo "${response}" | tail -n1)

    # Extract response body (all but last line)
    local response_body
    response_body=$(echo "${response}" | sed '$d')

    # Check HTTP status code
    if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 300 ]; then
        log_success "Email sent successfully (HTTP ${http_code})"
        return 0
    else
        log_error "Failed to send email (HTTP ${http_code})"
        if [ -n "${response_body}" ]; then
            log_error "Response: ${response_body}"
        fi
        return 1
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local subject="${1:-}"
    local body_html="${2:-}"

    # Validate inputs
    if ! validate_inputs "${subject}" "${body_html}"; then
        return 1
    fi

    # Try to send email with jq if available, otherwise use fallback
    if command -v jq >/dev/null 2>&1; then
        send_email "${subject}" "${body_html}"
    else
        log_warning "jq not found, using fallback method"
        send_email_fallback "${subject}" "${body_html}"
    fi
}

# Run main with all arguments
main "$@"
