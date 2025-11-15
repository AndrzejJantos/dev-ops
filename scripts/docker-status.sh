#!/bin/bash

# Docker Container Status Monitor
# Location: /Users/andrzej/Development/Brokik/DevOps/scripts/docker-status.sh
# This script displays comprehensive Docker container monitoring information
#
# Usage:
#   ./docker-status.sh              # Show all running containers
#   ./docker-status.sh --all        # Show all containers (including stopped)
#   ./docker-status.sh --help       # Show help message

set -euo pipefail

# ==============================================================================
# EMAIL NOTIFICATION SYSTEM
# ==============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to find the common directory (supports both local and server paths)
COMMON_DIR=""
if [ -d "/home/andrzej/DevOps/common" ]; then
    # Server path
    COMMON_DIR="/home/andrzej/DevOps/common"
elif [ -d "$SCRIPT_DIR/../common" ]; then
    # Local development path
    COMMON_DIR="$SCRIPT_DIR/../common"
fi

# Load email notification functions if available
EMAIL_NOTIFICATIONS_AVAILABLE=false
if [ -n "$COMMON_DIR" ] && [ -f "$COMMON_DIR/email-notification.sh" ]; then
    # Create minimal log functions if not already defined
    if ! type log_error >/dev/null 2>&1; then
        log_error() { echo "ERROR: $*" >&2; }
    fi
    if ! type log_warning >/dev/null 2>&1; then
        log_warning() { echo "WARNING: $*" >&2; }
    fi
    if ! type log_info >/dev/null 2>&1; then
        log_info() { echo "INFO: $*"; }
    fi

    # Try to source the email notification system
    if source "$COMMON_DIR/email-notification.sh" 2>/dev/null; then
        EMAIL_NOTIFICATIONS_AVAILABLE=true
    fi
fi

# ANSI Color Codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color

# Configuration
SHOW_ALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all|-a)
            SHOW_ALL=true
            shift
            ;;
        --help|-h)
            echo "Docker Container Status Monitor"
            echo ""
            echo "Usage:"
            echo "  $0              # Show running containers only"
            echo "  $0 --all        # Show all containers (including stopped)"
            echo "  $0 --help       # Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    error_exit "Docker is not running or you don't have permission to access it"
fi

# Function to get system memory usage
get_system_memory() {
    if command -v free >/dev/null 2>&1; then
        # Use free command (Linux)
        local mem_info=$(free -h | grep '^Mem:')
        local total=$(echo "$mem_info" | awk '{print $2}')
        local used=$(echo "$mem_info" | awk '{print $3}')
        local available=$(echo "$mem_info" | awk '{print $7}')
        local percent=$(free | grep '^Mem:' | awk '{printf "%.1f", ($3/$2)*100}')
        echo "${used}/${total} (${percent}% used, ${available} available)"
    else
        echo "N/A"
    fi
}

# Function to get disk usage
get_disk_usage() {
    # Get disk usage for root filesystem and docker data root
    local root_usage=$(df -h / | tail -1 | awk '{print $3"/"$2" ("$5" used)"}')

    # Try to get Docker data root
    local docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    local docker_usage=$(df -h "$docker_root" 2>/dev/null | tail -1 | awk '{print $3"/"$2" ("$5" used)"}' || echo "N/A")

    # If docker is on the same filesystem as root, only show root
    local root_device=$(df / | tail -1 | awk '{print $1}')
    local docker_device=$(df "$docker_root" 2>/dev/null | tail -1 | awk '{print $1}' || echo "")

    if [ "$root_device" = "$docker_device" ]; then
        echo "Root: ${root_usage}"
    else
        echo "Root: ${root_usage}, Docker: ${docker_usage}"
    fi
}

# Print header
print_header() {
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}                     DOCKER CONTAINER STATUS MONITOR${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${DIM}Generated: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
}

