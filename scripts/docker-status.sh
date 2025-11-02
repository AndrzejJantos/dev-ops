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
            local started_ts=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${started:0:19}" "+%s" 2>/dev/null || echo "0")
            local current_ts=$(date "+%s")
            local diff=$((current_ts - started_ts))

            if [ $diff -lt 60 ]; then
                uptime="${diff}s"
            elif [ $diff -lt 3600 ]; then
                uptime="$((diff / 60))m"
            elif [ $diff -lt 86400 ]; then
                uptime="$((diff / 3600))h $((diff % 3600 / 60))m"
            else
                uptime="$((diff / 86400))d $((diff % 86400 / 3600))h"
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

    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Run the main function
show_container_status

exit 0
