#!/bin/bash

# ============================================================================
# Deployment Summary Generator
# ============================================================================
# Generates deployment summary data for email notifications
#
# Usage:
#   ./deployment-summary.sh [status] [duration]
#
# Arguments:
#   status   - Deployment status (success/failure) [default: success]
#   duration - Deployment duration in seconds [optional]
#
# Output:
#   HTML formatted deployment summary
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURATION
# ============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${HOME}/apps/cheaperfordrug-scraper"
REPO_DIR="${APP_DIR}/repo"

# Container names
CONTAINER_POLAND="cheaperfordrug-scraper-poland"
CONTAINER_GERMANY="cheaperfordrug-scraper-germany"
CONTAINER_CZECH="cheaperfordrug-scraper-czech"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

get_container_status() {
    local container_name="$1"

    if docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "${container_name}"; then
        local health
        health=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null || echo "no healthcheck")
        local status
        status=$(docker inspect --format='{{.State.Status}}' "${container_name}" 2>/dev/null || echo "unknown")

        if [ "${health}" = "healthy" ]; then
            echo "Running (Healthy)"
        elif [ "${health}" = "unhealthy" ]; then
            echo "Running (Unhealthy)"
        elif [ "${status}" = "running" ]; then
            echo "Running"
        else
            echo "${status}"
        fi
    else
        echo "Not Running"
    fi
}

get_container_status_icon() {
    local container_name="$1"

    if docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "${container_name}"; then
        local health
        health=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null || echo "no healthcheck")

        if [ "${health}" = "healthy" ]; then
            echo "✓"
        elif [ "${health}" = "unhealthy" ]; then
            echo "✗"
        else
            echo "•"
        fi
    else
        echo "✗"
    fi
}

get_git_commit() {
    if [ -d "${REPO_DIR}/.git" ]; then
        cd "${REPO_DIR}"
        local commit_hash
        commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        local commit_message
        commit_message=$(git log -1 --pretty=%B 2>/dev/null | head -n1 || echo "")
        echo "${commit_hash}: ${commit_message}"
    else
        echo "No git repository"
    fi
}

get_next_scheduled_run() {
    # Next Monday or Thursday at 7:00 AM
    local next_run
    next_run=$(date -v +1d +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || date -d "+1 day" +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || echo "Next scheduled run")

    # Find next Monday or Thursday
    local day_of_week
    day_of_week=$(date +%u)  # 1=Monday, 4=Thursday

    if [ "${day_of_week}" -lt 1 ]; then
        # Before Monday - next Monday
        next_run=$(date -v +mon +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || echo "Monday at 7:00 AM")
    elif [ "${day_of_week}" -eq 1 ]; then
        # Monday - next Thursday
        next_run=$(date -v +thu +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || echo "Thursday at 7:00 AM")
    elif [ "${day_of_week}" -lt 4 ]; then
        # Between Monday and Thursday - next Thursday
        next_run=$(date -v +thu +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || echo "Thursday at 7:00 AM")
    elif [ "${day_of_week}" -eq 4 ]; then
        # Thursday - next Monday
        next_run=$(date -v +mon +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || echo "Monday at 7:00 AM")
    else
        # After Thursday - next Monday
        next_run=$(date -v +mon +"%A, %B %d, %Y at 7:00 AM" 2>/dev/null || echo "Monday at 7:00 AM")
    fi

    echo "${next_run}"
}

format_duration() {
    local duration_seconds="$1"

    if [ -z "${duration_seconds}" ] || [ "${duration_seconds}" -eq 0 ]; then
        echo "N/A"
        return
    fi

    local minutes=$((duration_seconds / 60))
    local seconds=$((duration_seconds % 60))

    if [ "${minutes}" -gt 0 ]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${seconds}s"
    fi
}

# ============================================================================
# EMAIL GENERATION
# ============================================================================

