#!/bin/bash

# CheaperForDrug Scraper Deployment Script (DevOps wrapper)
# Wraps the scraper repo's deploy.sh for integration with DevOps orchestrator
#
# Usage:
#   ./deploy.sh deploy          # Pull latest code and start all enabled containers
#   ./deploy.sh start           # Start all enabled containers
#   ./deploy.sh stop            # Stop all containers
#   ./deploy.sh restart         # Restart all enabled containers
#   ./deploy.sh status          # Show container status
#   ./deploy.sh logs [name]     # View logs
#   ./deploy.sh start-workers   # Start only product update workers (all countries)
#   ./deploy.sh stop-workers    # Stop only product update workers (all countries)

set -e

# Get script directory and DevOps root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load app configuration
APP_CONFIG="$SCRIPT_DIR/config.sh"
if [ -f "$APP_CONFIG" ]; then
    source "$APP_CONFIG"
else
    log_error "Configuration file not found: $APP_CONFIG"
    exit 1
fi

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

check_requirements() {
    log_info "Checking requirements..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed"
        exit 1
    fi

    if [ ! -d "$SCRAPER_REPO_DIR" ]; then
        log_error "Scraper repo not found: $SCRAPER_REPO_DIR"
        exit 1
    fi

    if [ ! -f "$SCRAPER_REPO_DIR/deploy.sh" ]; then
        log_error "Scraper deploy.sh not found: $SCRAPER_REPO_DIR/deploy.sh"
        exit 1
    fi

    log_success "Requirements OK"
}

pull_latest_code() {
    log_info "Pulling latest scraper code..."

    cd "$SCRAPER_REPO_DIR"
    if [ -d ".git" ]; then
        git fetch origin "${SCRAPER_REPO_BRANCH:-master}" 2>/dev/null || true
        git reset --hard origin/"${SCRAPER_REPO_BRANCH:-master}" 2>/dev/null || true
        log_success "Scraper code updated to latest ${SCRAPER_REPO_BRANCH:-master}"
    else
        log_warning "Not a git repo, skipping pull"
    fi
}

run_scraper_deploy() {
    local command="$1"
    shift

    cd "$SCRAPER_REPO_DIR"
    chmod +x deploy.sh
    ./deploy.sh "$command" "$@"
}

# =============================================================================
# WORKER MANAGEMENT
# =============================================================================

# Read scraper-config.env and return list of enabled worker container names
get_enabled_workers() {
    local config_file="$SCRAPER_REPO_DIR/scraper-config.env"
    local country_filter="${1:-}"

    if [ ! -f "$config_file" ]; then
        log_error "Config file not found: $config_file"
        return 1
    fi

    grep -E '^ENABLE_WORKER_.*=true' "$config_file" | while IFS='=' read -r key _; do
        # ENABLE_WORKER_POLAND_1 -> poland 1
        local stripped="${key#ENABLE_WORKER_}"
        local num="${stripped##*_}"
        local country="${stripped%_*}"
        country=$(echo "$country" | tr '[:upper:]' '[:lower:]')

        if [ -n "$country_filter" ] && [ "$country" != "$country_filter" ]; then
            continue
        fi

        echo "product-update-worker-${country}-${num}"
    done
}

do_start_workers() {
    local country_filter="${1:-}"
    local filter_msg=""
    [ -n "$country_filter" ] && filter_msg=" for $country_filter"

    log_info "=== Starting Product Update Workers${filter_msg} ==="

    local workers
    workers=$(get_enabled_workers "$country_filter")

    if [ -z "$workers" ]; then
        log_warning "No enabled workers found${filter_msg}"
        log_info "Configure workers in: $SCRAPER_REPO_DIR/scraper-config.env"
        return 0
    fi

    local count
    count=$(echo "$workers" | wc -l | tr -d ' ')
    log_info "Found $count enabled worker(s)${filter_msg}:"
    echo "$workers" | while read -r w; do
        echo "  - $w"
    done
    echo ""

    cd "$SCRAPER_REPO_DIR"

    # Ensure required directories exist
    echo "$workers" | while read -r w; do
        local country=$(echo "$w" | sed 's/product-update-worker-//' | sed 's/-[0-9]*$//')
        mkdir -p "logs/$country" "logs/product-worker-${country}-$(echo "$w" | grep -oP '\d+$')" \
                 "nordvpn-data/$w" 2>/dev/null || true
    done

    # Start all enabled workers
    # shellcheck disable=SC2086
    docker compose up -d $workers

    echo ""
    log_success "Started $count worker(s)${filter_msg}"

    # Show status
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep product-update-worker || true
}

