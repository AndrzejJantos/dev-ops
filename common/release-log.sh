#!/bin/bash

# Release Logging Module
# Location: /home/andrzej/DevOps/common/release-log.sh
#
# This module provides centralized deployment logging to ~/DevOps/release.log
# All deployments (successes and failures) are logged with detailed information

# ==============================================================================
# CONFIGURATION
# ==============================================================================
RELEASE_LOG_FILE="${DEVOPS_DIR}/release.log"

# Ensure log file exists and is writable
ensure_release_log() {
    if [ ! -f "$RELEASE_LOG_FILE" ]; then
        touch "$RELEASE_LOG_FILE"
        echo "# CheaperForDrug & Brokik Deployment Release Log" > "$RELEASE_LOG_FILE"
        echo "# Format: [TIMESTAMP] [STATUS] [APP] [VERSION] [DETAILS]" >> "$RELEASE_LOG_FILE"
        echo "# ============================================================================" >> "$RELEASE_LOG_FILE"
        echo "" >> "$RELEASE_LOG_FILE"
    fi
}

# ==============================================================================
# LOG DEPLOYMENT START
# ==============================================================================
log_deployment_start() {
    local app_name="$1"
    local app_display_name="$2"
    local git_commit="${3:-N/A}"

    ensure_release_log

    local timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")

    cat >> "$RELEASE_LOG_FILE" <<EOF

========================================================================================================
[${timestamp}] DEPLOYMENT STARTED - ${app_display_name}
========================================================================================================
  App ID:        ${app_name}
  Git Commit:    ${git_commit}
  Server:        $(hostname)
  User:          $(whoami)
--------------------------------------------------------------------------------------------------------
EOF
}

# ==============================================================================
# LOG DEPLOYMENT SUCCESS
# ==============================================================================
log_deployment_success() {
    local app_name="$1"
    local app_display_name="$2"
    local domain="${3:-N/A}"
    local scale="$4"
    local image_tag="$5"
    local migrations_run="${6:-N/A}"
    local git_commit="${7:-N/A}"

    ensure_release_log

    local timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
    local duration="N/A"

    cat >> "$RELEASE_LOG_FILE" <<EOF
[${timestamp}] ✓ DEPLOYMENT SUCCESS - ${app_display_name}
--------------------------------------------------------------------------------------------------------
  App ID:        ${app_name}
  Domain:        ${domain}
  Git Commit:    ${git_commit}
  Image Tag:     ${image_tag}
  Scale:         ${scale} containers
  Migrations:    ${migrations_run}
  Server:        $(hostname)
  User:          $(whoami)
--------------------------------------------------------------------------------------------------------

EOF
}

# ==============================================================================
# LOG DEPLOYMENT FAILURE
# ==============================================================================
log_deployment_failure() {
    local app_name="$1"
    local app_display_name="$2"
    local error_message="$3"
    local git_commit="${4:-N/A}"

    ensure_release_log

    local timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")

    cat >> "$RELEASE_LOG_FILE" <<EOF
[${timestamp}] ✗ DEPLOYMENT FAILED - ${app_display_name}
========================================================================================================

------------------------------------------------------------
APPLICATION DETAILS
------------------------------------------------------------
 Application:      ${app_display_name}
 App ID:           ${app_name}
 Server:           $(hostname)
 User:             $(whoami)
 Git Commit:       ${git_commit}
 Timestamp:        ${timestamp}

------------------------------------------------------------
ERROR DETAILS
------------------------------------------------------------

${error_message}

------------------------------------------------------------
RECOMMENDED ACTIONS
------------------------------------------------------------

 1. Check the deployment logs for detailed error information

 2. Verify that all prerequisites are met:
    - Database connectivity
    - Redis availability
    - Required environment variables

 3. Check for configuration issues:
    - Review docker-compose.yml
    - Verify environment files
    - Check port conflicts

 4. Review recent code changes:
    - Check git log for breaking changes
    - Verify database migration compatibility
    - Review dependency updates

------------------------------------------------------------
TROUBLESHOOTING COMMANDS
------------------------------------------------------------

 View Container Logs:
   docker logs ${app_name}_web_1 -f

 Check Deployment Status:
   cd ~/DevOps/apps/${app_name} && ./deploy.sh status

 View All Running Containers:
   docker ps -a | grep ${app_name}

 Check Docker Resources:
   docker system df
   docker stats --no-stream

========================================================================================================

EOF
}

# ==============================================================================
# DISPLAY RECENT RELEASES
# ==============================================================================
show_recent_releases() {
    local count="${1:-10}"

    ensure_release_log

    echo "Recent Deployments (last ${count}):"
    echo "========================================"
    echo ""

    grep -E "DEPLOYMENT (STARTED|SUCCESS|FAILED)" "$RELEASE_LOG_FILE" | tail -n "$count"

    echo ""
    echo "Full log: $RELEASE_LOG_FILE"
}

# ==============================================================================
# EXPORT FUNCTIONS
# ==============================================================================
export -f ensure_release_log
export -f log_deployment_start
export -f log_deployment_success
export -f log_deployment_failure
export -f show_recent_releases