# Print table header
print_table_header() {
    printf "${BOLD}%-30s %-12s %-10s %-20s %-15s %-15s${NC}\n" \
        "CONTAINER NAME" "STATUS" "CPU %" "MEMORY USAGE" "UPTIME" "HEALTH"
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
}

# Format uptime to human readable
format_uptime() {
    local uptime="$1"

    # Remove any extra spaces and handle different formats
    uptime=$(echo "$uptime" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # If uptime contains "Up", extract it
    if [[ "$uptime" =~ Up[[:space:]]+(.*) ]]; then
        uptime="${BASH_REMATCH[1]}"
    fi

    # Truncate if too long
    if [ ${#uptime} -gt 14 ]; then
        uptime="${uptime:0:11}..."
    fi

    echo "$uptime"
}

# Format memory usage
format_memory() {
    local mem_usage="$1"
    local mem_limit="$2"

    # Remove any trailing units if present
    mem_usage=$(echo "$mem_usage" | sed 's/[[:space:]]*$//')
    mem_limit=$(echo "$mem_limit" | sed 's/[[:space:]]*$//')

    # Format as "usage/limit"
    echo "${mem_usage}/${mem_limit}"
}

# Get container health status
get_health_status() {
    local container_id="$1"
    local health=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "none")

    if [ "$health" = "healthy" ]; then
        echo -e "${GREEN}healthy${NC}"
    elif [ "$health" = "unhealthy" ]; then
        echo -e "${RED}unhealthy${NC}"
    elif [ "$health" = "starting" ]; then
        echo -e "${YELLOW}starting${NC}"
    else
        echo -e "${DIM}no healthcheck${NC}"
    fi
}

# Get color for status
get_status_color() {
    local status="$1"

    case "$status" in
        running)
            echo "${GREEN}"
            ;;
        exited|dead|paused)
            echo "${RED}"
            ;;
        created|restarting)
            echo "${YELLOW}"
            ;;
        *)
            echo "${NC}"
            ;;
    esac
}

