#!/bin/bash

# Email Templates for Deployment Notifications
# Location: /home/andrzej/DevOps/common/email-templates.sh
#
# This module provides email templates (title, message, HTML) for various notifications
# Easy to add new notification types - just create new generate_*_email functions
#
# Usage:
#   source email-templates.sh
#   generate_deployment_success_email <params...>
#   generate_deployment_failure_email <params...>
#
# Each function returns a structured result via exported variables:
#   EMAIL_SUBJECT, EMAIL_TEXT_BODY, EMAIL_HTML_BODY

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
#   Sets EMAIL_SUBJECT, EMAIL_TEXT_BODY, EMAIL_HTML_BODY variables
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
        containers_info="${containers_info}  - ${container} (port ${port}, status: ${status})\n"
    done

    # Collect worker information
    local workers_info=""
    local worker_containers=($(docker ps --filter "name=${app_name}_worker" --format "{{.Names}}" 2>/dev/null))
    if [ ${#worker_containers[@]} -gt 0 ]; then
        workers_info="WORKER CONTAINERS:\n  Count: ${#worker_containers[@]} instances\n"
        for worker in "${worker_containers[@]}"; do
            local status=$(docker inspect -f '{{.State.Status}}' "$worker" 2>/dev/null)
            workers_info="${workers_info}  - ${worker} (status: ${status})\n"
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

            ssl_info="SSL CERTIFICATE:\n  Status: Active\n  Domains: ${domains}\n  Expires: ${expiry_date}\n  Validity: ${days_left} days remaining\n  Certificate: /etc/letsencrypt/live/${domain}/\n"

            if [ -n "${SSL_SETUP_STATUS:-}" ]; then
                case "$SSL_SETUP_STATUS" in
                    success) ssl_info="${ssl_info}  Last Setup: ✓ Success\n" ;;
                    failed) ssl_info="${ssl_info}  Last Setup: ✗ FAILED\n" ;;
                esac
            fi
            ssl_info="${ssl_info}\n"
        fi
    else
        ssl_info="SSL CERTIFICATE:\n  Status: Not configured\n\n"
    fi

    # Collect image backup information
    local image_backup_info=""
    if [ -d "${IMAGE_BACKUP_DIR:-}" ]; then
        local backup_count=$(ls -1 "${IMAGE_BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        image_backup_info="IMAGE BACKUPS:\n  Available: ${backup_count} backups\n  Location: ${IMAGE_BACKUP_DIR}\n  Latest: ${IMAGE_BACKUP_DIR}/${app_name}_${image_tag}.tar.gz\n\n"
    fi

    # Collect database backup information
    local db_backup_info=""
    if [ -d "${BACKUP_DIR:-}" ]; then
        local db_backup_count=$(ls -1 ${BACKUP_DIR}/*.sql.gz 2>/dev/null | wc -l | tr -d ' ')
        local latest_db_backup=$(ls -t ${BACKUP_DIR}/*.sql.gz 2>/dev/null | head -1 | xargs -r basename)
        db_backup_info="DATABASE:\n  Name: ${DB_NAME:-N/A}\n  Available Backups: ${db_backup_count}\n  Latest Backup: ${latest_db_backup}\n  Backup Location: ${BACKUP_DIR}\n\n"
    fi

    # Collect internal domain info if exists
    local internal_url=""
    if [ -n "${DOMAIN_INTERNAL:-}" ]; then
        internal_url="  Internal URL: https://${DOMAIN_INTERNAL}\n"
    fi

    # Subject
    export EMAIL_SUBJECT="✓ Deployment Successful: $app_display_name"

    # Plain text body
    export EMAIL_TEXT_BODY=$(cat << EOF
================================================================================
                     DEPLOYMENT SUMMARY
================================================================================

APPLICATION:
  Name: $app_display_name
  Type: Rails API
  App ID: $app_name
  Git Commit: $git_commit
  Image Tag: $image_tag

DEPLOYMENT STATUS:
  Status: SUCCESS
  Timestamp: $deployment_time
  Migrations: $migrations_run

AVAILABILITY:
  Primary URL: https://$domain
${internal_url}  Health Check: https://$domain/up

${ssl_info}WEB CONTAINERS:
  Count: ${#containers[@]} instances
  Containers:
$(echo -e "$containers_info")
${workers_info}${image_backup_info}${db_backup_info}USEFUL COMMANDS:
  Deploy:           cd ~/DevOps/apps/${app_name} && ./deploy.sh
  Rails console:    ~/apps/${app_name}/console.sh
  Check health:     curl https://${domain}/up
  Scale to N:       cd ~/DevOps/apps/${app_name} && ./deploy.sh scale N
  Restart:          cd ~/DevOps/apps/${app_name} && ./deploy.sh restart
  Rollback:         cd ~/DevOps/apps/${app_name} && ./deploy.sh rollback
  Stop:             cd ~/DevOps/apps/${app_name} && ./deploy.sh stop

NAVIGATION:
  Config dir:       cd ~/DevOps/apps/${app_name}
  Deployed app:     cd ~/apps/${app_name}
  Quick link:       cd ~/apps/${app_name}/config (→ config dir)

LOGS (persisted on host at ~/apps/${app_name}/logs/):
  All logs:         tail -f ~/apps/${app_name}/logs/production.log
  Sidekiq only:     tail -f ~/apps/${app_name}/logs/production.log | grep Sidekiq
  Container logs:   docker logs ${app_name}_web_1 -f
  Inside container: docker exec ${app_name}_web_1 tail -f /app/log/production.log

================================================================================

Deployed on $deployment_time
This is an automated notification from the CheaperForDrug deployment system.
EOF
)

    # HTML body - comprehensive version with all deployment details
    export EMAIL_HTML_BODY=$(cat << 'EOF_HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; background: #f8f9fa; }
        .container { background: white; margin: 20px 0; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .header h1 { margin: 0; font-size: 24px; }
        .success-badge { background: #10b981; color: white; padding: 8px 16px; border-radius: 20px; display: inline-block; margin: 10px 0; font-weight: bold; }
        .content { padding: 30px 20px; }
        .section { margin-bottom: 25px; }
        .section h2 { color: #667eea; margin: 0 0 15px 0; font-size: 18px; border-bottom: 2px solid #667eea; padding-bottom: 8px; }
        .detail-grid { display: grid; grid-template-columns: auto 1fr; gap: 10px; }
        .detail-label { font-weight: bold; color: #6b7280; }
        .detail-value { color: #111827; }
        .code { background: #f3f4f6; padding: 4px 8px; border-radius: 4px; font-family: monospace; font-size: 13px; display: inline-block; }
        .link { color: #667eea; text-decoration: none; }
        .link:hover { text-decoration: underline; }
        .command-list { background: #f8f9fa; border-left: 4px solid #667eea; padding: 15px; margin: 10px 0; }
        .command-list .command { font-family: monospace; font-size: 13px; margin: 5px 0; }
        .footer { background: #f3f4f6; padding: 20px; text-align: center; font-size: 12px; color: #6b7280; border-radius: 0 0 8px 8px; }
        ul { margin: 5px 0; padding-left: 20px; }
        li { margin: 3px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Deployment Successful</h1>
            <div class="success-badge">✓ All Containers Replaced</div>
        </div>

        <div class="content">
            <div class="section">
                <h2>APPLICATION</h2>
                <div class="detail-grid">
                    <span class="detail-label">Name:</span>
                    <span class="detail-value"><strong>{{APP_DISPLAY_NAME}}</strong></span>
                    <span class="detail-label">Type:</span>
                    <span class="detail-value">Rails API</span>
                    <span class="detail-label">App ID:</span>
                    <span class="detail-value"><span class="code">{{APP_NAME}}</span></span>
                    <span class="detail-label">Git Commit:</span>
                    <span class="detail-value"><span class="code">{{GIT_COMMIT}}</span></span>
                    <span class="detail-label">Image Tag:</span>
                    <span class="detail-value"><span class="code">{{IMAGE_TAG}}</span></span>
                </div>
            </div>

            <div class="section">
                <h2>DEPLOYMENT STATUS</h2>
                <div class="detail-grid">
                    <span class="detail-label">Status:</span>
                    <span class="detail-value" style="color: #10b981;"><strong>SUCCESS</strong></span>
                    <span class="detail-label">Timestamp:</span>
                    <span class="detail-value">{{DEPLOYMENT_TIME}}</span>
                    <span class="detail-label">Migrations:</span>
                    <span class="detail-value">{{MIGRATIONS_RUN}}</span>
                </div>
            </div>

            <div class="section">
                <h2>AVAILABILITY</h2>
                <div class="detail-grid">
                    <span class="detail-label">Primary URL:</span>
                    <span class="detail-value"><a href="https://{{DOMAIN}}" class="link">https://{{DOMAIN}}</a></span>
                    {{INTERNAL_URL_ROW}}
                    <span class="detail-label">Health Check:</span>
                    <span class="detail-value"><a href="https://{{DOMAIN}}/up" class="link">https://{{DOMAIN}}/up</a></span>
                </div>
            </div>

            {{SSL_SECTION}}

            <div class="section">
                <h2>WEB CONTAINERS</h2>
                <div class="detail-grid">
                    <span class="detail-label">Count:</span>
                    <span class="detail-value">{{SCALE}} instances</span>
                    <span class="detail-label">Containers:</span>
                    <span class="detail-value">{{CONTAINERS_LIST}}</span>
                </div>
            </div>

            {{WORKERS_SECTION}}

            {{IMAGE_BACKUP_SECTION}}

            {{DB_BACKUP_SECTION}}

            <div class="section">
                <h2>USEFUL COMMANDS</h2>
                <div class="command-list">
                    <div class="command">Deploy: cd ~/DevOps/apps/{{APP_NAME}} && ./deploy.sh</div>
                    <div class="command">Rails console: ~/apps/{{APP_NAME}}/console.sh</div>
                    <div class="command">Check health: curl https://{{DOMAIN}}/up</div>
                    <div class="command">Scale to N: cd ~/DevOps/apps/{{APP_NAME}} && ./deploy.sh scale N</div>
                    <div class="command">Restart: cd ~/DevOps/apps/{{APP_NAME}} && ./deploy.sh restart</div>
                    <div class="command">Rollback: cd ~/DevOps/apps/{{APP_NAME}} && ./deploy.sh rollback</div>
                    <div class="command">Stop: cd ~/DevOps/apps/{{APP_NAME}} && ./deploy.sh stop</div>
                </div>
            </div>

            <div class="section">
                <h2>NAVIGATION</h2>
                <div class="command-list">
                    <div class="command">Config dir: cd ~/DevOps/apps/{{APP_NAME}}</div>
                    <div class="command">Deployed app: cd ~/apps/{{APP_NAME}}</div>
                    <div class="command">Quick link: cd ~/apps/{{APP_NAME}}/config</div>
                </div>
            </div>

            <div class="section">
                <h2>LOGS</h2>
                <div class="command-list">
                    <div class="command">All logs: tail -f ~/apps/{{APP_NAME}}/logs/production.log</div>
                    <div class="command">Sidekiq only: tail -f ~/apps/{{APP_NAME}}/logs/production.log | grep Sidekiq</div>
                    <div class="command">Container logs: docker logs {{APP_NAME}}_web_1 -f</div>
                    <div class="command">Inside container: docker exec {{APP_NAME}}_web_1 tail -f /app/log/production.log</div>
                </div>
            </div>
        </div>

        <div class="footer">
            <p>Deployed on {{DEPLOYMENT_TIME}}</p>
            <p>This is an automated notification from the CheaperForDrug deployment system.</p>
        </div>
    </div>
</body>
</html>
EOF_HTML
)

    # Build dynamic sections for HTML
    local html_internal_url_row=""
    if [ -n "${DOMAIN_INTERNAL:-}" ]; then
        html_internal_url_row="<span class=\"detail-label\">Internal URL:</span><span class=\"detail-value\"><a href=\"https://${DOMAIN_INTERNAL}\" class=\"link\">https://${DOMAIN_INTERNAL}</a></span>"
    fi

    local html_ssl_section=""
    if [ -n "$ssl_info" ]; then
        local ssl_html=$(echo -e "$ssl_info" | sed 's/^/                    /')
        html_ssl_section="<div class=\"section\"><h2>SSL CERTIFICATE</h2><pre style=\"margin: 0; white-space: pre-wrap; font-size: 13px;\">${ssl_html}</pre></div>"
    fi

    local html_containers_list=$(echo -e "$containers_info" | sed 's/^/<br>/' | tr -d '\n')

    local html_workers_section=""
    if [ ${#worker_containers[@]} -gt 0 ]; then
        local workers_html=$(echo -e "$workers_info" | sed 's/^/                    /')
        html_workers_section="<div class=\"section\"><h2>WORKER CONTAINERS</h2><pre style=\"margin: 0; white-space: pre-wrap; font-size: 13px;\">${workers_html}</pre></div>"
    fi

    local html_image_backup_section=""
    if [ -d "${IMAGE_BACKUP_DIR:-}" ]; then
        local backup_count=$(ls -1 "${IMAGE_BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        html_image_backup_section="<div class=\"section\"><h2>IMAGE BACKUPS</h2><div class=\"detail-grid\"><span class=\"detail-label\">Available:</span><span class=\"detail-value\">${backup_count} backups</span><span class=\"detail-label\">Location:</span><span class=\"detail-value\"><span class=\"code\">${IMAGE_BACKUP_DIR}</span></span><span class=\"detail-label\">Latest:</span><span class=\"detail-value\"><span class=\"code\">${IMAGE_BACKUP_DIR}/${app_name}_${image_tag}.tar.gz</span></span></div></div>"
    fi

    local html_db_backup_section=""
    if [ -d "${BACKUP_DIR:-}" ]; then
        local db_backup_count=$(ls -1 ${BACKUP_DIR}/*.sql.gz 2>/dev/null | wc -l | tr -d ' ')
        local latest_db_backup=$(ls -t ${BACKUP_DIR}/*.sql.gz 2>/dev/null | head -1 | xargs -r basename)
        html_db_backup_section="<div class=\"section\"><h2>DATABASE</h2><div class=\"detail-grid\"><span class=\"detail-label\">Name:</span><span class=\"detail-value\"><span class=\"code\">${DB_NAME:-N/A}</span></span><span class=\"detail-label\">Available Backups:</span><span class=\"detail-value\">${db_backup_count}</span><span class=\"detail-label\">Latest Backup:</span><span class=\"detail-value\"><span class=\"code\">${latest_db_backup}</span></span><span class=\"detail-label\">Backup Location:</span><span class=\"detail-value\"><span class=\"code\">${BACKUP_DIR}</span></span></div></div>"
    fi

    # Replace template placeholders
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{APP_NAME\}\}/$app_name}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{APP_DISPLAY_NAME\}\}/$app_display_name}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{DOMAIN\}\}/$domain}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{SCALE\}\}/$scale}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{IMAGE_TAG\}\}/$image_tag}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{MIGRATIONS_RUN\}\}/$migrations_run}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{GIT_COMMIT\}\}/$git_commit}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{DEPLOYMENT_TIME\}\}/$deployment_time}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{SERVER_HOSTNAME\}\}/$server_hostname}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{INTERNAL_URL_ROW\}\}/$html_internal_url_row}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{SSL_SECTION\}\}/$html_ssl_section}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{CONTAINERS_LIST\}\}/$html_containers_list}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{WORKERS_SECTION\}\}/$html_workers_section}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{IMAGE_BACKUP_SECTION\}\}/$html_image_backup_section}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{DB_BACKUP_SECTION\}\}/$html_db_backup_section}"
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
#   Sets EMAIL_SUBJECT, EMAIL_TEXT_BODY, EMAIL_HTML_BODY variables
generate_deployment_failure_email() {
    local app_name="$1"
    local app_display_name="$2"
    local error_message="$3"

    local deployment_time="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    local server_hostname="$(hostname)"

    # Subject
    export EMAIL_SUBJECT="✗ Deployment Failed: $app_display_name"

    # Plain text body
    export EMAIL_TEXT_BODY=$(cat << EOF
DEPLOYMENT FAILED
=================

⚠️ ACTION REQUIRED ⚠️

Application: $app_display_name
Server: $server_hostname
Time: $deployment_time

ERROR DETAILS
-------------
$error_message

RECOMMENDED ACTIONS
-------------------
1. Check the deployment logs for detailed error information
2. Verify that all prerequisites are met (database, Redis, etc.)
3. Check if there are any configuration issues
4. Review recent code changes that may have caused the failure

---
Failed on $deployment_time
This is an automated notification from the CheaperForDrug deployment system.
EOF
)

    # HTML body
    export EMAIL_HTML_BODY=$(cat << 'EOF_HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); color: white; padding: 30px 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .header h1 { margin: 0; font-size: 24px; }
        .failure-badge { background: #dc2626; color: white; padding: 8px 16px; border-radius: 20px; display: inline-block; margin: 10px 0; font-weight: bold; }
        .content { background: #f8f9fa; padding: 30px 20px; }
        .details { background: white; border-radius: 8px; padding: 20px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .details h2 { color: #ef4444; margin-top: 0; font-size: 18px; border-bottom: 2px solid #ef4444; padding-bottom: 10px; }
        .error-box { background: #fef2f2; border-left: 4px solid #ef4444; padding: 15px; margin: 15px 0; border-radius: 4px; }
        .code { background: #f3f4f6; padding: 2px 6px; border-radius: 4px; font-family: monospace; font-size: 14px; }
        .footer { background: #f3f4f6; padding: 20px; text-align: center; font-size: 12px; color: #6b7280; border-radius: 0 0 8px 8px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>⚠️ Deployment Failed</h1>
        <div class="failure-badge">✗ Action Required</div>
    </div>

    <div class="content">
        <div class="details">
            <h2>Application Information</h2>
            <p><strong>Application:</strong> {{APP_DISPLAY_NAME}}</p>
            <p><strong>Server:</strong> <span class="code">{{SERVER_HOSTNAME}}</span></p>
            <p><strong>Time:</strong> {{DEPLOYMENT_TIME}}</p>
        </div>

        <div class="details">
            <h2>Error Details</h2>
            <div class="error-box">
                <pre style="white-space: pre-wrap; margin: 0; font-family: monospace;">{{ERROR_MESSAGE}}</pre>
            </div>
        </div>

        <div class="details">
            <h2>Recommended Actions</h2>
            <ul>
                <li>Check the deployment logs for detailed error information</li>
                <li>Verify that all prerequisites are met (database, Redis, etc.)</li>
                <li>Check if there are any configuration issues</li>
                <li>Review recent code changes that may have caused the failure</li>
            </ul>
        </div>
    </div>

    <div class="footer">
        <p>Failed on {{DEPLOYMENT_TIME}}</p>
        <p>This is an automated notification from the CheaperForDrug deployment system.</p>
    </div>
</body>
</html>
EOF_HTML
)

    # Replace template placeholders
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{APP_DISPLAY_NAME\}\}/$app_display_name}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{SERVER_HOSTNAME\}\}/$server_hostname}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{DEPLOYMENT_TIME\}\}/$deployment_time}"
    EMAIL_HTML_BODY="${EMAIL_HTML_BODY//\{\{ERROR_MESSAGE\}\}/$error_message}"
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
