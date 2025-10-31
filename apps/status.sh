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
    local config_file="$app_dir/config.sh"

    # Always set APP_NAME from directory
    APP_NAME=$(basename "$app_dir")
    APP_DISPLAY_NAME=""
    DOMAIN=""
    APP_TYPE=""

    # Try to read from .env.production first
    if [ -f "$env_file" ]; then
        DOMAIN=$(grep "^DOMAIN=" "$env_file" 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        APP_DISPLAY_NAME=$(grep "^APP_DISPLAY_NAME=" "$env_file" 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        APP_TYPE=$(grep "^APP_TYPE=" "$env_file" 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
    fi

    # Fallback to config.sh if .env.production doesn't exist or values are missing
    if [ -f "$config_file" ] && [ -z "$DOMAIN" ]; then
        # Source config.sh in a subshell to get variables without polluting current shell
        eval "$(grep "^export DOMAIN=" "$config_file" 2>/dev/null | sed 's/^export //')"
        eval "$(grep "^export APP_DISPLAY_NAME=" "$config_file" 2>/dev/null | sed 's/^export //')"
        eval "$(grep "^export APP_TYPE=" "$config_file" 2>/dev/null | sed 's/^export //')"
    fi

    # If APP_DISPLAY_NAME is still empty, use APP_NAME
    if [ -z "$APP_DISPLAY_NAME" ]; then
        APP_DISPLAY_NAME="$APP_NAME"
    fi

    # If APP_TYPE is still empty, try to guess from structure
    if [ -z "$APP_TYPE" ]; then
        if [ -f "$app_dir/Gemfile" ] || grep -q "rails" "$config_file" 2>/dev/null; then
            APP_TYPE="rails"
        elif [ -f "$app_dir/package.json" ] || grep -q "nextjs" "$config_file" 2>/dev/null; then
            APP_TYPE="nextjs"
        else
            APP_TYPE="unknown"
        fi
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

# Function to get detailed backup information
get_backup_details() {
    local app_name="$1"
    local backup_base="/home/andrzej/backups/${app_name}"

    # Database backups
    local db_backup_dir="${backup_base}/db"
    local db_count=0
    local db_last_file=""
    local db_last_size=""
    local db_last_time=""
    local db_total_size=0

    if [ -d "$db_backup_dir" ]; then
        db_count=$(ls -1 "${db_backup_dir}"/*.sql.gz 2>/dev/null | wc -l | tr -d ' ')
        db_last_file=$(ls -t "${db_backup_dir}"/*.sql.gz 2>/dev/null | head -1)

        if [ -n "$db_last_file" ]; then
            db_last_size=$(du -h "$db_last_file" | cut -f1)
            db_last_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$db_last_file" 2>/dev/null || stat -c "%y" "$db_last_file" 2>/dev/null | cut -d'.' -f1)
            db_last_file=$(basename "$db_last_file")
        fi

        # Calculate total size of all db backups
        if [ $db_count -gt 0 ]; then
            db_total_size=$(du -sh "${db_backup_dir}" 2>/dev/null | cut -f1)
        fi
    fi

    # Image backups
    local img_backup_dir="${backup_base}/images"
    local img_count=0
    local img_last_file=""
    local img_last_size=""
    local img_last_time=""
    local img_total_size=0

    if [ -d "$img_backup_dir" ]; then
        img_count=$(ls -1 "${img_backup_dir}"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        img_last_file=$(ls -t "${img_backup_dir}"/*.tar.gz 2>/dev/null | head -1)

        if [ -n "$img_last_file" ]; then
            img_last_size=$(du -h "$img_last_file" | cut -f1)
            img_last_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$img_last_file" 2>/dev/null || stat -c "%y" "$img_last_file" 2>/dev/null | cut -d'.' -f1)
            img_last_file=$(basename "$img_last_file")
        fi

        # Calculate total size of all image backups
        if [ $img_count -gt 0 ]; then
            img_total_size=$(du -sh "${img_backup_dir}" 2>/dev/null | cut -f1)
        fi
    fi

    # Return all details separated by pipe
    echo "${db_count}|${db_last_file}|${db_last_size}|${db_last_time}|${db_total_size}|${img_count}|${img_last_file}|${img_last_size}|${img_last_time}|${img_total_size}"
}

# Function to check if backup is old (older than 7 days)
is_backup_old() {
    local backup_time="$1"

    if [ -z "$backup_time" ] || [ "$backup_time" = "Never" ]; then
        return 0  # true, no backup is "old"
    fi

    # Convert backup time to timestamp
    local backup_ts=$(date -j -f "%Y-%m-%d %H:%M" "$backup_time" +%s 2>/dev/null || date -d "$backup_time" +%s 2>/dev/null || echo "0")
    local now_ts=$(date +%s)
    local days_old=$(( (now_ts - backup_ts) / 86400 ))

    if [ $days_old -gt 7 ]; then
        return 0  # true
    else
        return 1  # false
    fi
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
# Look for directories with config.sh or deploy.sh (indicates it's an app)
app_dirs=()
for dir in "$APPS_DIR"/*; do
    if [ -d "$dir" ] && [[ "$(basename "$dir")" != "." ]] && [[ "$(basename "$dir")" != ".." ]]; then
        # Check if it's an app directory (has config.sh or deploy.sh)
        if [ -f "$dir/config.sh" ] || [ -f "$dir/deploy.sh" ]; then
            app_dirs+=("$dir")
        fi
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
    get_app_config "$app_dir"

    # Get status information
    container_info=$(get_container_status "$APP_NAME")
    IFS='|' read -r total_containers web_count worker_count scheduler_count <<< "$container_info"

    last_deployment=$(get_last_deployment "$APP_NAME")
    log_location=$(get_log_location "$APP_NAME")

    backup_details=$(get_backup_details "$APP_NAME")
    IFS='|' read -r db_count db_last_file db_last_size db_last_time db_total_size img_count img_last_file img_last_size img_last_time img_total_size <<< "$backup_details"

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
        alt_health=$(check_app_health "www.${DOMAIN}")
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
    echo -e "    Host:           tail -f ${log_location}/production.log"
    echo -e "    Docker:         docker logs ${APP_NAME}_web_1 -f"

    echo ""
    echo -e "  ${BOLD}Backups:${NC}"

    # Database backups section
    if [ "$db_count" -gt 0 ]; then
        # Determine color based on backup age
        local db_color="${GREEN}"
        if is_backup_old "$db_last_time"; then
            db_color="${YELLOW}"
        fi

        echo -e "    ${BOLD}Database Backups:${NC}"
        echo -e "      Count:        ${db_count} backup(s)"
        echo -e "      Latest:       ${db_color}${db_last_file}${NC}"
        echo -e "      Size:         ${db_last_size}"
        echo -e "      Created:      ${db_color}${db_last_time}${NC}"
        echo -e "      Total Size:   ${db_total_size}"
    else
        echo -e "    ${BOLD}Database Backups:${NC} ${YELLOW}None${NC}"
    fi

    # Docker image backups section
    if [ "$img_count" -gt 0 ]; then
        # Determine color based on backup age
        local img_color="${GREEN}"
        if is_backup_old "$img_last_time"; then
            img_color="${YELLOW}"
        fi

        echo -e "    ${BOLD}Docker Image Backups:${NC}"
        echo -e "      Count:        ${img_count} backup(s)"
        echo -e "      Latest:       ${img_color}${img_last_file}${NC}"
        echo -e "      Size:         ${img_last_size}"
        echo -e "      Created:      ${img_color}${img_last_time}${NC}"
        echo -e "      Total Size:   ${img_total_size}"
    else
        echo -e "    ${BOLD}Docker Image Backups:${NC} ${YELLOW}None${NC}"
    fi

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

# Backup Summary Section
echo -e "${BOLD}BACKUP SUMMARY:${NC}"
echo ""

total_db_backups=0
total_img_backups=0
total_backup_size=0
apps_with_db_backups=0
apps_with_img_backups=0

for app_dir in "${app_dirs[@]}"; do
    get_app_config "$app_dir" >/dev/null 2>&1
    backup_details=$(get_backup_details "$APP_NAME")
    IFS='|' read -r db_count db_last_file db_last_size db_last_time db_total_size img_count img_last_file img_last_size img_last_time img_total_size <<< "$backup_details"

    total_db_backups=$((total_db_backups + db_count))
    total_img_backups=$((total_img_backups + img_count))

    if [ "$db_count" -gt 0 ]; then
        apps_with_db_backups=$((apps_with_db_backups + 1))
    fi

    if [ "$img_count" -gt 0 ]; then
        apps_with_img_backups=$((apps_with_img_backups + 1))
    fi
done

# Calculate total backup disk usage across all apps
total_backup_usage=$(du -sh /home/andrzej/backups 2>/dev/null | cut -f1 || echo "0")

echo -e "  ${BOLD}Database Backups:${NC}"
echo -e "    Total Files:      ${total_db_backups}"
echo -e "    Apps with DB:     ${apps_with_db_backups}/${total_apps}"
echo ""
echo -e "  ${BOLD}Docker Image Backups:${NC}"
echo -e "    Total Files:      ${total_img_backups}"
echo -e "    Apps with Images: ${apps_with_img_backups}/${total_apps}"
echo ""
echo -e "  ${BOLD}Storage Usage:${NC}"
echo -e "    Total Backups:    ${total_backup_usage}"
echo -e "    Location:         /home/andrzej/backups/"
echo ""

# Show warnings for apps without recent backups
echo -e "  ${BOLD}Backup Health:${NC}"
apps_need_backup=0

for app_dir in "${app_dirs[@]}"; do
    get_app_config "$app_dir" >/dev/null 2>&1
    backup_details=$(get_backup_details "$APP_NAME")
    IFS='|' read -r db_count db_last_file db_last_size db_last_time db_total_size img_count img_last_file img_last_size img_last_time img_total_size <<< "$backup_details"

    # Check for Rails apps without DB backups
    if [ -f "$app_dir/config.sh" ]; then
        app_type=$(grep "^export APP_TYPE=" "$app_dir/config.sh" 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        if [ "$app_type" = "rails" ] && [ "$db_count" -eq 0 ]; then
            echo -e "    ${YELLOW}WARNING:${NC} ${APP_NAME} (Rails) has no database backups"
            apps_need_backup=$((apps_need_backup + 1))
        fi
    fi

    # Check for old backups
    if [ -n "$db_last_time" ] && is_backup_old "$db_last_time"; then
        echo -e "    ${YELLOW}WARNING:${NC} ${APP_NAME} database backup is older than 7 days"
        apps_need_backup=$((apps_need_backup + 1))
    fi

    if [ -n "$img_last_time" ] && is_backup_old "$img_last_time"; then
        echo -e "    ${YELLOW}WARNING:${NC} ${APP_NAME} image backup is older than 7 days"
        apps_need_backup=$((apps_need_backup + 1))
    fi
done

if [ $apps_need_backup -eq 0 ]; then
    echo -e "    ${GREEN}All backups are up to date${NC}"
fi

echo ""
echo -e "${BOLD}================================================================================${NC}"
echo ""
