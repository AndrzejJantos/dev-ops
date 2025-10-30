#!/bin/bash

# ============================================================================
# CheaperForDrug Scraper - Ultimate Setup Script
# ============================================================================
# This is the ONLY script you need to setup, deploy, and manage the scraper.
#
# Usage:
#   ./setup.sh                 - Interactive setup + deploy
#   ./setup.sh --deploy        - Deploy (skip setup checks)
#   ./setup.sh --rebuild       - Rebuild images and deploy
#   ./setup.sh --stop          - Stop all containers
#   ./setup.sh --restart       - Restart all containers
#   ./setup.sh --clean         - Stop and remove everything
#   ./setup.sh --status        - Show container status
#   ./setup.sh --logs          - Show logs
#   ./setup.sh --help          - Show this help
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURATION
# ============================================================================

# Get script directory (absolute path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Application configuration
APP_NAME="cheaperfordrug-scraper"
APP_DIR="${HOME}/apps/${APP_NAME}"
REPO_DIR="${APP_DIR}/repo"
REPO_URL="git@github.com:AndrzejJantos/cheaperfordrug-scraper.git"
REPO_BRANCH="master"

# Docker configuration
DOCKER_IMAGE_NAME="${APP_NAME}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Container names
CONTAINER_POLAND="cheaperfordrug-scraper-poland"
CONTAINER_GERMANY="cheaperfordrug-scraper-germany"
CONTAINER_CZECH="cheaperfordrug-scraper-czech"

# DevOps directory (for scripts)
DEVOPS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo ""
    echo "================================================================"
    echo "$1"
    echo "================================================================"
    echo ""
}

# ============================================================================
# EMAIL NOTIFICATION FUNCTIONS
# ============================================================================

send_deployment_email() {
    local status="$1"
    local duration="$2"
    local error_message="${3:-}"

    # Skip if no API key
    if [ -z "${SENDGRID_API_KEY:-}" ]; then
        log_info "Skipping email notification (SENDGRID_API_KEY not set)"
        return 0
    fi

    log_info "Sending deployment email notification..."

    # Generate email subject
    local subject
    if [ "${status}" = "success" ]; then
        subject="[CheaperForDrug Scraper] Deployment Completed Successfully"
    else
        subject="[CheaperForDrug Scraper] Deployment FAILED"
    fi

    # Generate email body
    local body
    if [ "${status}" = "success" ]; then
        body=$("${SCRIPT_DIR}/.scripts/deployment-summary.sh" "success" "${duration}")
    else
        body=$("${SCRIPT_DIR}/.scripts/deployment-summary.sh" "failure" "${duration}" "${error_message}")
    fi

    # Send email
    if "${SCRIPT_DIR}/.scripts/send-email.sh" "${subject}" "${body}"; then
        log_success "Email notification sent"
        return 0
    else
        log_warning "Failed to send email notification (deployment status: ${status})"
        return 0  # Don't fail deployment if email fails
    fi
}

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

check_nordvpn_token() {
    log_info "Checking NordVPN token..."

    if [ -z "${NORDVPN_TOKEN:-}" ]; then
        log_error "NORDVPN_TOKEN environment variable is not set!"
        echo ""
        echo "To set up your NordVPN token:"
        echo ""
        echo "1. Get your token from: https://my.nordaccount.com/dashboard/nordvpn/access-tokens/"
        echo ""
        echo "2. Add to your shell profile (~/.bashrc, ~/.zshrc, or ~/.bash_profile):"
        echo "   ${GREEN}export NORDVPN_TOKEN=\"your_token_here\"${NC}"
        echo ""
        echo "3. Reload your shell:"
        echo "   ${GREEN}source ~/.bashrc${NC}  # or source ~/.zshrc"
        echo ""
        echo "4. Run this script again"
        echo ""
        exit 1
    fi

    log_success "NordVPN token is set"
}

check_docker() {
    log_info "Checking Docker..."

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed!"
        echo ""
        echo "Please install Docker: https://docs.docker.com/get-docker/"
        echo ""
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running!"
        echo ""
        echo "Please start Docker and try again."
        echo ""
        exit 1
    fi

    log_success "Docker is installed and running"
}