generate_success_email() {
    local duration="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Get container statuses
    local poland_status
    poland_status=$(get_container_status "${CONTAINER_POLAND}")
    local poland_icon
    poland_icon=$(get_container_status_icon "${CONTAINER_POLAND}")

    local germany_status
    germany_status=$(get_container_status "${CONTAINER_GERMANY}")
    local germany_icon
    germany_icon=$(get_container_status_icon "${CONTAINER_GERMANY}")

    local czech_status
    czech_status=$(get_container_status "${CONTAINER_CZECH}")
    local czech_icon
    czech_icon=$(get_container_status_icon "${CONTAINER_CZECH}")

    # Get git commit
    local git_commit
    git_commit=$(get_git_commit)

    # Get next scheduled run
    local next_run
    next_run=$(get_next_scheduled_run)

    # Format duration
    local duration_formatted
    duration_formatted=$(format_duration "${duration}")

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
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
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
            background: #10b981;
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
            color: #667eea;
            font-size: 18px;
            margin-bottom: 10px;
            border-bottom: 2px solid #667eea;
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
            border-left: 4px solid #667eea;
        }
        .info-row strong {
            color: #667eea;
            display: inline-block;
            min-width: 120px;
        }
        .container-list {
            list-style: none;
            padding: 0;
        }
        .container-list li {
            background: white;
            padding: 12px;
            margin-bottom: 8px;
            border-radius: 5px;
            border-left: 4px solid #10b981;
        }
        .container-list li.unhealthy {
            border-left-color: #ef4444;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 2px solid #e5e7eb;
            font-size: 14px;
            color: #6b7280;
            text-align: center;
        }
        code {
            background: #1f2937;
            color: #10b981;
            padding: 2px 8px;
            border-radius: 4px;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 13px;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Deployment Summary</h1>
        <div class="status-badge">SUCCESS</div>
    </div>

    <div class="content">
        <div class="section">
            <h2>Overview</h2>
            <div class="info-grid">
                <div class="info-row">
                    <strong>Status:</strong> Success
                </div>
                <div class="info-row">
                    <strong>Date:</strong> ${timestamp}
                </div>
                <div class="info-row">
                    <strong>Server:</strong> webet
                </div>
                <div class="info-row">
                    <strong>Duration:</strong> ${duration_formatted}
                </div>
            </div>
        </div>

        <div class="section">
            <h2>Containers Status</h2>
            <ul class="container-list">
                <li>Poland: ${poland_status} ${poland_icon}</li>
                <li>Germany: ${germany_status} ${germany_icon}</li>
                <li>Czech: ${czech_status} ${czech_icon}</li>
            </ul>
        </div>

        <div class="section">
            <h2>Deployment Details</h2>
            <div class="info-grid">
                <div class="info-row">
                    <strong>Git Commit:</strong> ${git_commit}
                </div>
                <div class="info-row">
                    <strong>Docker Images:</strong> Rebuilt and deployed
                </div>
                <div class="info-row">
                    <strong>VPN:</strong> NordVPN connected (Poland, Germany, Czech)
                </div>
            </div>
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
                    <strong>Restart:</strong> <code>./setup.sh --restart</code>
                </div>
            </div>
        </div>
    </div>

    <div class="footer">
        <p>CheaperForDrug Scraper - Automated Deployment System</p>
        <p>Scrapers run automatically: Monday and Thursday at 7:00 AM (Europe/Warsaw)</p>
    </div>
</body>
</html>
EOF
}

