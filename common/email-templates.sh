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
        local port=$(docker port "$container" 2>/dev/null | grep -oP '\d+:\d+' | head -1 || echo "-")
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
        containers_info="${containers_info}- ${container} (port ${port}, status: ${status})\n"
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
        local cert_info=$(sudo certbot certificates 2>/dev/null | grep -A 15 "Certificate Name: ${domain}")
        local domains=$(echo "$cert_info" | grep "Domains:" | sed 's/.*Domains: //')
        local expiry_date=$(echo "$cert_info" | grep "Expiry Date:" | awk '{print $3}')

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
        internal_url="Internal URL: https://${DOMAIN_INTERNAL}\n"
    fi

    # Subject (clean text, no emojis)
    export EMAIL_SUBJECT="Deployment Successful: $app_display_name"

    # Plain text body (NO color codes, NO emojis - clean TXT mode)
    # Strip any ANSI color codes that might be in the data
    local clean_ssl_info=$(echo -e "$ssl_info" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/✓/Success/g' | sed 's/✗/FAILED/g')
    local clean_containers_info=$(echo -e "$containers_info" | sed 's/\x1b\[[0-9;]*m//g')
    local clean_workers_info=$(echo -e "$workers_info" | sed 's/\x1b\[[0-9;]*m//g')
    local clean_internal_url=$(echo -e "$internal_url" | sed 's/\x1b\[[0-9;]*m//g')

    export EMAIL_TEXT_BODY=$(cat << EOF
Deployment Successful
All Containers Replaced

From: WebET Data Center

APPLICATION
Name: $app_display_name
Type: Rails API
App ID: $app_name
Git Commit: $git_commit
Image Tag: $image_tag

DEPLOYMENT STATUS
Status: SUCCESS
Timestamp: $deployment_time
Migrations: $migrations_run

AVAILABILITY
Primary URL: https://$domain
${clean_internal_url}Health Check: https://$domain/up

${clean_ssl_info}WEB CONTAINERS
Count: ${#containers[@]} instances
Containers:
$(echo -e "$clean_containers_info")
${clean_workers_info}${image_backup_info}${db_backup_info}USEFUL COMMANDS
Deploy: cd ~/DevOps/apps/${app_name} && ./deploy.sh
Rails console: ~/apps/${app_name}/console.sh
Check health: curl https://${domain}/up
Scale to N: cd ~/DevOps/apps/${app_name} && ./deploy.sh scale N
Restart: cd ~/DevOps/apps/${app_name} && ./deploy.sh restart
Rollback: cd ~/DevOps/apps/${app_name} && ./deploy.sh rollback
Stop: cd ~/DevOps/apps/${app_name} && ./deploy.sh stop

NAVIGATION
Config dir: cd ~/DevOps/apps/${app_name}
Deployed app: cd ~/apps/${app_name}
Quick link: cd ~/apps/${app_name}/config

LOGS
All logs: tail -f ~/apps/${app_name}/logs/production.log
Sidekiq only: tail -f ~/apps/${app_name}/logs/production.log | grep Sidekiq
Container logs: docker logs ${app_name}_web_1 -f
Inside container: docker exec ${app_name}_web_1 tail -f /app/log/production.log

Deployed on $deployment_time

This is an automated notification from the CheaperForDrug deployment system.
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
Deployment Starting

From: WebET Data Center

APPLICATION
Name: $app_display_name
Type: Rails API
App ID: $app_name
Git Commit: $git_commit
Domain: $domain

DEPLOYMENT STATUS
Status: IN PROGRESS
Started: $deployment_time
Server: $server_hostname

AVAILABILITY
Primary URL: https://$domain
Health Check: https://$domain/up

NEXT STEPS
- Pulling latest code from repository
- Building Docker image
- Running database migrations (if configured)
- Performing rolling restart of containers
- Setting up SSL certificates (if needed)

MONITORING
You will receive another email when the deployment completes or fails.

Started on $deployment_time
This is an automated notification from the CheaperForDrug deployment system.
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
Deployment Failed
ACTION REQUIRED

From: WebET Data Center

Application: $app_display_name
Server: $server_hostname
Time: $deployment_time

ERROR DETAILS
$clean_error_message

RECOMMENDED ACTIONS
1. Check the deployment logs for detailed error information
2. Verify that all prerequisites are met (database, Redis, etc.)
3. Check if there are any configuration issues
4. Review recent code changes that may have caused the failure

USEFUL COMMANDS
View logs: docker logs ${app_name}_web_1 -f
Check status: cd ~/DevOps/apps/${app_name} && ./deploy.sh status
Check health: curl https://${DOMAIN:-$app_name}/up

Failed on $deployment_time

This is an automated notification from the CheaperForDrug deployment system.
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