check_docker_compose() {
    log_info "Checking docker-compose..."

    # Check for docker-compose (standalone) first
    if command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
        log_success "docker-compose is installed (standalone)"
        return 0
    fi

    # Check for docker compose (plugin)
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
        log_success "docker compose is installed (plugin)"
        return 0
    fi

    # Neither found
    log_error "docker-compose is not installed!"
    echo ""
    echo "Please install docker-compose:"
    echo "  - Plugin (recommended): Already included with Docker Desktop"
    echo "  - Standalone: https://docs.docker.com/compose/install/"
    echo ""
    exit 1
}

check_git() {
    log_info "Checking git..."

    if ! command -v git >/dev/null 2>&1; then
        log_error "git is not installed!"
        echo ""
        echo "Please install git first."
        echo ""
        exit 1
    fi

    log_success "git is installed"
}

check_all_prerequisites() {
    log_header "Checking Prerequisites"

    check_docker
    check_docker_compose
    check_git
    check_nordvpn_token

    log_success "All prerequisites met!"
}

# ============================================================================
# DIRECTORY SETUP
# ============================================================================

create_directories() {
    log_info "Creating directory structure..."

    # Main directories
    mkdir -p "${APP_DIR}"
    mkdir -p "${APP_DIR}/backups"
    mkdir -p "${APP_DIR}/docker-images"

    # Country-specific directories
    for country in poland germany czech; do
        mkdir -p "${APP_DIR}/logs/${country}"
        mkdir -p "${APP_DIR}/outputs/${country}"
        mkdir -p "${APP_DIR}/state/${country}"
    done

    log_success "Directory structure created"
}

# ============================================================================
# REPOSITORY MANAGEMENT
# ============================================================================

clone_or_update_repo() {
    log_info "Checking repository..."

    if [ -d "${REPO_DIR}/.git" ]; then
        log_info "Repository exists, updating..."
        cd "${REPO_DIR}"
        git fetch origin

        # Get current and latest commit
        CURRENT_COMMIT=$(git rev-parse HEAD)
        LATEST_COMMIT=$(git rev-parse origin/"${REPO_BRANCH}")

        if [ "${CURRENT_COMMIT}" = "${LATEST_COMMIT}" ]; then
            log_success "Already at latest commit"
        else
            log_info "Pulling latest changes..."
            git checkout "${REPO_BRANCH}"
            git pull origin "${REPO_BRANCH}"
            log_success "Repository updated"
        fi
    else
        log_info "Cloning repository..."
        git clone -b "${REPO_BRANCH}" "${REPO_URL}" "${REPO_DIR}"
        log_success "Repository cloned"
    fi
}

# ============================================================================
# DOCKER BUILD
# ============================================================================

build_docker_images() {
    log_info "Building Docker images..."

    cd "${REPO_DIR}"

    # Generate timestamped tag for versioning
    TIMESTAMP_TAG="$(date +%Y%m%d-%H%M%S)"

    # Copy docker files to build context
    log_info "Preparing build context..."
    cp -r "${SCRIPT_DIR}/.docker/"* "${REPO_DIR}/"

    # Build image
    log_info "Building image: ${DOCKER_IMAGE_NAME}:${TIMESTAMP_TAG}"

    if docker build \
        -t "${DOCKER_IMAGE_NAME}:${TIMESTAMP_TAG}" \
        -t "${DOCKER_IMAGE_NAME}:latest" \
        -f "${REPO_DIR}/Dockerfile" \
        "${REPO_DIR}"; then
        log_success "Docker image built successfully"

        # Export the tag for docker-compose
        export IMAGE_TAG="${TIMESTAMP_TAG}"
    else
        log_error "Failed to build Docker image"
        return 1
    fi
}

# ============================================================================
# CONTAINER MANAGEMENT
# ============================================================================

stop_containers() {
    log_info "Stopping containers..."

    cd "${REPO_DIR}"

    if ${DOCKER_COMPOSE_CMD} -f "${SCRIPT_DIR}/docker-compose.yml" down --timeout 30 2>/dev/null; then
        log_success "Containers stopped"
    else
        log_warning "No containers to stop or error occurred"
    fi
}

