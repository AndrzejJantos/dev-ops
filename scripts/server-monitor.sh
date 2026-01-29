#!/bin/bash

# Server Resource Monitor with Email Alerts
# Location: /home/andrzej/DevOps/scripts/server-monitor.sh
#
# Monitors:
# - CPU usage > 50% for 5+ minutes → email alert
# - Zombie processes > 100 → email alert
#
# Usage:
#   ./server-monitor.sh         # Run once
#   ./server-monitor.sh --cron  # Cron-friendly (uses state file for timing)
#
# Cron setup (every minute):
#   * * * * * /home/andrzej/DevOps/scripts/server-monitor.sh --cron

set -e

# Configuration
CPU_THRESHOLD=50           # Alert if CPU > 50%
CPU_ALERT_DURATION=300     # Must exceed threshold for 5 minutes (300 seconds)
ZOMBIE_THRESHOLD=100       # Alert if zombies > 100
STATE_DIR="/tmp/server-monitor"
STATE_FILE="$STATE_DIR/cpu_high_since"
ALERT_COOLDOWN_FILE="$STATE_DIR/last_alert"
ALERT_COOLDOWN=1800        # Don't send same alert more than once per 30 minutes

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Get script directory for loading modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(dirname "$SCRIPT_DIR")"

# Load email notification if available
EMAIL_AVAILABLE=false
if [ -f "$DEVOPS_DIR/common/email-config.sh" ]; then
    source "$DEVOPS_DIR/common/email-config.sh" 2>/dev/null || true
fi
if [ -f "$DEVOPS_DIR/common/sendgrid-api.sh" ]; then
    source "$DEVOPS_DIR/common/sendgrid-api.sh" 2>/dev/null && EMAIL_AVAILABLE=true
fi

# Colors for console output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get current CPU usage (average across all cores)
get_cpu_usage() {
    # Use /proc/stat for accurate CPU measurement
    local cpu_line=$(head -1 /proc/stat)
    local cpu_values=($cpu_line)

    # cpu user nice system idle iowait irq softirq steal guest guest_nice
    local user=${cpu_values[1]}
    local nice=${cpu_values[2]}
    local system=${cpu_values[3]}
    local idle=${cpu_values[4]}
    local iowait=${cpu_values[5]}

    local total=$((user + nice + system + idle + iowait))
    local active=$((user + nice + system))

    # Read previous values
    local prev_file="$STATE_DIR/prev_cpu"
    if [ -f "$prev_file" ]; then
        local prev_total=$(cut -d' ' -f1 "$prev_file")
        local prev_active=$(cut -d' ' -f2 "$prev_file")

        local diff_total=$((total - prev_total))
        local diff_active=$((active - prev_active))

        if [ $diff_total -gt 0 ]; then
            echo $((diff_active * 100 / diff_total))
        else
            echo 0
        fi
    else
        echo 0
    fi

    # Save current values
    echo "$total $active" > "$prev_file"
}

# Get zombie process count
get_zombie_count() {
    ps aux 2>/dev/null | grep -c ' Z ' || echo 0
}

# Get load average
get_load_average() {
    uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $1}' | tr -d ' '
}

# Check if we can send alert (cooldown check)
can_send_alert() {
    local alert_type="$1"
    local cooldown_file="${ALERT_COOLDOWN_FILE}_${alert_type}"

    if [ -f "$cooldown_file" ]; then
        local last_alert=$(cat "$cooldown_file")
        local now=$(date +%s)
        local diff=$((now - last_alert))

        if [ $diff -lt $ALERT_COOLDOWN ]; then
            return 1  # Still in cooldown
        fi
    fi

    return 0  # Can send
}

# Mark alert as sent
mark_alert_sent() {
    local alert_type="$1"
    local cooldown_file="${ALERT_COOLDOWN_FILE}_${alert_type}"
    date +%s > "$cooldown_file"
}

