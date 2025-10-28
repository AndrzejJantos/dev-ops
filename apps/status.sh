#!/bin/bash

# Global Application Status Script
# Location: ~/DevOps/apps/status.sh
# Shows comprehensive status for all deployed applications

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$SCRIPT_DIR"

# Function to get app configuration
get_app_config() {
    local app_dir="$1"
    local env_file="$app_dir/.env.production"

    if [ ! -f "$env_file" ]; then
        return 1
    fi

    # Read key configuration values
    APP_NAME=$(basename "$app_dir")
    DOMAIN=$(grep "^DOMAIN=" "$env_file" 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
    APP_DISPLAY_NAME=$(grep "^APP_DISPLAY_NAME=" "$env_file" 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
    APP_TYPE=$(grep "^APP_TYPE=" "$env_file" 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")

    # If APP_DISPLAY_NAME is empty, use APP_NAME
    if [ -z "$APP_DISPLAY_NAME" ]; then
        APP_DISPLAY_NAME="$APP_NAME"
    fi

    return 0
}

# Function to get container status
get_container_status() {
    local app_name="$1"

    # Get all containers for this app
    local containers=($(docker ps --filter "name=${app_name}" --format "{{.Names}}" 2>/dev/null))
    local container_count=${#containers[@]}

    # Count by type
    local web_count=$(docker ps --filter "name=${app_name}_web" --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')
    local worker_count=$(docker ps --filter "name=${app_name}_worker" --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')
    local scheduler_count=$(docker ps --filter "name=${app_name}_scheduler" --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')

    echo "${container_count}|${web_count}|${worker_count}|${scheduler_count}"
}

# Function to get last deployment time
get_last_deployment() {
    local app_name="$1"

    # Try to get from newest container creation time
    local container_created=$(docker ps --filter "name=${app_name}_web" --format "{{.CreatedAt}}" 2>/dev/null | head -1)

    if [ -n "$container_created" ]; then
        echo "$container_created"
    else
        echo "Never"
    fi
}

# Function to get log location
get_log_location() {
    local app_name="$1"
    local logs_dir="/home/andrzej/apps/${app_name}/logs"

    if [ -d "$logs_dir" ]; then
        local log_count=$(ls -1 "$logs_dir"/*.log 2>/dev/null | wc -l | tr -d ' ')
        echo "${logs_dir} (${log_count} files)"
    else
        echo "Not configured"
    fi
}

# Function to count backups
count_backups() {
    local app_name="$1"
    local backup_dir="/home/andrzej/backups/${app_name}"

    local db_backups=0
    local image_backups=0

    if [ -d "${backup_dir}/db" ]; then
        db_backups=$(ls -1 "${backup_dir}/db"/*.sql.gz 2>/dev/null | wc -l | tr -d ' ')
    fi

    if [ -d "${backup_dir}/images" ]; then
        image_backups=$(ls -1 "${backup_dir}/images"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
    fi

    echo "${db_backups}|${image_backups}"
}

# Function to check if app is accessible
check_app_health() {
    local domain="$1"

    if [ -z "$domain" ]; then
        echo "❌"
        return
    fi

    # Try HTTPS first
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${domain}" 2>/dev/null)

    if [[ "$status" =~ ^[23][0-9][0-9]$ ]]; then
        echo "✅"
    else
        echo "❌"
    fi
}

# Main script
echo ""
echo -e "${BOLD}================================================================================${NC}"
echo -e "${BOLD}                      APPLICATION STATUS OVERVIEW${NC}"
echo -e "${BOLD}================================================================================${NC}"
echo ""
echo -e "Generated: ${CYAN}$(date)${NC}"
echo ""

# Find all app directories
app_dirs=()
for dir in "$APPS_DIR"/*; do
    if [ -d "$dir" ] && [ -f "$dir/.env.production" ]; then
        app_dirs+=("$dir")
    fi
done

if [ ${#app_dirs[@]} -eq 0 ]; then
    echo -e "${YELLOW}No applications found in ${APPS_DIR}${NC}"
    echo ""
    exit 0
fi

echo -e "${BOLD}Found ${#app_dirs[@]} application(s)${NC}"
echo ""

# Process each app
for app_dir in "${app_dirs[@]}"; do
    # Get app configuration
    if ! get_app_config "$app_dir"; then
        continue
    fi

    # Get status information
    container_info=$(get_container_status "$APP_NAME")
    IFS='|' read -r total_containers web_count worker_count scheduler_count <<< "$container_info"

    last_deployment=$(get_last_deployment "$APP_NAME")
    log_location=$(get_log_location "$APP_NAME")

    backup_info=$(count_backups "$APP_NAME")
    IFS='|' read -r db_backups image_backups <<< "$backup_info"

    health_status=$(check_app_health "$DOMAIN")

    # Determine overall status
    if [ "$total_containers" -gt 0 ]; then
        status_text="${GREEN}RUNNING${NC}"
    else
        status_text="${RED}STOPPED${NC}"
    fi

    # Print app status
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}${APP_DISPLAY_NAME}${NC} ${status_text}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    echo -e "  ${BOLD}App ID:${NC}           ${APP_NAME}"
    echo -e "  ${BOLD}Type:${NC}             ${APP_TYPE:-Unknown}"
    echo -e "  ${BOLD}Domain:${NC}           ${DOMAIN:-Not configured} ${health_status}"

    if [[ "$DOMAIN" != www.* ]] && [ -n "$DOMAIN" ]; then
        local alt_health=$(check_app_health "www.${DOMAIN}")
        echo -e "  ${BOLD}Alternative:${NC}      www.${DOMAIN} ${alt_health}"
    fi

    echo ""
    echo -e "  ${BOLD}Containers:${NC}"
    echo -e "    Total:          ${total_containers}"
    echo -e "    Web:            ${web_count}"

    if [ "$worker_count" -gt 0 ]; then
        echo -e "    Workers:        ${worker_count}"
    fi

    if [ "$scheduler_count" -gt 0 ]; then
        echo -e "    Scheduler:      ${scheduler_count}"
    fi

    echo ""
    echo -e "  ${BOLD}Deployment:${NC}"
    echo -e "    Last:           ${last_deployment}"

    echo ""
    echo -e "  ${BOLD}Logs:${NC}"
    echo -e "    Location:       ${log_location}"
    echo -e "    View:           /home/andrzej/apps/${APP_NAME}/logs.sh"
    echo -e "    Docker:         docker logs ${APP_NAME}_web_1 -f"

    echo ""
    echo -e "  ${BOLD}Backups:${NC}"
    echo -e "    Database:       ${db_backups} backup(s)"
    echo -e "    Docker Images:  ${image_backups} backup(s)"

    echo ""
    echo -e "  ${BOLD}Quick Actions:${NC}"
    echo -e "    Deploy:         cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh"
    echo -e "    Config:         cd ~/DevOps/apps/${APP_NAME}"
    echo -e "    Instance:       cd ~/apps/${APP_NAME}"
    echo -e "    Restart:        cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh restart"
    echo -e "    Stop:           cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh stop"

    if [ "$total_containers" -gt 0 ]; then
        echo -e "    Scale to N:     cd ~/DevOps/apps/${APP_NAME} && ./deploy.sh scale N"
    fi

    echo ""
done

echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Summary statistics
total_apps=${#app_dirs[@]}
running_apps=0
total_web_containers=0
total_worker_containers=0

for app_dir in "${app_dirs[@]}"; do
    get_app_config "$app_dir" >/dev/null 2>&1
    container_info=$(get_container_status "$APP_NAME")
    IFS='|' read -r total web worker scheduler <<< "$container_info"

    if [ "$total" -gt 0 ]; then
        running_apps=$((running_apps + 1))
    fi

    total_web_containers=$((total_web_containers + web))
    total_worker_containers=$((total_worker_containers + worker))
done

echo -e "${BOLD}SUMMARY:${NC}"
echo -e "  Total Applications:     ${total_apps}"
echo -e "  Running:                ${running_apps}"
echo -e "  Stopped:                $((total_apps - running_apps))"
echo -e "  Total Web Containers:   ${total_web_containers}"
echo -e "  Total Worker Containers: ${total_worker_containers}"
echo ""
echo -e "${BOLD}================================================================================${NC}"
echo ""