start_containers() {
    log_info "Starting containers..."

    cd "${REPO_DIR}"

    # Export required environment variables
    export DOCKER_IMAGE_NAME
    export IMAGE_TAG
    export APP_DIR
    export DEVOPS_DIR
    export NORDVPN_TOKEN
    export SCRAPER_AUTH_TOKEN="${SCRAPER_AUTH_TOKEN:-Andrzej12345}"
    export API_TOKEN="${API_TOKEN:-${SCRAPER_AUTH_TOKEN}}"

    # Start containers
    if ${DOCKER_COMPOSE_CMD} -f "${SCRIPT_DIR}/docker-compose.yml" up -d; then
        log_success "Containers started"
    else
        log_error "Failed to start containers"
        return 1
    fi
}

restart_containers() {
    stop_containers
    sleep 2
    start_containers
}

clean_everything() {
    log_warning "This will stop and remove all containers, images, and volumes!"
    read -p "Are you sure? (yes/no): " -r
    echo

    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Cancelled"
        return 0
    fi

    log_info "Cleaning up..."

    # Stop and remove containers
    stop_containers

    # Remove images
    docker images "${DOCKER_IMAGE_NAME}" -q | xargs -r docker rmi -f 2>/dev/null || true

    log_success "Cleanup complete"
}

# ============================================================================
# STATUS AND MONITORING
# ============================================================================

