#!/bin/bash
# =============================================================================
# Docker Build Performance Benchmark Script
# =============================================================================
# This script benchmarks Docker build performance to verify optimization
# improvements after cleanup and Dockerfile changes.
#
# Usage:
#   ./docker-build-benchmark.sh <app_directory>
#
# Example:
#   ./docker-build-benchmark.sh /path/to/rails/app
#
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
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

log_metric() {
    echo -e "${CYAN}[METRIC]${NC} $1"
}

# Display header
echo "============================================================================="
echo "  Docker Build Performance Benchmark"
echo "============================================================================="
echo ""

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <app_directory>"
    log_error "Example: $0 /home/app/my-rails-app"
    exit 1
fi

APP_DIR="${1}"
APP_NAME=$(basename "$APP_DIR")

# Validate directory
if [ ! -d "$APP_DIR" ]; then
    log_error "Directory not found: $APP_DIR"
    exit 1
fi

if [ ! -f "$APP_DIR/Dockerfile" ]; then
    log_error "Dockerfile not found in: $APP_DIR"
    exit 1
fi

cd "$APP_DIR"
log_info "Working directory: $APP_DIR"
log_info "Application: $APP_NAME"
echo ""

# =============================================================================
# Pre-build Information
# =============================================================================
log_info "=== Pre-Build System Status ==="
echo ""

# Docker version
log_info "Docker version:"
docker --version
echo ""

# Docker info
log_info "Docker storage driver:"
docker info 2>/dev/null | grep -E "(Storage Driver|Backing Filesystem)" || true
echo ""

# Check BuildKit status
if [ "${DOCKER_BUILDKIT:-0}" = "1" ]; then
    log_success "BuildKit is enabled"
else
    log_warning "BuildKit is NOT enabled (set DOCKER_BUILDKIT=1 for better performance)"
fi
echo ""

# Current disk usage
log_info "Current Docker disk usage:"
docker system df
echo ""

# Check overlay2 layers
if [ -d /var/lib/docker/overlay2 ]; then
    LAYER_COUNT=$(sudo find /var/lib/docker/overlay2 -maxdepth 1 -type d 2>/dev/null | wc -l || echo "N/A")
    log_metric "Overlay2 layers before build: $LAYER_COUNT"
else
    log_warning "Cannot access overlay2 directory (requires sudo)"
fi
echo ""

# =============================================================================
# Build Performance Test
# =============================================================================
log_info "=== Starting Build Performance Test ==="
echo ""

# Generate unique tag
BUILD_TAG="${APP_NAME}:benchmark-$(date +%s)"
log_info "Build tag: $BUILD_TAG"
echo ""

# Confirm before building
read -p "Ready to start build? This will build the Docker image. (Y/n): " -r
if [[ $REPLY =~ ^[Nn]$ ]]; then
    log_info "Build cancelled by user"
    exit 0
fi
echo ""

# Create a temporary file for detailed logs
LOG_FILE="/tmp/docker-build-benchmark-${APP_NAME}-$(date +%s).log"
log_info "Detailed build log: $LOG_FILE"
echo ""

# Start timing
START_TIME=$(date +%s)
START_TIME_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
log_info "Build started at: $START_TIME_HUMAN"
echo ""

# Run the build with timing and step-by-step output
log_info "Building image (this may take several minutes)..."
echo "-----------------------------------------------------------------------------"

