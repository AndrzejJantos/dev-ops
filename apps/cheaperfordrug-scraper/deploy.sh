#!/bin/bash

# ============================================================================
# CheaperForDrug Scraper Deployment Script
# ============================================================================
#
# This script deploys and manages Docker containerized scrapers (Poland, Germany, Czech)
# with integrated NordVPN and cron scheduling.
#
# Usage:
#   ./deploy.sh build          # Build Docker image
#   ./deploy.sh up             # Start all containers
#   ./deploy.sh down           # Stop and remove containers
#   ./deploy.sh restart        # Restart all containers
#   ./deploy.sh logs [service] # View logs (optional: specific service)
#   ./deploy.sh status         # Show container status
#   ./deploy.sh rebuild        # Rebuild and restart everything
#
# Requirements:
#   - Docker and Docker Compose installed
#   - .env file in ~/apps/cheaperfordrug-scraper/.env with:
#       API_ENDPOINT, SCRAPER_AUTH_TOKEN, SEND_TO_API, HEADLESS
#   - NordVPN token (set NORDVPN_TOKEN environment variable)
#
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# CONFIGURATION
# ============================================================================

# Paths (adjust if needed)
APP_DIR="${HOME}/apps/cheaperfordrug-scraper"
DEVOPS_DIR="${HOME}/DevOps"
DOCKER_COMPOSE_FILE="${DEVOPS_DIR}/apps/cheaperfordrug-scraper/docker-compose.yml"
ENV_FILE="${APP_DIR}/.env"

# Docker image configuration
DOCKER_IMAGE_NAME="cheaperfordrug-scraper"
IMAGE_TAG="latest"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_color() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo ""
    print_color "$BLUE" "============================================================================"
    print_color "$BLUE" "$1"
    print_color "$BLUE" "============================================================================"
}

check_requirements() {
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_color "$RED" "Error: Docker is not installed"
        exit 1
    fi

    # Check if Docker Compose is installed
    if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
        print_color "$RED" "Error: Docker Compose is not installed"
        exit 1
    fi

    # Check if .env file exists
    if [ ! -f "$ENV_FILE" ]; then
        print_color "$RED" "Error: .env file not found at $ENV_FILE"
        print_color "$YELLOW" "Please create .env file with required variables:"
        print_color "$YELLOW" "  API_ENDPOINT, SCRAPER_AUTH_TOKEN, SEND_TO_API, HEADLESS"
        exit 1
    fi

    # Check if docker-compose.yml exists
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_color "$RED" "Error: docker-compose.yml not found at $DOCKER_COMPOSE_FILE"
        exit 1
    fi

    # Check if NORDVPN_TOKEN is set (can be in host environment or .env file)
    if [ -z "$NORDVPN_TOKEN" ]; then
        print_color "$YELLOW" "Warning: NORDVPN_TOKEN environment variable is not set in host environment"
        print_color "$YELLOW" "VPN will not work without this token"
        print_color "$YELLOW" "Set it with: export NORDVPN_TOKEN='your_token_here' in ~/.bashrc or ~/.profile"
    else
        print_color "$GREEN" "✓ NORDVPN_TOKEN found in host environment"
    fi
}

load_env() {
    print_color "$GREEN" "Loading environment variables from $ENV_FILE"

    # Load variables from .env file, but preserve existing environment variables
    # This allows host environment variables (like NORDVPN_TOKEN) to take precedence
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key ]] && continue

        # Only set if not already set in environment
        if [ -z "${!key}" ]; then
            export "$key=$value"
        fi
    done < <(grep -v '^#' "$ENV_FILE" | grep -v '^[[:space:]]*$')

    # Export Docker-specific variables
    export APP_DIR
    export DEVOPS_DIR
    export DOCKER_IMAGE_NAME
    export IMAGE_TAG
    export HOME

    print_color "$GREEN" "Environment variables loaded successfully"

    # Show which important variables are set
    if [ -n "$NORDVPN_TOKEN" ]; then
        print_color "$GREEN" "  ✓ NORDVPN_TOKEN: loaded from host environment"
    fi
    if [ -n "$API_ENDPOINT" ]; then
        print_color "$GREEN" "  ✓ API_ENDPOINT: $API_ENDPOINT"
    fi
}

# ============================================================================
# DOCKER COMMANDS
# ============================================================================

docker_build() {
    print_header "Building Docker Image: ${DOCKER_IMAGE_NAME}:${IMAGE_TAG}"

    cd "$DEVOPS_DIR/apps/cheaperfordrug-scraper"

    # Build from Dockerfile in .docker directory
    if [ -f ".docker/Dockerfile" ]; then
        docker build -f .docker/Dockerfile -t "${DOCKER_IMAGE_NAME}:${IMAGE_TAG}" "${APP_DIR}/repo"
        print_color "$GREEN" "✓ Docker image built successfully"
    else
        print_color "$RED" "Error: Dockerfile not found at .docker/Dockerfile"
        exit 1
    fi
}

docker_up() {
    print_header "Starting Scraper Containers"

    cd "$DEVOPS_DIR/apps/cheaperfordrug-scraper"

    # Start containers in detached mode
    docker compose -f "$DOCKER_COMPOSE_FILE" up -d

    print_color "$GREEN" "✓ Containers started successfully"
    echo ""
    docker_status
}