# Main function to display container status
show_container_status() {
    print_header

    # Get list of containers
    local filter_arg=""
    if [ "$SHOW_ALL" = false ]; then
        filter_arg="--filter status=running"
    fi

    # Get container IDs
    local container_ids=$(docker ps $filter_arg --format "{{.ID}}" 2>/dev/null)

    if [ -z "$container_ids" ]; then
        echo -e "${YELLOW}No containers found${NC}"
        echo ""
        return
    fi

    # Get stats in background (single snapshot)
    local stats_output=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" $container_ids 2>/dev/null | tail -n +2)

    # Print table header
    print_table_header

    # Initialize counters
    local total_containers=0
    local running_containers=0
    local stopped_containers=0
    local total_cpu=0
    local healthy_containers=0
    local unhealthy_containers=0

    # Process each container
    while IFS= read -r container_id; do
        if [ -z "$container_id" ]; then
            continue
        fi

        # Get container details
        local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')
        local status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null)
        local started=$(docker inspect --format='{{.State.StartedAt}}' "$container_id" 2>/dev/null)

        # Calculate uptime
        local uptime=""
        if [ "$status" = "running" ]; then
            # Docker returns timestamps in ISO 8601 format with UTC timezone: 2025-01-08T14:30:45.123456789Z
            # We need to parse this as UTC time, not local time

            local started_ts=""

            # Parse the timestamp - handle both macOS (BSD) and Linux (GNU) date commands
            if date --version >/dev/null 2>&1; then
                # GNU date (Linux) - can parse ISO 8601 directly with UTC timezone
                started_ts=$(date -u -d "$started" "+%s" 2>/dev/null)
            else
                # macOS date (BSD) - requires manual format specification
                # Remove fractional seconds and Z suffix for parsing
                local started_clean=$(echo "$started" | sed 's/\.[0-9]*Z$//' | sed 's/Z$//')
                started_ts=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "$started_clean" "+%s" 2>/dev/null)
            fi

            # If parsing failed, try alternative method using docker ps
            if [ -z "$started_ts" ] || [ "$started_ts" = "0" ]; then
                # Fallback: parse from docker ps status field
                local status_line=$(docker ps --filter "id=$container_id" --format "{{.Status}}" 2>/dev/null)
                if [[ "$status_line" =~ Up[[:space:]]+(.*) ]]; then
                    uptime=$(format_uptime "${BASH_REMATCH[1]}")
                else
                    uptime="N/A"
                fi
            else
                # Calculate uptime from timestamps (both in UTC)
                local current_ts=$(date -u "+%s")
                local diff=$((current_ts - started_ts))

                # Ensure diff is positive
                if [ $diff -lt 0 ]; then
                    diff=0
                fi

                if [ $diff -lt 60 ]; then
                    uptime="${diff}s"
                elif [ $diff -lt 3600 ]; then
                    uptime="$((diff / 60))m"
                elif [ $diff -lt 86400 ]; then
                    uptime="$((diff / 3600))h $((diff % 3600 / 60))m"
                else
                    uptime="$((diff / 86400))d $((diff % 86400 / 3600))h"
                fi
            fi
            running_containers=$((running_containers + 1))
        else
            uptime="stopped"
            stopped_containers=$((stopped_containers + 1))
        fi

        # Get health status
        local health=$(get_health_status "$container_id")
        if [[ "$health" == *"healthy"* ]]; then
            healthy_containers=$((healthy_containers + 1))
        elif [[ "$health" == *"unhealthy"* ]]; then
            unhealthy_containers=$((unhealthy_containers + 1))
        fi

        # Get stats from the stats output
        local cpu="N/A"
        local mem_usage="N/A"
        local mem_limit=""

        if [ "$status" = "running" ]; then
            local stats_line=$(echo "$stats_output" | grep "^${container_id:0:12}" || echo "")
            if [ -n "$stats_line" ]; then
                cpu=$(echo "$stats_line" | awk '{print $2}')
                local mem_full=$(echo "$stats_line" | awk '{print $3, $4, $5}')
                mem_usage=$(echo "$mem_full" | awk '{print $1}')
                mem_limit=$(echo "$mem_full" | awk '{print $3}')

                # Add to total CPU (remove % sign)
                local cpu_num=$(echo "$cpu" | sed 's/%//')
                total_cpu=$(echo "$total_cpu + $cpu_num" | bc 2>/dev/null || echo "$total_cpu")
            fi
        fi

        # Format memory
        local memory_display
        if [ "$mem_limit" != "" ]; then
            memory_display=$(format_memory "$mem_usage" "$mem_limit")
        else
            memory_display="$mem_usage"
        fi

        # Truncate name if too long
        if [ ${#name} -gt 28 ]; then
            name="${name:0:25}..."
        fi

        # Get status color
        local status_color=$(get_status_color "$status")

        # Determine row color based on overall health
        local row_color="${NC}"
        if [ "$status" = "running" ]; then
            if [[ "$health" == *"healthy"* ]]; then
                row_color="${GREEN}"
            elif [[ "$health" == *"unhealthy"* ]]; then
                row_color="${RED}"
            else
                row_color="${YELLOW}"
            fi
        else
            row_color="${RED}"
        fi

        # Print row
        printf "${row_color}%-30s${NC} ${status_color}%-12s${NC} %-10s %-20s %-15s %b\n" \
            "$name" \
            "$status" \
            "$cpu" \
            "$memory_display" \
            "$uptime" \
            "$health"

        total_containers=$((total_containers + 1))
    done <<< "$container_ids"

    # Get system-wide statistics
    local system_memory=$(get_system_memory)
    local disk_usage=$(get_disk_usage)

    # Print summary
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}SUMMARY${NC}"
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"

    printf "  ${BOLD}Total Containers:${NC}       %d\n" "$total_containers"
    printf "  ${GREEN}Running:${NC}                %d\n" "$running_containers"

    if [ $stopped_containers -gt 0 ]; then
        printf "  ${RED}Stopped:${NC}                %d\n" "$stopped_containers"
    fi

    if [ $healthy_containers -gt 0 ]; then
        printf "  ${GREEN}Healthy:${NC}                %d\n" "$healthy_containers"
    fi

    if [ $unhealthy_containers -gt 0 ]; then
        printf "  ${RED}Unhealthy:${NC}              %d\n" "$unhealthy_containers"
    fi

    if [ "$running_containers" -gt 0 ]; then
        printf "  ${BOLD}Total CPU Usage:${NC}        %.2f%%\n" "$total_cpu"
    fi

    # Add system memory and disk usage
    echo ""
    printf "  ${BOLD}System Memory:${NC}          %s\n" "$system_memory"
    printf "  ${BOLD}Disk Usage:${NC}             %s\n" "$disk_usage"

    # Scraper API Infrastructure Information
    echo ""
    echo -e "${BOLD}${CYAN}SCRAPER API INFRASTRUCTURE${NC}"
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"

    # Count API containers
    local api_containers=$(docker ps --filter "name=cheaperfordrug-api_web" --format "{{.ID}}" 2>/dev/null | wc -l | tr -d ' ')

    # Count scraper containers
    local scraper_containers=$(docker ps --filter "name=scraper" --filter "name=product-update-worker" --format "{{.ID}}" 2>/dev/null | wc -l | tr -d ' ')

    # Check nginx load balancer on port 4200
    local nginx_status="${RED}DOWN${NC}"
    local nginx_port_info=""
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":4200 "; then
            nginx_status="${GREEN}UP${NC}"
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | grep -q ":4200 "; then
            nginx_status="${GREEN}UP${NC}"
        fi
    fi

    # Count API containers listening on ports 3020-3050
    local listening_ports=0
    if command -v ss >/dev/null 2>&1; then
        listening_ports=$(ss -tlnp 2>/dev/null | grep -oE ':(30[2-5][0-9])' | grep -oE '[0-9]+' | sort -n | uniq | wc -l | tr -d ' ')
    fi

    printf "  ${BOLD}API Containers:${NC}         %d running\n" "$api_containers"
    printf "  ${BOLD}Scraper Containers:${NC}     %d running\n" "$scraper_containers"
    printf "  ${BOLD}Nginx Load Balancer:${NC}    %b (port 4200)\n" "$nginx_status"

    if [ "$listening_ports" -gt 0 ]; then
        printf "  ${BOLD}Backend Ports Active:${NC}   %d (ports 3020-3050)\n" "$listening_ports"
    fi

    # Show scraper endpoint
    printf "  ${BOLD}Scraper Endpoint:${NC}       http://localhost:4200\n"

    # Check for recent scraper traffic (if log file exists)
    if [ -f "/var/log/nginx/api-scraper-local-access.log" ]; then
        local recent_requests=$(tail -1000 /var/log/nginx/api-scraper-local-access.log 2>/dev/null | wc -l | tr -d ' ')
        if [ "$recent_requests" -gt 0 ]; then
            printf "  ${BOLD}Recent Requests:${NC}        %s (last 1000 log lines)\n" "$recent_requests"
        fi
    fi

    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Confirmation prompt function
confirm_action() {
    local action="$1"
    echo -e "${YELLOW}${BOLD}Are you sure you want to ${action}?${NC}"
    read -p "Type 'yes' to confirm: " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        echo -e "${CYAN}Action cancelled.${NC}"
        echo ""
        return 1
    fi
    return 0
}

# Function to wait for container to become healthy
wait_for_container_health() {
    local container_id="$1"
    local container_name="$2"
    local max_wait=60  # seconds
    local elapsed=0
    local interval=2   # check every 2 seconds

    echo -e "  ${CYAN}Waiting for ${container_name} to become healthy...${NC}"

    while [ $elapsed -lt $max_wait ]; do
        # Check if container is still running
        local status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null)

        if [ "$status" != "running" ]; then
            echo -e "  ${RED}✗ Container stopped unexpectedly${NC}"
            return 1
        fi

        # Check health status
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "no_healthcheck")

        # Container is ready if:
        # - It has healthcheck and is healthy, OR
        # - It has no healthcheck and is running
        if [ "$health" = "healthy" ] || [ "$health" = "no_healthcheck" ]; then
            echo -e "  ${GREEN}✓ ${container_name} is ready${NC}"
            return 0
        fi

        # Show current status
        if [ "$health" = "starting" ]; then
            echo -e "    ${DIM}Health check in progress... (${elapsed}s/${max_wait}s)${NC}"
        elif [ "$health" = "unhealthy" ]; then
            echo -e "    ${YELLOW}Container unhealthy, waiting... (${elapsed}s/${max_wait}s)${NC}"
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    # Timeout reached
    echo -e "  ${YELLOW}⚠ Warning: ${container_name} did not become healthy within ${max_wait}s${NC}"
    return 1
}

