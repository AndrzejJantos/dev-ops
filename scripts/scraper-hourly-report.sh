#!/bin/bash

# Scraper Hourly Activity Report
# Location: /home/andrzej/DevOps/scripts/scraper-hourly-report.sh
#
# Sends hourly email report with:
# - Number of products scraped in the last hour
# - List of URLs that were scraped
#
# Cron setup (every hour at minute 0):
#   0 * * * * /home/andrzej/DevOps/scripts/scraper-hourly-report.sh >> /var/log/scraper-hourly-report.log 2>&1

set -e

# Configuration
LOG_FILE="/home/andrzej/apps/cheaperfordrug-scraper/logs/poland-product-workers.log"
HOURS_BACK=1

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
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

# Calculate time threshold (1 hour ago in ISO format)
get_time_threshold() {
    date -d "-${HOURS_BACK} hour" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || \
    date -v-${HOURS_BACK}H '+%Y-%m-%dT%H:%M:%S' 2>/dev/null
}

# Extract scraping activity from logs
analyze_logs() {
    local threshold="$1"
    local log_file="$2"

    if [ ! -f "$log_file" ]; then
        echo "Log file not found: $log_file"
        return 1
    fi

    # Get logs from the last hour
    # Filter by timestamp >= threshold
    awk -v threshold="$threshold" '
    BEGIN {
        completed = 0
        updated = 0
    }

    # Match timestamp at start of line
    /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}/ {
        timestamp = substr($1, 1, 19)
        if (timestamp >= threshold) {
            line = $0

            # Count completed scrapes
            if (line ~ /completed successfully/) {
                completed++
            }

            # Count drug updates
            if (line ~ /Drug updated successfully/) {
                updated++
            }
        }
    }

    # Extract URLs from "link": lines within time range
    /"link":/ {
        if (timestamp >= threshold) {
            match($0, /"link": "([^"]+)"/, arr)
            if (arr[1] != "") {
                urls[arr[1]]++
            }
        }
    }

    END {
        print "COMPLETED:" completed
        print "UPDATED:" updated
        print "URLS_START"
        for (url in urls) {
            print url "|" urls[url]
        }
        print "URLS_END"
    }
    ' "$log_file"
}

# Generate report
generate_report() {
    local threshold=$(get_time_threshold)
    local now=$(date '+%Y-%m-%d %H:%M:%S')
    local hour_ago=$(date -d "-1 hour" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v-1H '+%Y-%m-%d %H:%M:%S')

    log_info "Generating hourly scraper report..."
    log_info "Time range: $hour_ago to $now"

    # Analyze logs
    local analysis=$(analyze_logs "$threshold" "$LOG_FILE")

    # Parse results
    local completed=$(echo "$analysis" | grep "^COMPLETED:" | cut -d: -f2)
    local updated=$(echo "$analysis" | grep "^UPDATED:" | cut -d: -f2)

    # Extract URLs
    local urls=$(echo "$analysis" | sed -n '/^URLS_START$/,/^URLS_END$/p' | grep -v "^URLS_" | sort -t'|' -k2 -rn | head -100)
    local url_count=$(echo "$urls" | grep -c "." || echo 0)

    # Build report
    local subject="[Scraper Report] ${updated:-0} products updated ($(date '+%Y-%m-%d %H:00'))"

    local body="Hourly Scraper Activity Report
================================

Time Period: $hour_ago to $now
Server: $(hostname)

Summary
-------
Products Updated: ${updated:-0}
Scrape Jobs Completed: ${completed:-0}
Unique URLs Scraped: ${url_count:-0}

"

    if [ -n "$urls" ] && [ "$url_count" -gt 0 ]; then
        body="${body}URLs Scraped (top 100 by frequency)
-------------------------------------
"
        # Format URLs with count
        while IFS='|' read -r url count; do
            if [ -n "$url" ]; then
                body="${body}${count}x ${url}
"
            fi
        done <<< "$urls"
    else
        body="${body}No URLs scraped in this period.
"
    fi

    body="${body}
---
Report generated at $(date)
"

    echo "$subject"
    echo "---"
    echo "$body"

    # Send email
    if [ "$EMAIL_AVAILABLE" = true ] && [ -n "$SENDGRID_API_KEY" ]; then
        local from="${DEPLOYMENT_EMAIL_FROM:-biuro@webet.pl}"
        local to="${DEPLOYMENT_EMAIL_TO:-andrzej@webet.pl}"

        log_info "Sending report email..."

        if send_email_via_sendgrid "$from" "$to" "$subject" "$body"; then
            log_info "Report email sent successfully"
        else
            log_warn "Failed to send report email"
        fi
    else
        log_warn "Email not available, report printed to console only"
    fi
}

# Main execution
main() {
    log_info "=== Scraper Hourly Report ==="
    generate_report
    log_info "=== Report Complete ==="
}

main "$@"
