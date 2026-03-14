#!/bin/bash

# Kill Zombie Scraper Processes
# Runs via cron every 15 minutes on hetzner-andrzej
# Finds orphaned node processes in scraper containers and kills them
# Sends email notification when zombies are found and killed
#
# Usage: ./kill-zombie-scrapers.sh
# Cron:  */15 * * * * /home/andrzej/DevOps/scripts/kill-zombie-scrapers.sh >> /var/log/zombie-killer.log 2>&1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(dirname "$SCRIPT_DIR")"

# Load email support
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"; }
log_warning() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"; }

source "$DEVOPS_DIR/common/email-config.sh" 2>/dev/null || true
source "$DEVOPS_DIR/common/sendgrid-api.sh" 2>/dev/null || true

# Find all scraper VPN containers
CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null | grep 'scraper-vpn-' || true)

if [ -z "$CONTAINERS" ]; then
    exit 0
fi

total_killed=0
report=""

for container in $CONTAINERS; do
    # Check if the scraper manager is running (npm run scrapers:*)
    manager_running=$(docker exec "$container" bash -c "pgrep -f 'node scripts/manager' 2>/dev/null | head -1" 2>/dev/null || true)

    if [ -n "$manager_running" ]; then
        # Manager is running — scrapers are active, skip this container
        continue
    fi

    # No manager running — any remaining node processes are zombies
    zombie_pids=$(docker exec "$container" bash -c "ps aux 2>/dev/null | grep 'node.*scraper' | grep -v grep | awk '{print \$2}'" 2>/dev/null || true)
    zombie_count=$(echo "$zombie_pids" | grep -c '[0-9]' 2>/dev/null || echo 0)

    if [ "$zombie_count" -gt 0 ]; then
        log_warning "Found $zombie_count zombie processes in $container"

        # Get zombie details before killing
        zombie_details=$(docker exec "$container" bash -c "ps aux 2>/dev/null | grep 'node.*scraper' | grep -v grep | awk '{print \$11}' | sort | uniq -c | sort -rn" 2>/dev/null || true)

        # Kill them
        docker exec "$container" bash -c "kill -9 \$(ps aux | grep 'node.*scraper' | grep -v grep | awk '{print \$2}') 2>/dev/null" 2>/dev/null || true
        sleep 2

        # Verify
        remaining=$(docker exec "$container" bash -c "ps aux 2>/dev/null | grep 'node.*scraper' | grep -v grep | wc -l" 2>/dev/null || echo 0)
        if [ "$remaining" -gt 0 ]; then
            docker exec "$container" bash -c "kill -9 \$(ps aux | grep 'node.*scraper' | grep -v grep | awk '{print \$2}') 2>/dev/null" 2>/dev/null || true
        fi

        total_killed=$((total_killed + zombie_count))
        report="${report}
Container: ${container}
  Killed: ${zombie_count} zombie processes
  Details:
${zombie_details}
"
        log_success "Killed $zombie_count zombies in $container"
    fi
done

# Send email if any zombies were killed
if [ "$total_killed" -gt 0 ]; then
    subject="[Scraper] Killed $total_killed zombie processes"
    body="Zombie Scraper Cleanup Report
$(date '+%Y-%m-%d %H:%M:%S')

Total killed: $total_killed
$report
---
This is an automated message from kill-zombie-scrapers.sh cron job."

    if declare -f send_email_via_sendgrid >/dev/null 2>&1 && [ -n "${SENDGRID_API_KEY:-}" ]; then
        send_email_via_sendgrid "$EMAIL_FROM" "$EMAIL_TO" "$subject" "$body" 2>/dev/null || true
        log_info "Email notification sent"
    else
        log_warning "Email not configured — skipping notification"
    fi
fi