# Function to restart all containers sequentially (one by one)
restart_containers_sequential() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}                     RESTART ALL CONTAINERS (ONE BY ONE)${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Get all running containers
    local running_containers=$(docker ps --format "{{.ID}}" 2>/dev/null)

    if [ -z "$running_containers" ]; then
        echo -e "${YELLOW}No running containers to restart.${NC}\n"
        return
    fi

    local container_count=$(echo "$running_containers" | wc -l | tr -d ' ')
    echo -e "Found ${BOLD}${container_count}${NC} running container(s).\n"
    echo -e "${YELLOW}Note: This will wait for each container to become healthy before proceeding to the next.${NC}"
    echo -e "${YELLOW}Estimated time: ~$(( container_count * 15 )) seconds (depending on healthcheck configurations)${NC}\n"

    if ! confirm_action "restart all containers sequentially with health checks"; then
        return
    fi

    echo -e "\n${CYAN}Restarting containers with health monitoring...${NC}\n"

    local success_count=0
    local fail_count=0
    local timeout_count=0
    local current=0
    local container_list=""

    while IFS= read -r container_id; do
        if [ -z "$container_id" ]; then
            continue
        fi

        current=$((current + 1))
        local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')

        echo -e "${BOLD}[${current}/${container_count}]${NC} ${CYAN}Restarting:${NC} ${name}"

        if docker restart "$container_id" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓ Restart command sent${NC}"

            # Wait for container to become healthy
            if wait_for_container_health "$container_id" "$name"; then
                success_count=$((success_count + 1))
                container_list="${container_list}  - ${name} (success)\n"
            else
                timeout_count=$((timeout_count + 1))
                container_list="${container_list}  - ${name} (timeout)\n"
                echo -e "  ${YELLOW}⚠ Container restarted but may not be fully ready${NC}"
            fi
        else
            echo -e "  ${RED}✗ Failed to restart${NC} ${name}"
            fail_count=$((fail_count + 1))
            container_list="${container_list}  - ${name} (failed)\n"
        fi

        echo ""
    done <<< "$running_containers"

    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Results Summary:${NC}"
    echo -e "  ${GREEN}Successfully restarted and healthy:${NC} ${success_count}"
    if [ $timeout_count -gt 0 ]; then
        echo -e "  ${YELLOW}Restarted but health timeout:${NC} ${timeout_count}"
    fi
    if [ $fail_count -gt 0 ]; then
        echo -e "  ${RED}Failed to restart:${NC} ${fail_count}"
    fi
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Send email notification if available
    if [ "$EMAIL_NOTIFICATIONS_AVAILABLE" = true ] && type send_container_restart_email >/dev/null 2>&1; then
        send_container_restart_email \
            "Sequential" \
            "$container_count" \
            "$success_count" \
            "$fail_count" \
            "$timeout_count" \
            "$container_list"
    fi
}

