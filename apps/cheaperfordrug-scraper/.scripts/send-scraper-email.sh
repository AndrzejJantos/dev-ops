#!/bin/bash

# ============================================================================
# Scraper Event Email Sender
# ============================================================================
# Sends email notifications for scraper start and finish events
#
# Usage:
#   ./send-scraper-email.sh start|finish
#
# Environment Variables:
#   SENDGRID_API_KEY - SendGrid API key (required)
#   COUNTRY          - Country code (poland/germany/czech) [optional]
#
# Returns:
#   0 - Email sent successfully
#   1 - Failed to send email
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURATION
# ============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${HOME}/apps/cheaperfordrug-scraper"
STATE_DIR="${APP_DIR}/state"

# Container names
CONTAINER_POLAND="cheaperfordrug-scraper-poland"
CONTAINER_GERMANY="cheaperfordrug-scraper-germany"
CONTAINER_CZECH="cheaperfordrug-scraper-czech"

# State files for tracking scraper sessions
STATE_FILE="${STATE_DIR}/scraper-session.state"
START_TIME_FILE="${STATE_DIR}/scraper-start-time.state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[SCRAPER-EMAIL]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SCRAPER-EMAIL]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[SCRAPER-EMAIL]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[SCRAPER-EMAIL]${NC} $1" >&2
}

# ============================================================================
# VALIDATION
# ============================================================================

