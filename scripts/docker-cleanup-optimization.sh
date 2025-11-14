#!/bin/bash
# =============================================================================
# Docker Cleanup and Optimization Script
# =============================================================================
# This script performs comprehensive Docker cleanup to resolve performance
# issues caused by excessive overlay2 layers and build cache.
#
# PERFORMANCE ISSUE ADDRESSED:
# - Slow Docker builds (10+ minutes on chmod/chown)
# - Excessive overlay2 layers (25+)
# - Large build cache (25GB+)
# - Uninterruptible I/O wait ("D" state processes)
#
# Usage:
#   ./docker-cleanup-optimization.sh [--aggressive]
#
# Options:
#   --aggressive    Remove all images (not just dangling), requires rebuilding
#
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Display header
echo "============================================================================="
echo "  Docker Cleanup and Optimization Script"
echo "============================================================================="
echo ""

# Parse arguments
AGGRESSIVE=false
if [[ "${1:-}" == "--aggressive" ]]; then
    AGGRESSIVE=true
    log_warning "Aggressive mode enabled - will remove ALL images"
    echo ""
fi

# Check if running as root or with Docker permissions
if ! docker info >/dev/null 2>&1; then
    log_error "Cannot connect to Docker daemon. Please ensure:"
    log_error "1. Docker is running"
    log_error "2. You have permission to run Docker commands"
    log_error "3. Try running with 'sudo' if necessary"
    exit 1
fi

# =============================================================================
# PHASE 1: Collect Current Status
# =============================================================================
log_info "Phase 1: Collecting current Docker status..."
echo ""

# Get disk usage before cleanup
log_info "Current Docker disk usage:"
docker system df
echo ""

# Get overlay2 directory size (if accessible)
if [ -d /var/lib/docker/overlay2 ]; then
    OVERLAY_SIZE=$(du -sh /var/lib/docker/overlay2 2>/dev/null | cut -f1 || echo "N/A")
    log_info "Overlay2 directory size: $OVERLAY_SIZE"

    # Count overlay2 layers
    LAYER_COUNT=$(find /var/lib/docker/overlay2 -maxdepth 1 -type d 2>/dev/null | wc -l || echo "N/A")
    log_info "Number of overlay2 layers: $LAYER_COUNT"
else
    log_warning "Cannot access /var/lib/docker/overlay2 (may need sudo)"
fi
echo ""

# Check for stopped containers
STOPPED_CONTAINERS=$(docker ps -aq -f status=exited -f status=created 2>/dev/null | wc -l)
log_info "Stopped containers: $STOPPED_CONTAINERS"

# Check for dangling images
DANGLING_IMAGES=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
log_info "Dangling images: $DANGLING_IMAGES"

# Check for unused volumes
UNUSED_VOLUMES=$(docker volume ls -qf dangling=true 2>/dev/null | wc -l)
log_info "Unused volumes: $UNUSED_VOLUMES"

echo ""
read -p "Press Enter to continue with cleanup or Ctrl+C to abort..."
echo ""

# =============================================================================
# PHASE 2: Stop All Running Containers (Optional)
# =============================================================================
log_info "Phase 2: Checking running containers..."

RUNNING_CONTAINERS=$(docker ps -q | wc -l)
if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
    log_warning "Found $RUNNING_CONTAINERS running container(s)"
    echo ""
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    echo ""
    read -p "Do you want to stop all running containers? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Stopping all running containers..."
        docker stop $(docker ps -q) || true
        log_success "All containers stopped"
    else
        log_info "Skipping container stop"
    fi
else
    log_info "No running containers found"
fi
echo ""

# =============================================================================
# PHASE 3: Remove Stopped Containers
# =============================================================================
log_info "Phase 3: Removing stopped containers..."

if [ "$STOPPED_CONTAINERS" -gt 0 ]; then
    docker container prune -f
    log_success "Removed $STOPPED_CONTAINERS stopped container(s)"
else
    log_info "No stopped containers to remove"
fi
echo ""

# =============================================================================
# PHASE 4: Remove Dangling Images
# =============================================================================
log_info "Phase 4: Removing dangling images..."

if [ "$DANGLING_IMAGES" -gt 0 ]; then
    docker image prune -f
    log_success "Removed $DANGLING_IMAGES dangling image(s)"
else
    log_info "No dangling images to remove"
fi
echo ""

# =============================================================================
# PHASE 5: Clean Build Cache
# =============================================================================
log_info "Phase 5: Cleaning build cache..."