do_stop_workers() {
    local country_filter="${1:-}"
    local filter_msg=""
    [ -n "$country_filter" ] && filter_msg=" for $country_filter"

    log_info "=== Stopping Product Update Workers${filter_msg} ==="

    cd "$SCRAPER_REPO_DIR"

    if [ -n "$country_filter" ]; then
        local workers
        workers=$(docker ps --format '{{.Names}}' | grep "product-update-worker-${country_filter}" || true)
        if [ -z "$workers" ]; then
            log_warning "No running workers found${filter_msg}"
            return 0
        fi
        # shellcheck disable=SC2086
        docker stop $workers
        log_success "Stopped workers${filter_msg}"
    else
        local workers
        workers=$(docker ps --format '{{.Names}}' | grep "product-update-worker" || true)
        if [ -z "$workers" ]; then
            log_warning "No running workers found"
            return 0
        fi
        # shellcheck disable=SC2086
        docker stop $workers
        log_success "Stopped all workers"
    fi
}

do_rebuild_workers() {
    local country_filter="${1:-}"
    local filter_msg=""
    [ -n "$country_filter" ] && filter_msg=" for $country_filter"

    log_info "=== Rebuilding Product Update Workers${filter_msg} ==="

    check_requirements
    pull_latest_code

    cd "$SCRAPER_REPO_DIR"

    # Rebuild the shared scraper image
    log_info "Building Docker image..."
    docker compose build product-update-worker-poland-1 2>&1 | tail -5
    log_success "Image rebuilt"

    # Stop existing workers
    do_stop_workers "$country_filter"

    # Remove dead containers
    log_info "Cleaning dead containers..."
    sudo find /var/lib/docker/containers/ -name 'resolv.conf' -exec chattr -i {} \; 2>/dev/null || true
    docker ps -a --filter 'status=dead' --format '{{.Names}}' | grep product-update-worker | xargs docker rm -f 2>/dev/null || true

    # Start enabled workers
    do_start_workers "$country_filter"

    echo ""
    log_success "=== Worker Rebuild Complete${filter_msg} ==="
}

# =============================================================================
# COMMANDS
# =============================================================================

