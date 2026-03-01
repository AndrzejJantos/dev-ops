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
# COMMANDS
# =============================================================================

do_deploy() {
    log_info "=== Deploying CheaperForDrug Scraper ==="
    echo ""

    check_requirements
    pull_latest_code

    log_info "Starting all enabled containers..."
    run_scraper_deploy start

    echo ""
    log_success "=== Scraper Deployment Complete ==="
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
    echo "Country-specific commands (passed to scraper deploy.sh):"
    echo "  start-<country>           Start VPN + worker for country"
    echo "  stop-<country>            Stop VPN + worker for country"
    echo "  start-workers-<country>   Start only worker for country"
    echo "  stop-workers-<country>    Stop only worker for country"
    echo ""
    echo "Examples:"
    echo "  $0 deploy                 # Full deployment (pull + start)"
    echo "  $0 start-poland           # Start Poland VPN + worker"
    echo "  $0 status                 # Show all container status"
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