show_status() {
    log_header "Container Status"

    if ! docker ps -a | grep -q "${APP_NAME}"; then
        log_warning "No containers found"
        return 0
    fi

    # Show container status
    docker ps -a --filter "name=${APP_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    echo ""
    log_info "Health Status:"
    echo ""

    for container in "${CONTAINER_POLAND}" "${CONTAINER_GERMANY}" "${CONTAINER_CZECH}"; do
        if docker ps --filter "name=${container}" --format "{{.Names}}" | grep -q "${container}"; then
            health=$(docker inspect --format='{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "no healthcheck")
            status=$(docker inspect --format='{{.State.Status}}' "${container}")

            if [ "${health}" = "healthy" ]; then
                echo -e "  ${GREEN}●${NC} ${container}: ${status} (${health})"
            elif [ "${health}" = "unhealthy" ]; then
                echo -e "  ${RED}●${NC} ${container}: ${status} (${health})"
            else
                echo -e "  ${YELLOW}●${NC} ${container}: ${status} (${health})"
            fi
        else
            echo -e "  ${RED}●${NC} ${container}: not running"
        fi
    done

    echo ""
}

show_logs() {
    log_header "Container Logs"

    if [ -f "${SCRIPT_DIR}/.scripts/watch-logs.sh" ]; then
        exec bash "${SCRIPT_DIR}/.scripts/watch-logs.sh" all
    else
        # Fallback to docker compose logs
        ${DOCKER_COMPOSE_CMD} -f "${SCRIPT_DIR}/docker-compose.yml" logs --tail=50 -f
    fi
}

# ============================================================================
# DEPLOYMENT WORKFLOW
# ============================================================================

full_setup() {
    log_header "CheaperForDrug Scraper - Initial Setup"

    # Track deployment start time
    local start_time
    start_time=$(date +%s)

    # Check prerequisites
    check_all_prerequisites

    # Create directories
    create_directories

    # Clone or update repository
    clone_or_update_repo

    # Build Docker images
    build_docker_images

    # Start containers
    start_containers

    # Wait for healthy status
    sleep 10

    # Show status
    show_status

    # Calculate deployment duration
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Send success email notification
    send_deployment_email "success" "${duration}"

    # Print success message
    log_header "Setup Complete!"

    echo "Your scraper is now running!"
    echo ""
    echo "Useful commands:"
    echo "  ${GREEN}./setup.sh --status${NC}         - Check container status"
    echo "  ${GREEN}./setup.sh --logs${NC}           - Watch container logs"
    echo "  ${GREEN}./setup.sh --restart${NC}        - Restart containers"
    echo "  ${GREEN}npm run scrapers:watch${NC}      - Watch all scraper logs"
    echo "  ${GREEN}npm run scrapers:start${NC}      - Start scraper manually"
    echo ""
    echo "Scheduled runs: Monday and Thursday at 7:00 AM (automatic)"
    echo ""
}

deploy_only() {
    log_header "Deploying CheaperForDrug Scraper"

    # Track deployment start time
    local start_time
    start_time=$(date +%s)

    # Set error trap for deployment failure
    set +e
    trap 'deployment_error_handler $?' ERR

    # Quick prerequisite check
    check_nordvpn_token
    check_docker

    # Update repository
    if ! clone_or_update_repo; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        send_deployment_email "failure" "${duration}" "Failed to clone or update repository"
        return 1
    fi

    # Build images
    if ! build_docker_images; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        send_deployment_email "failure" "${duration}" "Failed to build Docker images"
        return 1
    fi

    # Restart containers
    if ! restart_containers; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        send_deployment_email "failure" "${duration}" "Failed to restart containers"
        return 1
    fi

    # Reset error handling
    set -e
    trap - ERR

    # Wait for healthy status
    sleep 10

    # Show status
    show_status

    # Calculate deployment duration
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Send success email notification
    send_deployment_email "success" "${duration}"

    log_success "Deployment complete!"
}

rebuild_deploy() {
    log_header "Rebuilding and Deploying"

    # Track deployment start time
    local start_time
    start_time=$(date +%s)

    # Set error trap for deployment failure
    set +e
    trap 'deployment_error_handler $?' ERR

    # Quick prerequisite check
    check_nordvpn_token
    check_docker

    # Update repository
    if ! clone_or_update_repo; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        send_deployment_email "failure" "${duration}" "Failed to clone or update repository"
        return 1
    fi

    # Force rebuild images
    log_info "Forcing image rebuild..."
    docker images "${DOCKER_IMAGE_NAME}" -q | xargs -r docker rmi -f 2>/dev/null || true

    # Build images
    if ! build_docker_images; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        send_deployment_email "failure" "${duration}" "Failed to rebuild Docker images"
        return 1
    fi

    # Restart containers
    if ! restart_containers; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        send_deployment_email "failure" "${duration}" "Failed to restart containers"
        return 1
    fi

    # Reset error handling
    set -e
    trap - ERR

    # Wait for healthy status
    sleep 10

    # Show status
    show_status

    # Calculate deployment duration
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Send success email notification
    send_deployment_email "success" "${duration}"

    log_success "Rebuild and deployment complete!"
}

# ============================================================================
# HELP
# ============================================================================

show_help() {
    cat << EOF

CheaperForDrug Scraper - Ultimate Setup Script
===============================================

Usage: ./setup.sh [COMMAND]

COMMANDS:
  (no args)          Run interactive setup and deployment
  --deploy           Deploy latest code (skip setup checks)
  --rebuild          Rebuild Docker images and deploy
  --stop             Stop all containers
  --restart          Restart all containers
  --clean            Stop and remove everything (interactive)
  --status           Show container status and health
  --logs             Show and follow container logs
  --help             Show this help message

EXAMPLES:
  ./setup.sh                    # First time setup
  ./setup.sh --deploy           # Update and deploy
  ./setup.sh --status           # Check status
  ./setup.sh --logs             # Watch logs

PREREQUISITES:
  1. Set NORDVPN_TOKEN environment variable in your shell profile
  2. Docker and docker-compose must be installed
  3. Git must be installed

For more information, see README.md or .docs/ directory.

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    case "${1:-}" in
        "")
            # No arguments - full setup
            full_setup
            ;;
        --deploy)
            deploy_only
            ;;
        --rebuild)
            rebuild_deploy
            ;;
        --stop)
            log_header "Stopping Containers"
            stop_containers
            log_success "All containers stopped"
            ;;
        --restart)
            log_header "Restarting Containers"
            restart_containers
            sleep 10
            show_status
            ;;
        --clean)
            log_header "Cleanup"
            clean_everything
            ;;
        --status)
            show_status
            ;;
        --logs)
            show_logs
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main with all arguments
main "$@"
