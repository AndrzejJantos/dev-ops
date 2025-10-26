#!/bin/bash

# CheaperForDrug API Deployment Script
# Domain: cheaperfordrug.com
# Type: Rails API with background processing

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG="$SCRIPT_DIR/config.sh"

# Source common configuration and utilities
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$DEVOPS_DIR/common/utils.sh"
source "$DEVOPS_DIR/common/db-utils.sh"
source "$DEVOPS_DIR/common/docker-utils.sh"
source "$DEVOPS_DIR/common/rails/deploy.sh"

# Load application-specific configuration
if [ -f "$APP_CONFIG" ]; then
    source "$APP_CONFIG"
    log_success "Environment loaded from $APP_CONFIG"
else
    log_error "Configuration file not found: $APP_CONFIG"
    exit 1
fi

# Override or extend functions here if needed for API-specific behavior
# For now, we use the standard Rails deployment functions

# Custom status display for API
handle_status() {
    log_info "Checking status of ${APP_DISPLAY_NAME} containers"

    # Get all containers (web + workers + scheduler)
    local all_containers=($(docker ps -a --filter "name=${APP_NAME}" --format "{{.Names}}" 2>/dev/null))

    if [ ${#all_containers[@]} -eq 0 ]; then
        log_warning "No containers found for ${APP_NAME}"
        echo ""
        echo "To deploy the application, run:"
        echo "  ./deploy.sh deploy"
        exit 0
    fi

    # Print table header
    echo ""
    printf "%-40s %-15s %-20s %-20s %-15s\n" "CONTAINER NAME" "STATUS" "PORTS" "STARTED" "UPTIME"
    echo "--------------------------------------------------------------------------------------------------------"

    for container in "${all_containers[@]}"; do
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
        local ports=$(docker port "$container" 2>/dev/null | grep -oP '\d+:\d+' | head -1 || echo "-")

        if [ "$status" = "running" ]; then
            local started=$(docker inspect -f '{{.State.StartedAt}}' "$container" 2>/dev/null)
            local now_ts=$(date +%s)
            local started_ts=$(date -d "$started" +%s 2>/dev/null || echo "$now_ts")
            local seconds=$(( now_ts - started_ts ))

            # Format start time
            started_time=$(date -d "$started" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "-")

            # Format uptime
            if [ $seconds -lt 0 ] || [ $seconds -gt 31536000 ]; then
                running_time="?"
            elif [ $seconds -lt 60 ]; then
                running_time="${seconds}s"
            elif [ $seconds -lt 3600 ]; then
                running_time="$(($seconds / 60))m"
            elif [ $seconds -lt 86400 ]; then
                running_time="$(($seconds / 3600))h $(($seconds % 3600 / 60))m"
            else
                running_time="$(($seconds / 86400))d $(($seconds % 86400 / 3600))h"
            fi

            printf "%-40s \033[32m%-15s\033[0m %-20s %-20s %-15s\n" "$container" "$status" "$ports" "$started_time" "$running_time"
        else
            printf "%-40s \033[31m%-15s\033[0m %-20s %-20s %-15s\n" "$container" "$status" "$ports" "-" "-"
        fi
    done

    echo ""
    echo "Summary:"
    echo "  Web containers:       $(docker ps --filter "name=${APP_NAME}_web" --format "{{.Names}}" | wc -l | tr -d ' ') running"
    echo "  Worker containers:    $(docker ps --filter "name=${APP_NAME}_worker" --format "{{.Names}}" | wc -l | tr -d ' ') running"
    echo "  Scheduler:            $(docker ps --filter "name=${APP_NAME}_scheduler" --format "{{.Names}}" | wc -l | tr -d ' ') running"
    echo ""

    echo "Useful commands:"
    echo "  View API logs:        docker logs ${APP_NAME}_web_1 -f"
    echo "  View worker logs:     docker logs ${APP_NAME}_worker_1 -f"
    echo "  View scheduler logs:  docker logs ${APP_NAME}_scheduler -f"
    echo "  Rails console:        docker exec -it ${APP_NAME}_web_1 rails console"
    echo "  Check health:         curl https://${DOMAIN}${HEALTH_CHECK_PATH}"
    echo "  Scale web:            ./deploy.sh scale <number>"
    echo "  Deploy:               ./deploy.sh deploy"
    echo "  Restart:              ./deploy.sh restart"
    echo ""

    exit 0
}

# Update nginx upstream configuration when scaling
update_nginx_upstream() {
    local new_scale="$1"

    log_info "Updating Nginx upstream configuration for ${new_scale} web containers..."

    local nginx_template="$SCRIPT_DIR/nginx.conf.template"
    local nginx_config="/etc/nginx/sites-available/$APP_NAME"

    # Backup current config
    sudo cp "$nginx_config" "${nginx_config}.backup" 2>/dev/null || true

    # Generate new upstream servers list
    local UPSTREAM_SERVERS=""
    for i in $(seq 1 $new_scale); do
        local PORT=$((BASE_PORT + i - 1))
        UPSTREAM_SERVERS="${UPSTREAM_SERVERS}    server localhost:${PORT} max_fails=3 fail_timeout=30s;\n"
    done

    # Remove trailing newline
    UPSTREAM_SERVERS=$(echo -e "$UPSTREAM_SERVERS" | sed '$ s/\\n$//')

    # Generate nginx config from template
    cat "$nginx_template" | \
        sed "s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g" | \
        sed "s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|g" | \
        sed "s|{{DOMAIN}}|${DOMAIN}|g" | \
        sed "s|{{APP_NAME}}|${APP_NAME}|g" | \
        sudo tee "$nginx_config" > /dev/null

    # Test nginx configuration
    if sudo nginx -t 2>&1 | grep -q "successful"; then
        sudo systemctl reload nginx
        log_success "Nginx configuration updated successfully"
        log_info "Nginx now routing to ${new_scale} containers (ports ${BASE_PORT}-$((BASE_PORT + new_scale - 1)))"
        return 0
    else
        log_error "Nginx configuration test failed, restoring backup"
        sudo mv "${nginx_config}.backup" "$nginx_config"
        sudo systemctl reload nginx
        return 1
    fi
}

# Handle deployment commands
handle_deploy() {
    rails_deploy_application "$DEFAULT_SCALE"
}

handle_restart() {
    local current_count=$(get_container_count "$APP_NAME")
    if [ $current_count -eq 0 ]; then
        log_error "No containers running. Use 'deploy' instead of 'restart'"
        exit 1
    fi
    rails_restart_application "$current_count"
}

handle_stop() {
    rails_stop_application
}

handle_scale() {
    local target_scale="$1"

    if [ -z "$target_scale" ]; then
        log_error "Usage: $0 scale <number>"
        exit 1
    fi

    if ! [[ "$target_scale" =~ ^[0-9]+$ ]] || [ "$target_scale" -lt 1 ] || [ "$target_scale" -gt 10 ]; then
        log_error "Scale must be a number between 1 and 10"
        exit 1
    fi

    rails_scale_application "$target_scale"

    # Update nginx upstream configuration
    update_nginx_upstream "$target_scale"

    if [ $? -eq 0 ]; then
        log_success "Scaled to ${target_scale} containers successfully"
        log_success "Nginx now routing to all ${target_scale} containers"
        exit 0
    else
        log_error "Failed to update Nginx configuration"
        exit 1
    fi
}

handle_console() {
    rails_run_console
}

handle_task() {
    local task="$1"
    if [ -z "$task" ]; then
        log_error "Usage: $0 task <rails_task>"
        exit 1
    fi
    rails_run_task "$task"
}

handle_logs() {
    local container="${1:-${APP_NAME}_web_1}"
    log_info "Showing logs for $container (Ctrl+C to exit)"
    docker logs -f "$container"
}

# Main command handler
case "${1:-help}" in
    deploy)
        handle_deploy
        ;;
    restart)
        handle_restart
        ;;
    stop)
        handle_stop
        ;;
    scale)
        handle_scale "$2"
        ;;
    status)
        handle_status
        ;;
    console)
        handle_console
        ;;
    task)
        handle_task "$2"
        ;;
    logs)
        handle_logs "$2"
        ;;
    ssl-setup)
        log_info "Setting up SSL certificates for API subdomains"
        log_info "Installing certificates for ${DOMAIN_PUBLIC} and ${DOMAIN_INTERNAL}"
        sudo certbot --nginx -d "$DOMAIN_PUBLIC" -d "$DOMAIN_INTERNAL"
        ;;
    help|*)
        echo "CheaperForDrug API Deployment Script"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  deploy              Pull latest code, build, and deploy application"
        echo "  restart             Restart all running containers with current image"
        echo "  stop                Stop all containers"
        echo "  scale <N>           Scale web containers to N instances (1-10)"
        echo "  status              Show status of all containers"
        echo "  console             Open Rails console in running container"
        echo "  task <task>         Run a Rails task (e.g., 'db:migrate')"
        echo "  logs [container]    Show logs (default: ${APP_NAME}_web_1)"
        echo "  ssl-setup           Setup SSL certificates with Let's Encrypt"
        echo "  help                Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 deploy           # Deploy latest code"
        echo "  $0 scale 5          # Scale to 5 web containers"
        echo "  $0 status           # Show container status"
        echo "  $0 console          # Open Rails console"
        echo "  $0 logs worker_1    # Show worker logs"
        echo ""
        exit 0
        ;;
esac
