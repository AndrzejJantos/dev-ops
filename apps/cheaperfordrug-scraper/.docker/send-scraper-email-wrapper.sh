#!/bin/bash

# ============================================================================
# Scraper Email Wrapper Script
# ============================================================================
# This script is called from inside the container to send emails from the host
# It bridges the gap between container and host environment
#
# Usage (from inside container):
#   /app/docker-scripts/send-scraper-email-wrapper.sh start|finish
#
# This script must be mounted into the container via docker-compose volumes
# ============================================================================

set -euo pipefail

EVENT="${1:-}"

# Validate event type
if [ -z "${EVENT}" ]; then
    echo "Error: Event type required (start|finish)" >&2
    exit 1
fi

# Check if we have SENDGRID_API_KEY
if [ -z "${SENDGRID_API_KEY:-}" ]; then
    echo "Info: SENDGRID_API_KEY not set, skipping email notification" >&2
    exit 0
fi

# Export SENDGRID_API_KEY for the host script
export SENDGRID_API_KEY

# Path to the host-based email script
# The script assumes it's running on the host where HOME is defined
HOST_SCRIPT_DIR="${HOME:-/home/andrzej}/apps/cheaperfordrug-scraper/.scripts"
EMAIL_SCRIPT="${HOST_SCRIPT_DIR}/send-scraper-email.sh"

# Check if host script exists (should be available via mounted volume)
if [ ! -f "${EMAIL_SCRIPT}" ]; then
    echo "Warning: Email script not found at ${EMAIL_SCRIPT}" >&2
    echo "Skipping email notification" >&2
    exit 0
fi

# Execute the host email script
exec "${EMAIL_SCRIPT}" "${EVENT}"