docker_down() {
    print_header "Stopping Scraper Containers"

    cd "$DEVOPS_DIR/apps/cheaperfordrug-scraper"

    docker compose -f "$DOCKER_COMPOSE_FILE" down

    print_color "$GREEN" "✓ Containers stopped and removed"
}

docker_restart() {
    print_header "Restarting Scraper Containers"

    cd "$DEVOPS_DIR/apps/cheaperfordrug-scraper"

    docker compose -f "$DOCKER_COMPOSE_FILE" restart

    print_color "$GREEN" "✓ Containers restarted successfully"
    echo ""
    docker_status
}

docker_logs() {
    service="${1:-}"

    if [ -z "$service" ]; then
        print_header "Container Logs (all services)"
        docker compose -f "$DOCKER_COMPOSE_FILE" logs --tail=50 --follow
    else
        print_header "Container Logs: $service"
        docker compose -f "$DOCKER_COMPOSE_FILE" logs --tail=50 --follow "$service"
    fi
}

docker_status() {
    print_header "Container Status"

    docker compose -f "$DOCKER_COMPOSE_FILE" ps

    echo ""
    print_color "$BLUE" "Container Details:"
    docker ps --filter "name=cheaperfordrug-scraper" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

docker_rebuild() {
    print_header "Rebuilding Everything"

    docker_down
    docker_build
    docker_up

    print_color "$GREEN" "✓ Rebuild complete"
}

docker_deploy() {
    print_header "Deploying Scraper Containers"

    # Check if image exists
    if docker images "${DOCKER_IMAGE_NAME}:${IMAGE_TAG}" | grep -q "${DOCKER_IMAGE_NAME}"; then
        print_color "$YELLOW" "Image ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} already exists"
        print_color "$YELLOW" "Use './deploy.sh rebuild' to force rebuild"
        echo ""
    else
        print_color "$GREEN" "Image not found, building..."
        docker_build
        echo ""
    fi

    # Check if containers are running
    RUNNING_CONTAINERS=$(docker ps --filter "name=cheaperfordrug-scraper" --format "{{.Names}}" | wc -l)
    if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
        print_color "$YELLOW" "Found $RUNNING_CONTAINERS running scraper container(s)"
        print_color "$YELLOW" "Stopping existing containers..."
        docker_down
        echo ""
    fi

    # Start containers
    print_color "$GREEN" "Starting containers..."
    docker_up

    echo ""
    print_header "Deployment Complete!"

    # Provide helpful next steps
    print_color "$GREEN" "Scraper containers are now running with:"
    print_color "$GREEN" "  ✓ NordVPN connection per country"
    print_color "$GREEN" "  ✓ Internal cron scheduling"
    print_color "$GREEN" "  ✓ API connection to localhost:4200"
    echo ""
    print_color "$BLUE" "Useful commands:"
    print_color "$BLUE" "  ./deploy.sh logs             - View all logs"
    print_color "$BLUE" "  ./deploy.sh logs scraper-poland - View Poland logs"
    print_color "$BLUE" "  ./deploy.sh status           - Check container status"
    print_color "$BLUE" "  ./deploy.sh restart          - Restart containers"
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

print_header "CheaperForDrug Scraper Deployment"

# Check requirements
check_requirements

# Load environment variables
load_env

# Parse command (default to deploy if no command given)
COMMAND="${1:-deploy}"

case "$COMMAND" in
    deploy)
        docker_deploy
        ;;
    build)
        docker_build
        ;;
    up|start)
        docker_up
        ;;
    down|stop)
        docker_down
        ;;
    restart)
        docker_restart
        ;;
    logs)
        docker_logs "${2:-}"
        ;;
    status|ps)
        docker_status
        ;;
    rebuild)
        docker_rebuild
        ;;
    help|--help|-h)
        print_color "$GREEN" "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  deploy         Full deployment (build if needed + start containers)"
        echo "  build          Build Docker image"
        echo "  up|start       Start all containers"
        echo "  down|stop      Stop and remove containers"
        echo "  restart        Restart all containers"
        echo "  logs [service] View logs (optional: specific service name)"
        echo "  status|ps      Show container status"
        echo "  rebuild        Rebuild image and restart containers"
        echo "  help           Show this help message"
        echo ""
        echo "Services:"
        echo "  scraper-poland    Poland scraper container"
        echo "  scraper-germany   Germany scraper container"
        echo "  scraper-czech     Czech Republic scraper container"
        echo ""
        echo "Examples:"
        echo "  $0 deploy                     # Full deployment (recommended)"
        echo "  $0 build                      # Build the image only"
        echo "  $0 up                         # Start all scrapers"
        echo "  $0 logs scraper-poland        # View Poland scraper logs"
        echo "  $0 restart                    # Restart all containers"
        echo ""
        echo "Environment:"
        echo "  .env file: $ENV_FILE"
        echo "  NORDVPN_TOKEN: ${NORDVPN_TOKEN:+SET}${NORDVPN_TOKEN:-NOT SET}"
        ;;
    *)
        print_color "$RED" "Unknown command: $COMMAND"
        print_color "$YELLOW" "Run '$0 help' for usage information"
        exit 1
        ;;
esac

echo ""
print_color "$GREEN" "Done!"