generate_failure_email() {
    local duration="$1"
    local error_message="${2:-Unknown error occurred}"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Get container statuses
    local poland_status
    poland_status=$(get_container_status "${CONTAINER_POLAND}")
    local poland_icon
    poland_icon=$(get_container_status_icon "${CONTAINER_POLAND}")

    local germany_status
    germany_status=$(get_container_status "${CONTAINER_GERMANY}")
    local germany_icon
    germany_icon=$(get_container_status_icon "${CONTAINER_GERMANY}")

    local czech_status
    czech_status=$(get_container_status "${CONTAINER_CZECH}")
    local czech_icon
    czech_icon=$(get_container_status_icon "${CONTAINER_CZECH}")

    # Get git commit
    local git_commit
    git_commit=$(get_git_commit)

    # Format duration
    local duration_formatted
    duration_formatted=$(format_duration "${duration}")

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
            background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
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
            background: #7f1d1d;
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
            color: #ef4444;
            font-size: 18px;
            margin-bottom: 10px;
            border-bottom: 2px solid #ef4444;
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
            border-left: 4px solid #ef4444;
        }
        .info-row strong {
            color: #ef4444;
            display: inline-block;
            min-width: 120px;
        }
        .error-box {
            background: #fee2e2;
            border: 2px solid #ef4444;
            padding: 15px;
            border-radius: 5px;
            color: #7f1d1d;
            font-family: monospace;
            white-space: pre-wrap;
        }
        .container-list {
            list-style: none;
            padding: 0;
        }
        .container-list li {
            background: white;
            padding: 12px;
            margin-bottom: 8px;
            border-radius: 5px;
            border-left: 4px solid #10b981;
        }
        .container-list li.unhealthy {
            border-left-color: #ef4444;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 2px solid #e5e7eb;
            font-size: 14px;
            color: #6b7280;
            text-align: center;
        }
        code {
            background: #1f2937;
            color: #ef4444;
            padding: 2px 8px;
            border-radius: 4px;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 13px;
        }
        .action-required {
            background: #fef3c7;
            border: 2px solid #f59e0b;
            padding: 15px;
            border-radius: 5px;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Deployment Failed</h1>
        <div class="status-badge">FAILURE</div>
    </div>

    <div class="content">
        <div class="section">
            <h2>Overview</h2>
            <div class="info-grid">
                <div class="info-row">
                    <strong>Status:</strong> Failed
                </div>
                <div class="info-row">
                    <strong>Date:</strong> ${timestamp}
                </div>
                <div class="info-row">
                    <strong>Server:</strong> webet
                </div>
                <div class="info-row">
                    <strong>Duration:</strong> ${duration_formatted}
                </div>
            </div>
        </div>

        <div class="section">
            <h2>Error Details</h2>
            <div class="error-box">${error_message}</div>
        </div>

        <div class="section">
            <h2>Containers Status</h2>
            <ul class="container-list">
                <li class="$([ "${poland_status}" = "Running (Healthy)" ] || echo "unhealthy")">Poland: ${poland_status} ${poland_icon}</li>
                <li class="$([ "${germany_status}" = "Running (Healthy)" ] || echo "unhealthy")">Germany: ${germany_status} ${germany_icon}</li>
                <li class="$([ "${czech_status}" = "Running (Healthy)" ] || echo "unhealthy")">Czech: ${czech_status} ${czech_icon}</li>
            </ul>
        </div>

        <div class="section">
            <h2>Deployment Details</h2>
            <div class="info-grid">
                <div class="info-row">
                    <strong>Git Commit:</strong> ${git_commit}
                </div>
            </div>
        </div>

        <div class="action-required">
            <h3 style="margin-top: 0; color: #b45309;">Action Required</h3>
            <p>Please investigate the deployment failure and take corrective action.</p>
            <p><strong>Recommended steps:</strong></p>
            <ol>
                <li>Check deployment logs: <code>./setup.sh --logs</code></li>
                <li>Check container status: <code>./setup.sh --status</code></li>
                <li>Review error message above</li>
                <li>Retry deployment: <code>./setup.sh --deploy</code></li>
            </ol>
        </div>
    </div>

    <div class="footer">
        <p>CheaperForDrug Scraper - Automated Deployment System</p>
        <p>Immediate attention required!</p>
    </div>
</body>
</html>
EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local status="${1:-success}"
    local duration="${2:-0}"
    local error_message="${3:-}"

    if [ "${status}" = "success" ]; then
        generate_success_email "${duration}"
    else
        generate_failure_email "${duration}" "${error_message}"
    fi
}

# Run main with all arguments
main "$@"