if docker build \
    --progress=plain \
    --no-cache \
    -t "$BUILD_TAG" \
    . 2>&1 | tee "$LOG_FILE"; then

    # Calculate total time
    END_TIME=$(date +%s)
    TOTAL_TIME=$((END_TIME - START_TIME))
    END_TIME_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

    echo "-----------------------------------------------------------------------------"
    echo ""
    log_success "Build completed successfully!"
    echo ""

    # =============================================================================
    # Build Performance Analysis
    # =============================================================================
    log_info "=== Build Performance Analysis ==="
    echo ""

    # Total build time
    log_metric "Total build time: ${TOTAL_TIME}s ($(date -u -d @${TOTAL_TIME} +'%H:%M:%S' 2>/dev/null || date -u -r ${TOTAL_TIME} +'%H:%M:%S'))"
    log_metric "Started:  $START_TIME_HUMAN"
    log_metric "Finished: $END_TIME_HUMAN"
    echo ""

    # Analyze critical steps from log
    log_info "Analyzing critical steps..."
    echo ""

    # Find chown/chmod steps
    if grep -q "chown" "$LOG_FILE"; then
        log_info "Found chown operations:"
        grep -n "chown" "$LOG_FILE" | head -5
        echo ""
    fi

    if grep -q "chmod" "$LOG_FILE"; then
        log_info "Found chmod operations:"
        grep -n "chmod" "$LOG_FILE" | head -5
        echo ""
    fi

    # Find COPY operations
    log_info "COPY operations (checking for --chown usage):"
    grep -n "COPY" "$LOG_FILE" | head -10
    echo ""

    # Image size
    IMAGE_SIZE=$(docker images "$BUILD_TAG" --format "{{.Size}}")
    log_metric "Final image size: $IMAGE_SIZE"
    echo ""

    # Layer count
    LAYER_COUNT_IMAGE=$(docker history "$BUILD_TAG" 2>/dev/null | wc -l)
    log_metric "Image layers: $LAYER_COUNT_IMAGE"
    echo ""

    # Post-build overlay2 layers
    if [ -d /var/lib/docker/overlay2 ]; then
        LAYER_COUNT_AFTER=$(sudo find /var/lib/docker/overlay2 -maxdepth 1 -type d 2>/dev/null | wc -l || echo "N/A")
        log_metric "Overlay2 layers after build: $LAYER_COUNT_AFTER"
    fi
    echo ""

    # =============================================================================
    # Performance Assessment
    # =============================================================================
    log_info "=== Performance Assessment ==="
    echo ""

    # Assess build time
    if [ "$TOTAL_TIME" -lt 120 ]; then
        log_success "Excellent: Build time under 2 minutes"
    elif [ "$TOTAL_TIME" -lt 300 ]; then
        log_success "Good: Build time under 5 minutes"
    elif [ "$TOTAL_TIME" -lt 600 ]; then
        log_warning "Acceptable: Build time under 10 minutes"
    else
        log_warning "Slow: Build time over 10 minutes - further optimization needed"
    fi
    echo ""

    # Check for problematic patterns
    log_info "Checking for performance issues..."

    RECURSIVE_CHOWN=$(grep -c "chown -R" "$LOG_FILE" || true)
    RECURSIVE_CHMOD=$(grep -c "chmod -R" "$LOG_FILE" || true)

    if [ "$RECURSIVE_CHOWN" -gt 0 ] || [ "$RECURSIVE_CHMOD" -gt 0 ]; then
        log_warning "Found recursive operations (chown -R: $RECURSIVE_CHOWN, chmod -R: $RECURSIVE_CHMOD)"
        log_warning "Consider using --chown in COPY instructions instead"
    else
        log_success "No recursive chown/chmod operations detected"
    fi
    echo ""

    # BuildKit recommendation
    if [ "${DOCKER_BUILDKIT:-0}" != "1" ]; then
        echo "RECOMMENDATION: Enable BuildKit for better performance"
        echo "  export DOCKER_BUILDKIT=1"
        echo "  This enables improved caching and parallelization"
        echo ""
    fi

    # =============================================================================
    # Cleanup
    # =============================================================================
    log_info "=== Cleanup ==="
    echo ""

    read -p "Remove benchmark image? (Y/n): " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        docker rmi "$BUILD_TAG" >/dev/null 2>&1 || true
        log_success "Benchmark image removed"
    else
        log_info "Keeping benchmark image: $BUILD_TAG"
    fi
    echo ""

    log_info "Detailed build log saved to: $LOG_FILE"
    log_info "You can analyze it with: grep -E '(Step|chown|chmod|COPY)' $LOG_FILE"
    echo ""

    # =============================================================================
    # Summary and Recommendations
    # =============================================================================
    log_success "=== Benchmark Complete ==="
    echo ""
    echo "SUMMARY:"
    echo "  Total Time:  ${TOTAL_TIME}s"
    echo "  Image Size:  $IMAGE_SIZE"
    echo "  Layers:      $LAYER_COUNT_IMAGE"
    echo "  Build Log:   $LOG_FILE"
    echo ""

    exit 0

else
    # Build failed
    END_TIME=$(date +%s)
    TOTAL_TIME=$((END_TIME - START_TIME))

    echo "-----------------------------------------------------------------------------"
    echo ""
    log_error "Build failed after ${TOTAL_TIME}s"
    log_error "Check the log file for details: $LOG_FILE"
    echo ""
    exit 1
fi
