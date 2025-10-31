#!/bin/bash

# Brokik API Setup Script
# This is a thin wrapper that uses the common setup infrastructure

set -e

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common utilities
source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/docker-utils.sh"

# Load app configuration
source "$SCRIPT_DIR/config.sh"

# Load generic setup script
source "$DEVOPS_DIR/common/setup-app.sh"

# Run setup
setup_application