# Send email alert
send_alert() {
    local subject="$1"
    local body="$2"
    local alert_type="$3"

    # Check cooldown
    if ! can_send_alert "$alert_type"; then
        log_info "Alert cooldown active for $alert_type, skipping email"
        return 0
    fi

    if [ "$EMAIL_AVAILABLE" = true ] && [ -n "$SENDGRID_API_KEY" ]; then
        local from="${DEPLOYMENT_EMAIL_FROM:-biuro@webet.pl}"
        local to="${DEPLOYMENT_EMAIL_TO:-andrzej@webet.pl}"

        log_warn "Sending alert email: $subject"

        if send_email_via_sendgrid "$from" "$to" "$subject" "$body"; then
            mark_alert_sent "$alert_type"
            log_info "Alert email sent successfully"
        else
            log_error "Failed to send alert email"
        fi
    else
        log_warn "Email not available. Alert: $subject"
        echo "$body"
    fi
}

# Check CPU and trigger alert if needed
check_cpu() {
    local cpu_usage=$(get_cpu_usage)
    local load_avg=$(get_load_average)
    local now=$(date +%s)

    log_info "CPU Usage: ${cpu_usage}% | Load Average: ${load_avg}"

    if [ "$cpu_usage" -gt "$CPU_THRESHOLD" ]; then
        # CPU is high
        if [ -f "$STATE_FILE" ]; then
            local high_since=$(cat "$STATE_FILE")
            local duration=$((now - high_since))

            log_warn "CPU > ${CPU_THRESHOLD}% for ${duration}s (threshold: ${CPU_ALERT_DURATION}s)"

            if [ $duration -ge $CPU_ALERT_DURATION ]; then
                # Send alert
                local subject="[ALERT] Server CPU High: ${cpu_usage}% for $((duration / 60)) minutes"
                local body="Server Resource Alert

CPU Usage: ${cpu_usage}%
Load Average: ${load_avg}
Duration: $((duration / 60)) minutes
Threshold: ${CPU_THRESHOLD}%

Server: $(hostname)
Time: $(date)

Top CPU Processes:
$(ps aux --sort=-%cpu | head -6)

Recommended Actions:
1. SSH to server: ssh hetzner-andrzej
2. Check processes: htop
3. Check Docker: docker stats --no-stream
4. Kill runaway processes if needed

This alert will not repeat for 30 minutes."

                send_alert "$subject" "$body" "cpu_high"
            fi
        else
            # First time CPU is high
            echo "$now" > "$STATE_FILE"
            log_warn "CPU exceeded ${CPU_THRESHOLD}%, starting timer"
        fi
    else
        # CPU is normal
        if [ -f "$STATE_FILE" ]; then
            rm -f "$STATE_FILE"
            log_info "CPU returned to normal, timer reset"
        fi
    fi
}

# Check zombies and trigger alert if needed
check_zombies() {
    local zombie_count=$(get_zombie_count)

    log_info "Zombie Processes: ${zombie_count}"

    if [ "$zombie_count" -gt "$ZOMBIE_THRESHOLD" ]; then
        local subject="[ALERT] ${zombie_count} Zombie Processes Detected!"
        local body="Zombie Process Alert

Zombie Count: ${zombie_count}
Threshold: ${ZOMBIE_THRESHOLD}

Server: $(hostname)
Time: $(date)

Zombie processes indicate child processes not being reaped.
This is usually caused by scraper workers spawning Chrome browsers.

Zombie Processes:
$(ps aux | grep ' Z ' | head -20)

Parent Processes:
$(ps -eo ppid,pid,stat,cmd | grep ' Z ' | head -10)

Recommended Actions:
1. SSH to server: ssh hetzner-andrzej
2. Restart scraper workers: docker restart product-update-worker-poland-{1..10}
3. If workers have init: true, this shouldn't happen - check docker-compose

This alert will not repeat for 30 minutes."

        send_alert "$subject" "$body" "zombies"
    fi
}

# Main execution
main() {
    log_info "=== Server Monitor $(date) ==="

    check_cpu
    check_zombies

    log_info "=== Check Complete ==="
}

main "$@"