# Function to restart all containers in parallel (simultaneously)
restart_containers_parallel() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}                     FORCE RESTART ALL CONTAINERS (SIMULTANEOUS)${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Get all running containers
    local running_containers=$(docker ps --format "{{.ID}}" 2>/dev/null)

    if [ -z "$running_containers" ]; then
        echo -e "${YELLOW}No running containers to restart.${NC}\n"
        return
    fi

    # Convert container IDs to array
    local container_array=()
    local container_names=()

    while IFS= read -r container_id; do
        if [ -z "$container_id" ]; then
            continue
        fi
        container_array+=("$container_id")
        local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')
        container_names+=("$name")
    done <<< "$running_containers"

    local container_count=${#container_array[@]}
    echo -e "Found ${BOLD}${container_count}${NC} running container(s).\n"

    # Display container names
    echo -e "${BOLD}Containers to restart:${NC}"
    for name in "${container_names[@]}"; do
        echo -e "  - ${name}"
    done
    echo ""

    if ! confirm_action "force-restart all containers simultaneously"; then
        return
    fi

    echo -e "\n${CYAN}Force-restarting all containers simultaneously...${NC}\n"

    local success_count=0
    local fail_count=0
    local container_list=""

    # Execute single docker restart command with all container IDs
    if docker restart "${container_array[@]}" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Successfully restarted all ${container_count} container(s) simultaneously${NC}\n"
        success_count=$container_count
        # Build container list
        for name in "${container_names[@]}"; do
            container_list="${container_list}  - ${name} (success)\n"
        done
    else
        echo -e "${RED}✗ Failed to restart containers${NC}\n"
        echo -e "${YELLOW}Some containers may have been restarted. Check status for details.${NC}\n"
        fail_count=$container_count
        # Build container list
        for name in "${container_names[@]}"; do
            container_list="${container_list}  - ${name} (failed)\n"
        done
    fi

    # Send email notification if available
    if [ "$EMAIL_NOTIFICATIONS_AVAILABLE" = true ] && type send_container_restart_email >/dev/null 2>&1; then
        send_container_restart_email \
            "Parallel" \
            "$container_count" \
            "$success_count" \
            "$fail_count" \
            "0" \
            "$container_list"
    fi
}

# Function to kill unhealthy containers
kill_unhealthy_containers() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}                     KILL UNHEALTHY CONTAINERS${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Get all running containers
    local all_containers=$(docker ps --format "{{.ID}}" 2>/dev/null)

    if [ -z "$all_containers" ]; then
        echo -e "${YELLOW}No running containers found.${NC}\n"
        return
    fi

    # Find unhealthy containers
    local unhealthy_containers=""
    local unhealthy_names=""

    while IFS= read -r container_id; do
        if [ -z "$container_id" ]; then
            continue
        fi

        local health=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "none")

        if [ "$health" = "unhealthy" ]; then
            local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')
            unhealthy_containers="${unhealthy_containers}${container_id}\n"
            unhealthy_names="${unhealthy_names}  - ${name}\n"
        fi
    done <<< "$all_containers"

    if [ -z "$unhealthy_containers" ]; then
        echo -e "${GREEN}No unhealthy containers found. All containers are healthy!${NC}\n"
        return
    fi

    local unhealthy_count=$(echo -e "$unhealthy_containers" | grep -v '^$' | wc -l | tr -d ' ')
    echo -e "Found ${BOLD}${RED}${unhealthy_count}${NC} unhealthy container(s):\n"
    echo -e "$unhealthy_names"

    if ! confirm_action "kill these unhealthy containers"; then
        return
    fi

    echo -e "\n${CYAN}Killing unhealthy containers...${NC}\n"

    local success_count=0
    local fail_count=0
    local container_list=""

    while IFS= read -r container_id; do
        if [ -z "$container_id" ]; then
            continue
        fi

        local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')
        echo -e "  ${CYAN}Killing:${NC} ${name}"

        if docker kill "$container_id" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓ Successfully killed${NC} ${name}"
            success_count=$((success_count + 1))
            container_list="${container_list}  - ${name} (killed successfully)\n"
        else
            echo -e "  ${RED}✗ Failed to kill${NC} ${name}"
            fail_count=$((fail_count + 1))
            container_list="${container_list}  - ${name} (failed to kill)\n"
        fi
    done <<< "$(echo -e "$unhealthy_containers")"

    echo ""
    echo -e "${BOLD}Results:${NC}"
    echo -e "  ${GREEN}Success:${NC} ${success_count}"
    if [ $fail_count -gt 0 ]; then
        echo -e "  ${RED}Failed:${NC} ${fail_count}"
    fi
    echo ""

    # Send email notification if available
    if [ "$EMAIL_NOTIFICATIONS_AVAILABLE" = true ] && type send_container_kill_email >/dev/null 2>&1; then
        send_container_kill_email \
            "$unhealthy_count" \
            "$success_count" \
            "$fail_count" \
            "$container_list"
    fi
}

