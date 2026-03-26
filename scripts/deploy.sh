#!/bin/bash

# Deployment Orchestrator Script
# Location: DevOps/scripts/deploy.sh
# Usage: ./deploy.sh [app1 app2 ...]
# If no arguments: deploys all whitelisted apps
# Example: ./deploy.sh cheaperfordrug-api cheaperfordrug-web brokik-api

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(dirname "$SCRIPT_DIR")"
APPS_DIR="$DEVOPS_DIR/apps"

# =============================================================================
# BLACKLIST - Apps that won't be deployed automatically
# =============================================================================
BLACKLISTED_APPS=(
)

# Function to check if app is blacklisted
is_blacklisted() {
    local app="$1"
    for blacklisted in "${BLACKLISTED_APPS[@]}"; do
        if [ "$app" = "$blacklisted" ]; then
            return 0  # true, is blacklisted
        fi
    done
    return 1  # false, not blacklisted
}

# Function to get all whitelisted apps
get_whitelisted_apps() {
    local apps=()
    for app_dir in "$APPS_DIR"/*/; do
        if [ -f "$app_dir/deploy.sh" ]; then
            local app_name=$(basename "$app_dir")
            if ! is_blacklisted "$app_name"; then
                apps+=("$app_name")
            fi
        fi
    done
    echo "${apps[@]}"
}

# If no arguments, deploy all whitelisted apps
if [ $# -eq 0 ]; then
    APPS=($(get_whitelisted_apps))

    if [ ${#APPS[@]} -eq 0 ]; then
        log_error "No apps available for deployment"
        exit 1
    fi

    echo ""
    echo "Deployment Orchestrator"
    echo "======================="
    echo ""
    echo "No apps specified - will deploy all whitelisted apps:"
    for app in "${APPS[@]}"; do
        echo "  - $app"
    done
    echo ""
    if [ ${#BLACKLISTED_APPS[@]} -gt 0 ]; then
        echo "Blacklisted (skipped):"
        for app in "${BLACKLISTED_APPS[@]}"; do
            echo "  - $app"
        done
        echo ""
    fi
else
    APPS=("$@")
fi
TOTAL_APPS=${#APPS[@]}
SUCCESSFUL=()
FAILED=()

echo ""
echo "========================================"
echo -e "  ${CYAN}Deployment Orchestrator${NC}"
echo "========================================"
echo ""
echo "  Apps to deploy: ${TOTAL_APPS}"
for app in "${APPS[@]}"; do
    echo "    - $app"
done
echo ""

# Validate all apps exist before starting
log_info "Validating apps..."
for app in "${APPS[@]}"; do
    APP_DIR="$APPS_DIR/$app"
    if [ ! -d "$APP_DIR" ]; then
        log_error "App directory not found: $APP_DIR"
        exit 1
    fi
    if [ ! -f "$APP_DIR/deploy.sh" ]; then
        log_error "Deploy script not found: $APP_DIR/deploy.sh"
        exit 1
    fi
done
log_success "All apps validated"
echo ""

# Confirm
read -p "Start deployment of ${TOTAL_APPS} app(s)? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log_info "Deployment cancelled"
    exit 0
fi

TOTAL_START=$(date +%s)

# Deploy each app
CURRENT=0
for app in "${APPS[@]}"; do
    CURRENT=$((CURRENT + 1))
    APP_DIR="$APPS_DIR/$app"

    echo ""
    echo "========================================"
    echo -e "  ${CYAN}[$CURRENT/$TOTAL_APPS] Deploying: $app${NC}"
    echo "========================================"
    echo ""

    APP_START=$(date +%s)

    # Run deployment
    cd "$APP_DIR"
    if ./deploy.sh deploy; then
        APP_END=$(date +%s)
        APP_ELAPSED=$((APP_END - APP_START))
        log_success "$app deployed successfully (${APP_ELAPSED}s)"
        SUCCESSFUL+=("$app")
    else
        APP_END=$(date +%s)
        APP_ELAPSED=$((APP_END - APP_START))
        log_error "$app deployment failed (${APP_ELAPSED}s)"
        FAILED+=("$app")

        # Ask whether to continue
        if [ $CURRENT -lt $TOTAL_APPS ]; then
            echo ""
            read -p "Continue with remaining deployments? (yes/no): " continue_deploy
            if [ "$continue_deploy" != "yes" ]; then
                log_warning "Deployment stopped by user"
                break
            fi
        fi
    fi

    # Brief pause between deployments
    if [ $CURRENT -lt $TOTAL_APPS ]; then
        sleep 3
    fi
done

TOTAL_END=$(date +%s)
TOTAL_ELAPSED=$((TOTAL_END - TOTAL_START))

# Format time
format_time() {
    local seconds=$1
    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    fi
}

# Summary
echo ""
echo "========================================"
echo -e "  ${GREEN}Deployment Summary${NC}"
echo "========================================"
echo ""
echo "  Total time: $(format_time $TOTAL_ELAPSED)"
echo ""

if [ ${#SUCCESSFUL[@]} -gt 0 ]; then
    echo -e "  ${GREEN}Successful (${#SUCCESSFUL[@]}):${NC}"
    for app in "${SUCCESSFUL[@]}"; do
        echo -e "    ${GREEN}✓${NC} $app"
    done
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    echo ""
    echo -e "  ${RED}Failed (${#FAILED[@]}):${NC}"
    for app in "${FAILED[@]}"; do
        echo -e "    ${RED}✗${NC} $app"
    done
fi

echo ""
echo "========================================"
echo ""

# Exit with error if any failed
if [ ${#FAILED[@]} -gt 0 ]; then
    exit 1
fi