do_deploy() {
    log_info "=== Deploying CheaperForDrug Scraper ==="
    echo ""

    check_requirements
    pull_latest_code

    cd "$SCRAPER_REPO_DIR"

    # Build Docker image first
    log_info "Building Docker image..."
    docker compose build --quiet 2>&1 | tail -5
    log_success "Docker image built"

    # Force kill all scraper containers to avoid immutable resolv.conf issues from NordVPN
    log_info "Stopping and removing all scraper containers..."
    docker compose down --remove-orphans 2>/dev/null || true

    # Clean up any stuck containers (NordVPN sets immutable flag on resolv.conf)
    local stuck_ids=$(docker ps -aq --filter "status=removing" --filter "status=dead" 2>/dev/null)
    if [ -n "$stuck_ids" ]; then
        log_warning "Cleaning up stuck containers..."
        for cid in $stuck_ids; do
            local full_id=$(docker inspect -f '{{.ID}}' "$cid" 2>/dev/null || echo "")
            if [ -n "$full_id" ]; then
                sudo chattr -i "/var/lib/docker/containers/${full_id}/resolv.conf" 2>/dev/null || true
            fi
            docker rm -f "$cid" 2>/dev/null || true
        done
    fi

    # Get list of enabled services from scraper-config.env
    local config_file="$SCRAPER_REPO_DIR/scraper-config.env"
    if [ ! -f "$config_file" ]; then
        log_error "Config file not found: $config_file"
        exit 1
    fi
    source "$config_file"

    local services=()

    # Collect enabled VPN containers
    for key in $(env | grep -oP '^ENABLE_VPN_\w+(?==true)'); do
        local country="${key#ENABLE_VPN_}"
        country=$(echo "$country" | tr '[:upper:]' '[:lower:]')
        services+=("scraper-vpn-${country}")
    done

    # Collect enabled worker containers
    for key in $(env | grep -oP '^ENABLE_WORKER_\w+(?==true)'); do
        local stripped="${key#ENABLE_WORKER_}"
        local num="${stripped##*_}"
        local country="${stripped%_*}"
        country=$(echo "$country" | tr '[:upper:]' '[:lower:]')
        services+=("product-update-worker-${country}-${num}")
    done

    if [ ${#services[@]} -eq 0 ]; then
        log_error "No services enabled in $config_file"
        exit 1
    fi

    local total=${#services[@]}
    log_info "Starting $total containers with 1-minute delay between each..."
    echo ""

    local current=0
    for svc in "${services[@]}"; do
        current=$((current + 1))
        log_info "[$current/$total] Starting $svc..."
        docker compose up -d "$svc" 2>&1 | grep -v "^$" || true

        if [ $current -lt $total ]; then
            log_info "Waiting 60s before next container..."
            sleep 60
        fi
    done

    echo ""
    log_info "All $total containers started. Checking status..."
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E '(scraper-vpn-|product-update-worker-)' | sort
    echo ""
    log_success "=== Scraper Deployment Complete ($total containers) ==="
}

do_start() {
    check_requirements
    run_scraper_deploy start
}

do_stop() {
    check_requirements
    run_scraper_deploy stop
}

do_restart() {
    check_requirements
    run_scraper_deploy restart
}

do_status() {
    check_requirements
    run_scraper_deploy status
}

do_logs() {
    check_requirements
    run_scraper_deploy logs "${1:-}"
}

show_usage() {
    echo ""
    echo "CheaperForDrug Scraper Deployment (DevOps)"
    echo "============================================"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy              Pull latest code and start all enabled containers"
    echo "  start               Start all enabled containers"
    echo "  stop                Stop all containers"
    echo "  restart             Restart all enabled containers"
    echo "  rebuild             Rebuild Docker images and restart"
    echo "  cleanup             Force remove stuck/orphaned containers"
    echo "  status              Show container status"
    echo "  logs [container]    View logs (all or specific container)"
    echo "  help                Show this help"
    echo ""
    echo "Worker commands (reads ENABLE_WORKER_* from scraper-config.env):"
    echo "  start-workers [country]     Start enabled product update workers"
    echo "  stop-workers [country]      Stop product update workers"
    echo "  rebuild-workers [country]   Pull code, rebuild image, restart workers"
    echo ""
    echo "Examples:"
    echo "  $0 deploy                   # Full deployment (pull + start)"
    echo "  $0 rebuild-workers          # Rebuild and restart all enabled workers"
    echo "  $0 rebuild-workers poland   # Rebuild and restart only Poland workers"
    echo "  $0 start-workers italy      # Start only Italy workers"
    echo "  $0 stop-workers             # Stop all workers"
    echo "  $0 status                   # Show all container status"
    echo ""
    echo "Configuration:"
    echo "  Workers config: $SCRAPER_REPO_DIR/scraper-config.env"
    echo "  Docker compose: $SCRAPER_REPO_DIR/docker-compose.yml"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

case "${1:-help}" in
    deploy)
        do_deploy
        ;;
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_restart
        ;;
    status)
        do_status
        ;;
    logs)
        do_logs "${2:-}"
        ;;
    start-workers)
        check_requirements
        do_start_workers "${2:-}"
        ;;
    stop-workers)
        check_requirements
        do_stop_workers "${2:-}"
        ;;
    rebuild-workers)
        do_rebuild_workers "${2:-}"
        ;;
    rebuild|cleanup|countries)
        check_requirements
        run_scraper_deploy "$1"
        ;;
    start-*|stop-*|restart-*|logs-*)
        # Pass country-specific commands through to scraper deploy.sh
        check_requirements
        run_scraper_deploy "$@"
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