# Function to stop all containers
stop_all_containers() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}                     STOP ALL CONTAINERS${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Get all running containers
    local running_containers=$(docker ps --format "{{.ID}}" 2>/dev/null)

    if [ -z "$running_containers" ]; then
        echo -e "${YELLOW}No running containers to stop.${NC}\n"
        return
    fi

    local container_count=$(echo "$running_containers" | wc -l | tr -d ' ')
    echo -e "Found ${BOLD}${container_count}${NC} running container(s).\n"

    if ! confirm_action "stop all containers"; then
        return
    fi

    echo -e "\n${CYAN}Stopping containers...${NC}\n"

    local success_count=0
    local fail_count=0

    while IFS= read -r container_id; do
        if [ -z "$container_id" ]; then
            continue
        fi

        local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')
        echo -e "  ${CYAN}Stopping:${NC} ${name}"

        if docker stop "$container_id" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓ Successfully stopped${NC} ${name}"
            success_count=$((success_count + 1))
        else
            echo -e "  ${RED}✗ Failed to stop${NC} ${name}"
            fail_count=$((fail_count + 1))
        fi
    done <<< "$running_containers"

    echo ""
    echo -e "${BOLD}Results:${NC}"
    echo -e "  ${GREEN}Success:${NC} ${success_count}"
    if [ $fail_count -gt 0 ]; then
        echo -e "  ${RED}Failed:${NC} ${fail_count}"
    fi
    echo ""
}

