#!/bin/bash

# Email Templates for Deployment Notifications - PLAIN TEXT ONLY
# Location: /home/andrzej/DevOps/common/email-templates.sh
#
# This module provides email templates for various notifications
# Easy to add new notification types - just create new generate_*_email functions
#
# Usage:
#   source email-templates.sh
#   generate_deployment_success_email <params...>
#   generate_deployment_failure_email <params...>
#
# Each function returns a structured result via exported variables:
#   EMAIL_SUBJECT, EMAIL_TEXT_BODY

set -e

# ==============================================================================
# DEPLOYMENT SUCCESS EMAIL TEMPLATE
# ==============================================================================

# Generate deployment success email
# Arguments:
#   $1 - app_name (e.g., "cheaperfordrug-api")
#   $2 - app_display_name (e.g., "CheaperForDrug API")
#   $3 - domain (e.g., "api.cheaperfordrug.com")
#   $4 - scale (number of containers deployed)
#   $5 - image_tag (Docker image tag)
#   $6 - migrations_run (true/false)
#   $7 - git_commit (short hash)
# Returns:
#   Sets EMAIL_SUBJECT, EMAIL_TEXT_BODY variables
generate_deployment_success_email() {
    local app_name="$1"
    local app_display_name="$2"
    local domain="$3"
    local scale="$4"
    local image_tag="$5"
    local migrations_run="${6:-N/A}"
    local git_commit="${7:-N/A}"

    local deployment_time="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    local server_hostname="$(hostname)"

    # Collect container information
    local containers_info=""
    local containers=($(docker ps --filter "name=${app_name}_web" --format "{{.Names}}" 2>/dev/null))
    for container in "${containers[@]}"; do
        local port=$(docker port "$container" 2>/dev/null | grep -oP '\d+:\d+' | head -1)
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
        if [ -z "$port" ]; then
            containers_info="${containers_info}    - ${container} (behind nginx, status: ${status})\n"
        else
            containers_info="${containers_info}    - ${container} (port ${port}, status: ${status})\n"
        fi
    done

    # Collect worker information
    local workers_info=""
    local worker_containers=($(docker ps --filter "name=${app_name}_worker" --format "{{.Names}}" 2>/dev/null))
    if [ ${#worker_containers[@]} -gt 0 ]; then
        workers_info="WORKER CONTAINERS\nCount: ${#worker_containers[@]} instances\n"
        for worker in "${worker_containers[@]}"; do
            local status=$(docker inspect -f '{{.State.Status}}' "$worker" 2>/dev/null)
            workers_info="${workers_info}- ${worker} (status: ${status})\n"
        done
        workers_info="${workers_info}\n"
    fi

    # Collect SSL certificate information
    local ssl_info=""
    if command -v certbot >/dev/null 2>&1 && sudo certbot certificates 2>/dev/null | grep -q "Certificate Name: ${domain}"; then
        local cert_info=$(sudo certbot certificates 2>/dev/null | grep -A 6 "Certificate Name: ${domain}" | head -7)
        local domains=$(echo "$cert_info" | grep "Domains:" | head -1 | sed 's/.*Domains: //')
        local expiry_date=$(echo "$cert_info" | grep "Expiry Date:" | head -1 | awk '{print $3}')

        if [ -n "$expiry_date" ]; then
            local expiry_ts=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
            local now_ts=$(date +%s)
            local days_left=$(( (expiry_ts - now_ts) / 86400 ))

            ssl_info="SSL CERTIFICATE\nStatus: Active\nDomains: ${domains}\nExpires: ${expiry_date}\nValidity: ${days_left} days remaining\nCertificate: /etc/letsencrypt/live/${domain}/\n"

            if [ -n "${SSL_SETUP_STATUS:-}" ]; then
                case "$SSL_SETUP_STATUS" in
                    success) ssl_info="${ssl_info}Last Setup: Success\n" ;;
                    failed) ssl_info="${ssl_info}Last Setup: FAILED\n" ;;
                esac
            fi
            ssl_info="${ssl_info}\n"
        fi
    else
        ssl_info="SSL CERTIFICATE\nStatus: Not configured\n\n"
    fi

    # Collect image backup information
    local image_backup_info=""
    if [ -d "${IMAGE_BACKUP_DIR:-}" ]; then
        local backup_count=$(ls -1 "${IMAGE_BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        image_backup_info="IMAGE BACKUPS\nAvailable: ${backup_count} backups\nLocation: ${IMAGE_BACKUP_DIR}\nLatest: ${IMAGE_BACKUP_DIR}/${app_name}_${image_tag}.tar.gz\n\n"
    fi

    # Collect database backup information
    local db_backup_info=""
    if [ -d "${BACKUP_DIR:-}" ]; then
        local db_backup_count=$(ls -1 ${BACKUP_DIR}/*.sql.gz 2>/dev/null | wc -l | tr -d ' ')
        local latest_db_backup=$(ls -t ${BACKUP_DIR}/*.sql.gz 2>/dev/null | head -1 | xargs -r basename)
        db_backup_info="DATABASE\nName: ${DB_NAME:-N/A}\nAvailable Backups: ${db_backup_count}\nLatest Backup: ${latest_db_backup}\nBackup Location: ${BACKUP_DIR}\n\n"
    fi

    # Collect internal domain info if exists
    local internal_url=""
    if [ -n "${DOMAIN_INTERNAL:-}" ]; then
        internal_url="  Internal Domain:  ${DOMAIN_INTERNAL}\n"
    fi

    # Subject (clean text, no emojis)
    export EMAIL_SUBJECT="Deployment Successful: $app_display_name"

    # Plain text body (NO color codes, NO emojis - clean TXT mode)
    # Strip any ANSI color codes that might be in the data
    local clean_ssl_info=$(echo -e "$ssl_info" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/✓/Success/g' | sed 's/✗/FAILED/g')
    local clean_containers_info=$(echo -e "$containers_info" | sed 's/\x1b\[[0-9;]*m//g')
    local clean_workers_info=$(echo -e "$workers_info" | sed 's/\x1b\[[0-9;]*m//g')
    local clean_internal_url=$(echo -e "$internal_url" | sed 's/\x1b\[[0-9;]*m//g')
    local clean_image_backup_info=$(echo -e "$image_backup_info" | sed 's/\x1b\[[0-9;]*m//g')
    local clean_db_backup_info=$(echo -e "$db_backup_info" | sed 's/\x1b\[[0-9;]*m//g')

    export EMAIL_TEXT_BODY=$(cat << EOF
================================================================
    DEPLOYMENT SUCCESSFUL - ALL CONTAINERS REPLACED
================================================================

------------------------------------------------------------
APPLICATION DETAILS
------------------------------------------------------------
  Name:             $app_display_name
  Type:             Rails API
  App ID:           $app_name
  Git Commit:       $git_commit
  Image Tag:        $image_tag

------------------------------------------------------------
DEPLOYMENT STATUS
------------------------------------------------------------
  Status:           SUCCESS
  Timestamp:        $deployment_time
  Migrations Run:   $migrations_run

------------------------------------------------------------
AVAILABILITY
------------------------------------------------------------
  Primary Domain:   $domain
${clean_internal_url}  Health Check:     https://$domain/up

------------------------------------------------------------
${clean_ssl_info}------------------------------------------------------------
WEB CONTAINERS
------------------------------------------------------------
  Count:            ${#containers[@]} instances

  Containers:
$(echo -e "$clean_containers_info")
${clean_workers_info}${clean_image_backup_info}${clean_db_backup_info}================================================================
USEFUL COMMANDS
================================================================

  Deploy Application:
    cd ~/DevOps/apps/${app_name} && ./deploy.sh

  Rails Console:
    ~/apps/${app_name}/console.sh

  Health Check:
    curl https://${domain}/up

  Scale Containers:
    cd ~/DevOps/apps/${app_name} && ./deploy.sh scale N

  Restart Services:
    cd ~/DevOps/apps/${app_name} && ./deploy.sh restart

  Rollback Deployment:
    cd ~/DevOps/apps/${app_name} && ./deploy.sh rollback

  Stop Application:
    cd ~/DevOps/apps/${app_name} && ./deploy.sh stop

------------------------------------------------------------
NAVIGATION
------------------------------------------------------------
  Config Directory:     cd ~/DevOps/apps/${app_name}
  Deployed App:         cd ~/apps/${app_name}
  Quick Config Link:    cd ~/apps/${app_name}/config

------------------------------------------------------------
LOGS & MONITORING
------------------------------------------------------------
  All Logs:
    tail -f ~/apps/${app_name}/logs/production.log

  Sidekiq Only:
    tail -f ~/apps/${app_name}/logs/production.log | grep Sidekiq

  Container Logs:
    docker logs ${app_name}_web_1 -f

  Inside Container:
    docker exec ${app_name}_web_1 tail -f /app/log/production.log

================================================================

Deployed on $deployment_time

This is an automated notification from the CheaperForDrug
deployment system.
EOF
)
}

# ==============================================================================
# DEPLOYMENT START EMAIL TEMPLATE
# ==============================================================================

# Generate deployment start email
# Arguments:
#   $1 - app_name (e.g., "cheaperfordrug-api")
#   $2 - app_display_name (e.g., "CheaperForDrug API")
#   $3 - domain (e.g., "api.cheaperfordrug.com")
#   $4 - git_commit (short hash)
# Returns:
#   Sets EMAIL_SUBJECT, EMAIL_TEXT_BODY variables
generate_deployment_start_email() {
    local app_name="$1"
    local app_display_name="$2"
    local domain="$3"
    local git_commit="${4:-N/A}"

    local deployment_time="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    local server_hostname="$(hostname)"

    # Subject
    export EMAIL_SUBJECT="Deployment Starting: $app_display_name"

    # Plain text body (NO color codes, NO emojis for clean TXT mode)
    export EMAIL_TEXT_BODY=$(cat << EOF
================================================================
    DEPLOYMENT STARTING
================================================================

------------------------------------------------------------
APPLICATION DETAILS
------------------------------------------------------------
  Name:             $app_display_name
  Type:             Rails API
  App ID:           $app_name
  Git Commit:       $git_commit
  Domain:           $domain

------------------------------------------------------------
DEPLOYMENT STATUS
------------------------------------------------------------
  Status:           IN PROGRESS
  Started:          $deployment_time
  Server:           $server_hostname

------------------------------------------------------------
AVAILABILITY
------------------------------------------------------------
  Primary Domain:   $domain
  Health Check:     https://$domain/up

------------------------------------------------------------
NEXT STEPS
------------------------------------------------------------
  The deployment process will perform the following actions:

    1. Pulling latest code from repository
    2. Building Docker image
    3. Running database migrations (if configured)
    4. Performing rolling restart of containers
    5. Setting up SSL certificates (if needed)

------------------------------------------------------------
MONITORING
------------------------------------------------------------
  You will receive another email when the deployment
  completes successfully or if any errors occur.

================================================================

Started on $deployment_time

This is an automated notification from the CheaperForDrug
deployment system.
EOF
)
}

# ==============================================================================
# DEPLOYMENT FAILURE EMAIL TEMPLATE
# ==============================================================================

# Generate deployment failure email
# Arguments:
#   $1 - app_name (e.g., "cheaperfordrug-api")
#   $2 - app_display_name (e.g., "CheaperForDrug API")
#   $3 - error_message (error details)
# Returns:
#   Sets EMAIL_SUBJECT, EMAIL_TEXT_BODY variables
generate_deployment_failure_email() {
    local app_name="$1"
    local app_display_name="$2"
    local error_message="$3"

    local deployment_time="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    local server_hostname="$(hostname)"

    # Subject (clean text, no emojis)
    export EMAIL_SUBJECT="Deployment Failed: $app_display_name"

    # Plain text body (NO color codes, NO emojis - clean TXT mode)
    # Strip any ANSI color codes from error message
    local clean_error_message=$(echo "$error_message" | sed 's/\x1b\[[0-9;]*m//g')

    export EMAIL_TEXT_BODY=$(cat << EOF
================================================================
    DEPLOYMENT FAILED - ACTION REQUIRED
================================================================

------------------------------------------------------------
APPLICATION DETAILS
------------------------------------------------------------
  Application:      $app_display_name
  Server:           $server_hostname
  Timestamp:        $deployment_time

------------------------------------------------------------
ERROR DETAILS
------------------------------------------------------------

$clean_error_message

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

  Check Application Health:
    curl https://${DOMAIN:-$app_name}/up

  View All Running Containers:
    docker ps -a | grep ${app_name}

  Check Docker Resources:
    docker system df
    docker stats --no-stream

================================================================

Failed on $deployment_time

This is an automated notification from the CheaperForDrug
deployment system.

PLEASE INVESTIGATE AND RESOLVE THE ISSUE PROMPTLY.
EOF
)
}

# ==============================================================================
# EXAMPLE: HOW TO ADD NEW EMAIL TEMPLATES
# ==============================================================================

# To add a new email type (e.g., backup complete), create a function like this:
#
# generate_backup_complete_email() {
#     local app_name="$1"
#     local backup_size="$2"
#     local backup_location="$3"
#
#     export EMAIL_SUBJECT="✓ Backup Complete: $app_name"
#     export EMAIL_TEXT_BODY="Backup completed successfully..."
#     export EMAIL_HTML_BODY="<html>...</html>"
# }
#
# Then update email-notification.sh to add a public API function:
#
# send_backup_complete_email() {
#     generate_backup_complete_email "$@"
#     send_email_via_sendgrid "$EMAIL_FROM" "$EMAIL_TO" "$EMAIL_SUBJECT" "$EMAIL_TEXT_BODY" "$EMAIL_HTML_BODY"
# }