validate_inputs() {
    # Check if event type is provided
    if [ -z "${1:-}" ]; then
        log_error "Event type is required"
        log_error "Usage: ./send-scraper-email.sh start|finish"
        return 1
    fi

    # Check if API key is set
    if [ -z "${SENDGRID_API_KEY:-}" ]; then
        log_warning "SENDGRID_API_KEY environment variable is not set"
        log_warning "Skipping email notification"
        return 1
    fi

    return 0
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get VPN status for a container
get_vpn_status() {
    local container_name="$1"
    local status

    if docker exec "${container_name}" nordvpn status 2>&1 | grep -q "Status: Connected"; then
        local vpn_country=$(docker exec "${container_name}" nordvpn status 2>/dev/null | grep "Country:" | awk '{print $2}' || echo "Unknown")
        local vpn_city=$(docker exec "${container_name}" nordvpn status 2>/dev/null | grep "City:" | awk '{print $2}' || echo "")
        echo "Connected to ${vpn_country} ${vpn_city}"
    else
        echo "Not connected"
    fi
}

# Count scrapers for a country
count_scrapers() {
    local country="$1"
    local scrapers_dir="${APP_DIR}/repo/scrapers/${country}"

    if [ -d "${scrapers_dir}" ]; then
        find "${scrapers_dir}" -name "*_scraper.js" -type f | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

# Get container status
is_container_running() {
    local container_name="$1"
    docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "${container_name}"
}

# Get next scheduled run
get_next_scheduled_run() {
    # Next Monday or Thursday at 7:00 AM
    local current_day=$(date +%u)  # 1=Monday, 4=Thursday, 7=Sunday
    local next_run_date

    if [ "${current_day}" -eq 1 ]; then
        # Monday - next run is Thursday
        next_run_date=$(date -v +3d +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || date -d "+3 days" +"%A, %B %d, %Y at 7:00 AM")
    elif [ "${current_day}" -lt 4 ]; then
        # Tuesday/Wednesday - next run is Thursday
        local days_until_thursday=$((4 - current_day))
        next_run_date=$(date -v +${days_until_thursday}d +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || date -d "+${days_until_thursday} days" +"%A, %B %d, %Y at 7:00 AM")
    elif [ "${current_day}" -eq 4 ]; then
        # Thursday - next run is Monday
        next_run_date=$(date -v +4d +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || date -d "+4 days" +"%A, %B %d, %Y at 7:00 AM")
    else
        # Friday/Saturday/Sunday - next run is Monday
        local days_until_monday=$((8 - current_day))
        next_run_date=$(date -v +${days_until_monday}d +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || date -d "+${days_until_monday} days" +"%A, %B %d, %Y at 7:00 AM")
    fi

    echo "${next_run_date}"
}

# Format duration
format_duration() {
    local duration_seconds="$1"

    if [ -z "${duration_seconds}" ] || [ "${duration_seconds}" -le 0 ]; then
        echo "N/A"
        return
    fi

    local hours=$((duration_seconds / 3600))
    local minutes=$(((duration_seconds % 3600) / 60))
    local seconds=$((duration_seconds % 60))

    if [ "${hours}" -gt 0 ]; then
        echo "${hours}h ${minutes}m ${seconds}s"
    elif [ "${minutes}" -gt 0 ]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${seconds}s"
    fi
}

# Count products in output files
count_products() {
    local country="$1"
    local outputs_dir="${APP_DIR}/outputs/${country}"
    local count=0

    if [ -d "${outputs_dir}" ]; then
        # Count lines in JSON files from today
        local today=$(date +%Y-%m-%d)
        count=$(find "${outputs_dir}" -name "*.json" -type f -newermt "${today}" -exec cat {} \; 2>/dev/null | grep -c '"' 2>/dev/null || echo "0")
    fi

    echo "${count}"
}

# Get scraper status from logs
get_scraper_status() {
    local country="$1"
    local logs_dir="${APP_DIR}/logs/${country}"

    if [ -d "${logs_dir}" ]; then
        # Check for errors in recent logs
        if grep -q "ERROR" "${logs_dir}/"*.log 2>/dev/null; then
            echo "Completed with errors"
        else
            echo "Success"
        fi
    else
        echo "Unknown"
    fi
}

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

# Save start time
save_start_time() {
    mkdir -p "${STATE_DIR}"
    date +%s > "${START_TIME_FILE}"
}

# Get session duration
get_session_duration() {
    if [ -f "${START_TIME_FILE}" ]; then
        local start_time=$(cat "${START_TIME_FILE}")
        local current_time=$(date +%s)
        echo $((current_time - start_time))
    else
        echo "0"
    fi
}

# ============================================================================
# EMAIL GENERATION
# ============================================================================

generate_start_email() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S %Z")
    local estimated_finish=$(date -v +45M +"%H:%M:%S" 2>/dev/null || date -d "+45 minutes" +"%H:%M:%S")
    local next_run=$(get_next_scheduled_run)

    # Get scraper counts
    local poland_count=$(count_scrapers "poland")
    local germany_count=$(count_scrapers "germany")
    local czech_count=$(count_scrapers "czech")
    local total_count=$((poland_count + germany_count + czech_count))

    # Get VPN status for each container
    local poland_vpn="Unknown"
    local germany_vpn="Unknown"
    local czech_vpn="Unknown"

    if is_container_running "${CONTAINER_POLAND}"; then
        poland_vpn=$(get_vpn_status "${CONTAINER_POLAND}")
    fi

    if is_container_running "${CONTAINER_GERMANY}"; then
        germany_vpn=$(get_vpn_status "${CONTAINER_GERMANY}")
    fi

    if is_container_running "${CONTAINER_CZECH}"; then
        czech_vpn=$(get_vpn_status "${CONTAINER_CZECH}")
    fi

    # Generate HTML
    cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
        }
        .header {
            background: linear-gradient(135deg, #3b82f6 0%, #1d4ed8 100%);
            color: white;
            padding: 30px;
            border-radius: 10px 10px 0 0;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 24px;
        }
        .status-badge {
            display: inline-block;
            background: #3b82f6;
            color: white;
            padding: 8px 16px;
            border-radius: 20px;
            font-weight: bold;
            margin-top: 10px;
        }
        .content {
            background: #f9fafb;
            padding: 30px;
            border-radius: 0 0 10px 10px;
        }
        .section {
            margin-bottom: 25px;
        }
        .section h2 {
            color: #3b82f6;
            font-size: 18px;
            margin-bottom: 10px;
            border-bottom: 2px solid #3b82f6;
            padding-bottom: 5px;
        }
        .info-grid {
            display: grid;
            gap: 10px;
        }
        .info-row {
            background: white;
            padding: 12px;
            border-radius: 5px;
            border-left: 4px solid #3b82f6;
        }
        .info-row strong {
            color: #3b82f6;
            display: inline-block;
            min-width: 120px;
        }
        .country-list {
            list-style: none;
            padding: 0;
        }
        .country-list li {
            background: white;
            padding: 12px;
            margin-bottom: 8px;
            border-radius: 5px;
            border-left: 4px solid #10b981;
        }
        .vpn-status {
            font-size: 14px;
            color: #6b7280;
            margin-top: 4px;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 2px solid #e5e7eb;
            font-size: 14px;
            color: #6b7280;
            text-align: center;
        }
        .highlight {
            background: #dbeafe;
            padding: 15px;
            border-radius: 5px;
            margin-top: 15px;
            border-left: 4px solid #3b82f6;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Scraping Session Started</h1>
        <div class="status-badge">IN PROGRESS</div>
    </div>

    <div class="content">
        <div class="section">
            <h2>Session Information</h2>
            <div class="info-grid">
                <div class="info-row">
                    <strong>Start Time:</strong> ${timestamp}
                </div>
                <div class="info-row">
                    <strong>Estimated Finish:</strong> ~${estimated_finish} (30-45 minutes)
                </div>
                <div class="info-row">
                    <strong>Total Scrapers:</strong> ${total_count}
                </div>
            </div>
        </div>

        <div class="section">
            <h2>Containers Starting</h2>
            <ul class="country-list">
                <li>
                    <strong>Poland:</strong> ${poland_count} scrapers
                    <div class="vpn-status">VPN: ${poland_vpn}</div>
                </li>
                <li>
                    <strong>Germany:</strong> ${germany_count} scraper(s)
                    <div class="vpn-status">VPN: ${germany_vpn}</div>
                </li>
                <li>
                    <strong>Czech Republic:</strong> ${czech_count} scraper(s)
                    <div class="vpn-status">VPN: ${czech_vpn}</div>
                </li>
            </ul>
        </div>

        <div class="highlight">
            <strong>What's Happening:</strong> All scraper containers are now executing their scheduled scraping tasks. Each scraper will collect drug pricing data from online pharmacies in their respective countries.
        </div>

        <div class="section">
            <h2>Next Scheduled Run</h2>
            <div class="info-row">
                ${next_run}
            </div>
        </div>
    </div>

    <div class="footer">
        <p>CheaperForDrug Scraper - Automated Scraping System</p>
        <p>You will receive a completion email when all scrapers finish.</p>
    </div>
</body>
</html>
EOF
}

generate_finish_email() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S %Z")
    local duration_seconds=$(get_session_duration)
    local duration=$(format_duration "${duration_seconds}")
    local next_run=$(get_next_scheduled_run)

    # Get scraper counts
    local poland_count=$(count_scrapers "poland")
    local germany_count=$(count_scrapers "germany")
    local czech_count=$(count_scrapers "czech")
    local total_count=$((poland_count + germany_count + czech_count))

    # Get product counts (approximate)
    local poland_products=$(count_products "poland")
    local germany_products=$(count_products "germany")
    local czech_products=$(count_products "czech")
    local total_products=$((poland_products + germany_products + czech_products))

    # Get status for each country
    local poland_status=$(get_scraper_status "poland")
    local germany_status=$(get_scraper_status "germany")
    local czech_status=$(get_scraper_status "czech")

    # Determine overall status
    local overall_status="SUCCESS"
    if [[ "${poland_status}" == *"error"* ]] || [[ "${germany_status}" == *"error"* ]] || [[ "${czech_status}" == *"error"* ]]; then
        overall_status="COMPLETED WITH ERRORS"
    fi

    # Set status icon and color
    local status_icon="✓"
    local status_color="#10b981"
    local header_gradient="linear-gradient(135deg, #10b981 0%, #059669 100%)"

    if [ "${overall_status}" = "COMPLETED WITH ERRORS" ]; then
        status_icon="⚠"
        status_color="#f59e0b"
        header_gradient="linear-gradient(135deg, #f59e0b 0%, #d97706 100%)"
    fi

    # Generate HTML
    cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
        }
        .header {
            background: ${header_gradient};
            color: white;
            padding: 30px;
            border-radius: 10px 10px 0 0;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 24px;
        }
        .status-badge {
            display: inline-block;
            background: rgba(0, 0, 0, 0.2);
            color: white;
            padding: 8px 16px;
            border-radius: 20px;
            font-weight: bold;
            margin-top: 10px;
        }
        .content {
            background: #f9fafb;
            padding: 30px;
            border-radius: 0 0 10px 10px;
        }
        .section {
            margin-bottom: 25px;
        }
        .section h2 {
            color: ${status_color};
            font-size: 18px;
            margin-bottom: 10px;
            border-bottom: 2px solid ${status_color};
            padding-bottom: 5px;
        }
        .info-grid {
            display: grid;
            gap: 10px;
        }
        .info-row {
            background: white;
            padding: 12px;
            border-radius: 5px;
            border-left: 4px solid ${status_color};
        }
        .info-row strong {
            color: ${status_color};
            display: inline-block;
            min-width: 120px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            background: white;
            border-radius: 5px;
            overflow: hidden;
        }
        th {
            background: ${status_color};
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }
        td {
            padding: 12px;
            border-bottom: 1px solid #e5e7eb;
        }
        tr:last-child td {
            border-bottom: none;
        }
        .status-success {
            color: #10b981;
            font-weight: 600;
        }
        .status-error {
            color: #ef4444;
            font-weight: 600;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 2px solid #e5e7eb;
            font-size: 14px;
            color: #6b7280;
            text-align: center;
        }
        .summary-box {
            background: white;
            padding: 20px;
            border-radius: 5px;
            border-left: 4px solid ${status_color};
            margin-bottom: 20px;
        }
        .summary-box h3 {
            margin-top: 0;
            color: ${status_color};
        }
        code {
            background: #1f2937;
            color: ${status_color};
            padding: 2px 8px;
            border-radius: 4px;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 13px;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Scraping Session Completed</h1>
        <div class="status-badge">${overall_status} ${status_icon}</div>
    </div>

    <div class="content">
        <div class="section">
            <h2>Session Summary</h2>
            <div class="info-grid">
                <div class="info-row">
                    <strong>Status:</strong> ${overall_status}
                </div>
                <div class="info-row">
                    <strong>Finish Time:</strong> ${timestamp}
                </div>
                <div class="info-row">
                    <strong>Duration:</strong> ${duration}
                </div>
                <div class="info-row">
                    <strong>Total Scrapers:</strong> ${total_count} executed
                </div>
            </div>
        </div>

        <div class="section">
            <h2>Results by Country</h2>
            <table>
                <thead>
                    <tr>
                        <th>Country</th>
                        <th>Status</th>
                        <th>Scrapers</th>
                        <th>Products</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td><strong>Poland</strong></td>
                        <td class="status-success">${poland_status}</td>
                        <td>${poland_count}</td>
                        <td>${poland_products}</td>
                    </tr>
                    <tr>
                        <td><strong>Germany</strong></td>
                        <td class="status-success">${germany_status}</td>
                        <td>${germany_count}</td>
                        <td>${germany_products}</td>
                    </tr>
                    <tr>
                        <td><strong>Czech Republic</strong></td>
                        <td class="status-success">${czech_status}</td>
                        <td>${czech_count}</td>
                        <td>${czech_products}</td>
                    </tr>
                </tbody>
            </table>
        </div>

        <div class="summary-box">
            <h3>Total Products Collected</h3>
            <p style="font-size: 24px; font-weight: bold; margin: 10px 0; color: ${status_color};">${total_products}</p>
            <p style="margin: 0; color: #6b7280;">Products collected and sent to API</p>
        </div>

        <div class="section">
            <h2>Next Scheduled Run</h2>
            <div class="info-row">
                ${next_run}
            </div>
        </div>

        <div class="section">
            <h2>Quick Commands</h2>
            <div class="info-grid">
                <div class="info-row">
                    <strong>View logs:</strong> <code>npm run scrapers:watch</code>
                </div>
                <div class="info-row">
                    <strong>Check status:</strong> <code>./setup.sh --status</code>
                </div>
                <div class="info-row">
                    <strong>Manual trigger:</strong> <code>npm run scrapers:start</code>
                </div>
            </div>
        </div>
    </div>

    <div class="footer">
        <p>CheaperForDrug Scraper - Automated Scraping System</p>
        <p>Scrapers run automatically: Monday and Thursday at 7:00 AM (Europe/Warsaw)</p>
    </div>
</body>
</html>
EOF
}

# ============================================================================
# EMAIL SENDING
# ============================================================================

send_scraper_email() {
    local event="$1"

    # Validate inputs
    if ! validate_inputs "${event}"; then
        return 1
    fi

    log_info "Preparing ${event} email..."

    # Generate email content based on event type
    local subject
    local body

    case "${event}" in
        start)
            subject="[CheaperForDrug Scraper] Scraping Started"
            body=$(generate_start_email)

            # Save start time for duration calculation
            save_start_time
            ;;
        finish)
            subject="[CheaperForDrug Scraper] Scraping Completed"
            body=$(generate_finish_email)
            ;;
        *)
            log_error "Unknown event type: ${event}"
            log_error "Valid events: start, finish"
            return 1
            ;;
    esac

    # Send email using the existing send-email script
    log_info "Sending ${event} email..."

    if "${SCRIPT_DIR}/send-email.sh" "${subject}" "${body}"; then
        log_success "Scraper ${event} email sent successfully"
        return 0
    else
        log_error "Failed to send scraper ${event} email"
        return 1
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local event="${1:-}"

    # Send email
    send_scraper_email "${event}"
}

# Run main with all arguments
main "$@"