# Interactive menu function
show_management_menu() {
    while true; do
        echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}${CYAN}                     CONTAINER MANAGEMENT MENU${NC}"
        echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

        echo -e "${BOLD}What would you like to do?${NC}\n"
        echo -e "  ${CYAN}1)${NC} Restart all containers (one by one)"
        echo -e "  ${CYAN}2)${NC} Force-restart all containers (simultaneous)"
        echo -e "  ${CYAN}3)${NC} Kill unhealthy containers"
        echo -e "  ${CYAN}4)${NC} Stop all containers"
        echo -e "  ${CYAN}5)${NC} Refresh status display"
        echo -e "  ${CYAN}6)${NC} Exit"
        echo ""

        read -p "Enter your choice [1-6]: " choice
        echo ""

        case $choice in
            1)
                restart_containers_sequential
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read
                ;;
            2)
                restart_containers_parallel
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read
                ;;
            3)
                kill_unhealthy_containers
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read
                ;;
            4)
                stop_all_containers
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read
                ;;
            5)
                clear
                show_container_status
                ;;
            6)
                echo -e "${GREEN}Exiting. Goodbye!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 1 and 6.${NC}\n"
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read
                ;;
        esac
    done
}

# Run the main function
show_container_status

# Show interactive menu
show_management_menu

exit 0