# Get build cache size before
BUILD_CACHE_BEFORE=$(docker system df -v | grep "Build Cache" | awk '{print $4}' || echo "0")

# Clean build cache (keep cache from last 24 hours)
docker builder prune -f --filter "until=24h"

log_success "Build cache cleaned (kept last 24 hours)"
echo ""

# =============================================================================
# PHASE 6: Aggressive Cleanup (Optional)
# =============================================================================
if [ "$AGGRESSIVE" = true ]; then
    log_warning "Phase 6: Aggressive cleanup - removing ALL unused images..."
    echo ""
    log_warning "This will remove:"
    log_warning "  - All images not used by at least one container"
    log_warning "  - All build cache"
    log_warning "  - You will need to rebuild your images"
    echo ""
    read -p "Are you sure you want to continue? (yes/NO): " -r

    if [[ $REPLY == "yes" ]]; then
        # Remove all unused images
        docker image prune -a -f
        log_success "Removed all unused images"

        # Remove all build cache
        docker builder prune -a -f
        log_success "Removed all build cache"
    else
        log_info "Skipping aggressive cleanup"
    fi
else
    log_info "Phase 6: Skipped (use --aggressive flag for complete cleanup)"
fi
echo ""

# =============================================================================
# PHASE 7: Remove Unused Volumes (with confirmation)
# =============================================================================
log_info "Phase 7: Checking unused volumes..."

if [ "$UNUSED_VOLUMES" -gt 0 ]; then
    log_warning "Found $UNUSED_VOLUMES unused volume(s)"
    read -p "Do you want to remove unused volumes? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker volume prune -f
        log_success "Removed unused volumes"
    else
        log_info "Skipping volume cleanup"
    fi
else
    log_info "No unused volumes to remove"
fi
echo ""

# =============================================================================
# PHASE 8: Remove Unused Networks
# =============================================================================
log_info "Phase 8: Removing unused networks..."

docker network prune -f
log_success "Removed unused networks"
echo ""

# =============================================================================
# PHASE 9: Collect Final Status
# =============================================================================
log_info "Phase 9: Collecting final Docker status..."
echo ""

log_success "=== CLEANUP COMPLETE ==="
echo ""
docker system df
echo ""

if [ -d /var/lib/docker/overlay2 ]; then
    OVERLAY_SIZE_AFTER=$(du -sh /var/lib/docker/overlay2 2>/dev/null | cut -f1 || echo "N/A")
    log_success "Overlay2 directory size after cleanup: $OVERLAY_SIZE_AFTER"

    LAYER_COUNT_AFTER=$(find /var/lib/docker/overlay2 -maxdepth 1 -type d 2>/dev/null | wc -l || echo "N/A")
    log_success "Number of overlay2 layers after cleanup: $LAYER_COUNT_AFTER"
fi
echo ""

# =============================================================================
# PHASE 10: Recommendations
# =============================================================================
log_info "=== RECOMMENDATIONS ==="
echo ""

echo "1. Build Performance Optimization:"
echo "   - Use multi-stage builds (already implemented)"
echo "   - Set ownership during COPY (--chown flag)"
echo "   - Avoid recursive chown/chmod on large directories"
echo "   - Use .dockerignore to exclude unnecessary files"
echo ""

echo "2. Docker Storage Driver Optimization:"
echo "   - Current driver: $(docker info 2>/dev/null | grep 'Storage Driver' | cut -d: -f2 | xargs)"
echo "   - overlay2 is optimal for most workloads"
echo "   - For RAID/network storage, consider fuse-overlayfs"
echo ""

echo "3. BuildKit Optimization (if available):"
echo "   - Enable BuildKit: export DOCKER_BUILDKIT=1"
echo "   - Better caching and parallelization"
echo "   - Faster builds with improved layer sharing"
echo ""

echo "4. Regular Maintenance:"
echo "   - Run 'docker system prune -f' weekly"
echo "   - Run 'docker builder prune -f --filter until=168h' weekly"
echo "   - Monitor disk usage: 'docker system df -v'"
echo ""

echo "5. Next Steps:"
echo "   - Rebuild your images with the optimized Dockerfile"
echo "   - Test build performance: time docker build ..."
echo "   - Expected improvement: Step 32 should complete in seconds"
echo ""

log_success "Cleanup completed successfully!"
echo ""
echo "To verify the improvement, rebuild your Docker images and time the build process."
echo "Example: time docker build -t myapp:latest ."
echo ""
