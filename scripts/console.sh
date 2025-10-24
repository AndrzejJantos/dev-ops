#!/bin/bash

# Rails console access script (works with new app-specific architecture)
# Location: /home/andrzej/DevOps/scripts/console.sh
# Usage: ./console.sh <app-name>

set -e

APP_NAME="$1"

if [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <app-name>"
    echo ""
    echo "Available apps:"
    ls -1 /home/andrzej/apps/ 2>/dev/null || echo "  (none)"
    echo ""
    echo "Examples:"
    echo "  $0 cheaperfordrug-landing"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(dirname "$SCRIPT_DIR")"

# Try to find app configuration
APP_CONFIG_DIR="${DEVOPS_DIR}/apps/${APP_NAME}"

if [ ! -d "$APP_CONFIG_DIR" ]; then
    echo "Error: Application '${APP_NAME}' not found in DevOps configuration"
    echo "Available apps:"
    ls -1 "${DEVOPS_DIR}/apps/" 2>/dev/null || echo "  (none)"
    exit 1
fi

# Load app configuration to get paths
if [ -f "${APP_CONFIG_DIR}/config.sh" ]; then
    source "${APP_CONFIG_DIR}/config.sh"
else
    echo "Error: Configuration file not found: ${APP_CONFIG_DIR}/config.sh"
    exit 1
fi

# Validate paths
if [ ! -d "$APP_DIR" ]; then
    echo "Error: Application directory not found: ${APP_DIR}"
    echo "Have you run the setup script?"
    echo "  ${APP_CONFIG_DIR}/setup.sh"
    exit 1
fi

if [ ! -d "$REPO_DIR" ]; then
    echo "Error: Repository directory not found: ${REPO_DIR}"
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Environment file not found: ${ENV_FILE}"
    exit 1
fi

echo "=== Rails Console for ${APP_DISPLAY_NAME:-$APP_NAME} ==="
echo "Repository: ${REPO_DIR}"
echo "Environment: production"
echo ""

# Change to repo directory
cd "$REPO_DIR"

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# Start Rails console
RAILS_ENV=production bundle exec rails console
