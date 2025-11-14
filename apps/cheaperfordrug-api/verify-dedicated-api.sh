#!/bin/bash

# Verification Script for Dedicated API Containers
# Checks prerequisites and tests all endpoints

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_info() {
    echo -e "${YELLOW}→${NC} $1"
}

echo "=============================================="
echo "Dedicated API Containers Verification"
echo "=============================================="
echo ""

# Check 1: Docker image exists
echo "1. Checking Docker image..."
if docker image inspect cheaperfordrug-api:latest > /dev/null 2>&1; then
    log_success "Docker image cheaperfordrug-api:latest found"
else
    log_error "Docker image not found"
    log_info "Run: cd $SCRIPT_DIR && ./deploy.sh deploy"
    exit 1
fi

# Check 2: Environment file exists
echo ""
echo "2. Checking environment configuration..."
if [ -f "$SCRIPT_DIR/.env.production" ]; then
    log_success "Environment file .env.production found"
else
    log_error "Environment file not found"
    log_info "Run: cd $SCRIPT_DIR && ./setup.sh"
    exit 1
fi

# Check 3: Docker Compose file exists
echo ""
echo "3. Checking Docker Compose configuration..."
if [ -f "$SCRIPT_DIR/docker-compose-dedicated-api.yml" ]; then
    log_success "Docker Compose file found"
else
    log_error "Docker Compose file not found"
    exit 1
fi

# Check 4: Deployment script exists
echo ""
echo "4. Checking deployment script..."
if [ -f "$SCRIPT_DIR/deploy-dedicated-api.sh" ] && [ -x "$SCRIPT_DIR/deploy-dedicated-api.sh" ]; then
    log_success "Deployment script found and executable"
else
    log_error "Deployment script not found or not executable"
    if [ -f "$SCRIPT_DIR/deploy-dedicated-api.sh" ]; then
        log_info "Run: chmod +x $SCRIPT_DIR/deploy-dedicated-api.sh"
    fi
    exit 1
fi

# Check 5: Port availability
echo ""
echo "5. Checking port availability..."
ports_in_use=()
for port in 4201 4202 4203 4204; do
    if lsof -i :$port > /dev/null 2>&1; then
        process=$(lsof -i :$port | tail -1 | awk '{print $1}')
        log_error "Port $port is in use by $process"
        ports_in_use+=($port)
    else
        log_success "Port $port is available"
    fi
done

if [ ${#ports_in_use[@]} -gt 0 ]; then
    log_info "Some ports are in use. Stop conflicting services or use different ports."
fi

# Check 6: Database connectivity
echo ""
echo "6. Checking database connectivity..."
if docker run --rm --network host \
    --env-file "$SCRIPT_DIR/.env.production" \
    cheaperfordrug-api:latest \
    /bin/bash -c "cd /app && bundle exec rails runner 'puts ActiveRecord::Base.connection.active?'" 2>&1 | grep -q "true"; then
    log_success "Database connection successful"
else
    log_error "Cannot connect to database"
    log_info "Check PostgreSQL is running: sudo systemctl status postgresql"
fi

# Check 7: Redis connectivity
echo ""
echo "7. Checking Redis connectivity..."
if docker run --rm --network host \
    --env-file "$SCRIPT_DIR/.env.production" \
    cheaperfordrug-api:latest \
    /bin/bash -c "cd /app && bundle exec rails runner 'puts Redis.new(url: ENV[\"REDIS_URL\"]).ping'" 2>&1 | grep -q "PONG"; then
    log_success "Redis connection successful"
else
    log_error "Cannot connect to Redis"
    log_info "Check Redis is running: sudo systemctl status redis"
fi

# Check 8: Container status
echo ""
echo "8. Checking if containers are running..."
containers=(
    "cheaperfordrug-api-product-read"
    "cheaperfordrug-api-product-write"
    "cheaperfordrug-api-product-write-sidekiq"
    "cheaperfordrug-api-normalizer"
    "cheaperfordrug-api-scraper"
    "cheaperfordrug-api-scraper-sidekiq"
)

running_count=0
stopped_count=0

for container in "${containers[@]}"; do
    if docker ps --filter "name=^${container}$" --format "{{.Names}}" | grep -q "^${container}$"; then
        status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
        if [ "$status" = "running" ]; then
            log_success "$container is running"
            running_count=$((running_count + 1))
        else
            log_error "$container exists but not running (status: $status)"
            stopped_count=$((stopped_count + 1))
        fi
    else
        log_info "$container not found (not started yet)"
        stopped_count=$((stopped_count + 1))
    fi
done

# Check 9: Health checks (if containers are running)
if [ $running_count -gt 0 ]; then
    echo ""
    echo "9. Testing health endpoints..."

    for port in 4201 4202 4203 4204; do
        name=""
        case $port in
            4201) name="Product Read" ;;
            4202) name="Product Write" ;;
            4203) name="Normalizer" ;;
            4204) name="Scraper" ;;
        esac

        if curl -sf "http://localhost:${port}/up" > /dev/null 2>&1; then
            log_success "$name (port $port) health check passed"
        else
            log_error "$name (port $port) health check failed"
        fi
    done
fi

# Summary
echo ""
echo "=============================================="
echo "Verification Summary"
echo "=============================================="
echo "Running containers: $running_count / ${#containers[@]}"

if [ $running_count -eq 0 ]; then
    echo ""
    log_info "To start containers, run:"
    echo "  $SCRIPT_DIR/deploy-dedicated-api.sh start"
elif [ $stopped_count -gt 0 ]; then
    echo ""
    log_info "Some containers are not running. To start all:"
    echo "  $SCRIPT_DIR/deploy-dedicated-api.sh restart"
else
    echo ""
    log_success "All containers are running!"
    echo ""
    echo "Useful commands:"
    echo "  Status:    $SCRIPT_DIR/deploy-dedicated-api.sh status"
    echo "  Logs:      $SCRIPT_DIR/deploy-dedicated-api.sh logs"
    echo "  Health:    $SCRIPT_DIR/deploy-dedicated-api.sh health"
    echo "  Restart:   $SCRIPT_DIR/deploy-dedicated-api.sh restart"
fi

echo ""
