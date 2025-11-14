#!/bin/bash
# =============================================================================
# Deploy Docker Optimization to Server
# =============================================================================
# Quick deployment script to upload and run Docker optimization on server
#
# Usage:
#   ./deploy-docker-optimization.sh <server> [--aggressive]
#
# Examples:
#   ./deploy-docker-optimization.sh user@hetzner.example.com
#   ./deploy-docker-optimization.sh user@hetzner.example.com --aggressive
#
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Display header
echo "============================================================================="
echo "  Deploy Docker Optimization to Server"
echo "============================================================================="
echo ""

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <server> [--aggressive]"
    log_error "Example: $0 user@hetzner.example.com"
    exit 1
fi

SERVER="$1"
AGGRESSIVE_FLAG="${2:-}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log_info "DevOps root: $DEVOPS_ROOT"
log_info "Target server: $SERVER"

if [ -n "$AGGRESSIVE_FLAG" ]; then
    log_warning "Aggressive cleanup mode enabled"
fi
echo ""

# Verify cleanup script exists
CLEANUP_SCRIPT="$SCRIPT_DIR/docker-cleanup-optimization.sh"
if [ ! -f "$CLEANUP_SCRIPT" ]; then
    log_error "Cleanup script not found: $CLEANUP_SCRIPT"
    exit 1
fi

# Verify benchmark script exists
BENCHMARK_SCRIPT="$SCRIPT_DIR/docker-build-benchmark.sh"
if [ ! -f "$BENCHMARK_SCRIPT" ]; then
    log_error "Benchmark script not found: $BENCHMARK_SCRIPT"
    exit 1
fi

# Test SSH connection
log_info "Testing SSH connection to $SERVER..."
if ! ssh -o ConnectTimeout=10 "$SERVER" "echo 'Connection successful'" >/dev/null 2>&1; then
    log_error "Cannot connect to $SERVER"
    log_error "Please check:"
    log_error "  1. Server address is correct"
    log_error "  2. SSH keys are set up"
    log_error "  3. Server is accessible"
    exit 1
fi
log_success "SSH connection verified"
echo ""

# Create temporary directory on server
log_info "Creating temporary directory on server..."
REMOTE_TMP="/tmp/docker-optimization-$(date +%s)"
ssh "$SERVER" "mkdir -p $REMOTE_TMP"
log_success "Remote directory: $REMOTE_TMP"
echo ""

# Upload scripts
log_info "Uploading optimization scripts..."
scp "$CLEANUP_SCRIPT" "$SERVER:$REMOTE_TMP/" >/dev/null
scp "$BENCHMARK_SCRIPT" "$SERVER:$REMOTE_TMP/" >/dev/null
ssh "$SERVER" "chmod +x $REMOTE_TMP/*.sh"
log_success "Scripts uploaded and made executable"
echo ""

# Display pre-cleanup status
log_info "Fetching current Docker status from server..."
echo "-----------------------------------------------------------------------------"
ssh "$SERVER" "docker system df 2>/dev/null || echo 'Docker status unavailable'"
echo "-----------------------------------------------------------------------------"
echo ""

# Confirm before proceeding
read -p "Proceed with Docker cleanup on $SERVER? (Y/n): " -r
if [[ $REPLY =~ ^[Nn]$ ]]; then
    log_info "Deployment cancelled by user"
    ssh "$SERVER" "rm -rf $REMOTE_TMP"
    exit 0
fi
echo ""

# Run cleanup script
log_info "Running Docker cleanup on server..."
log_info "This may take several minutes depending on Docker usage..."
echo "-----------------------------------------------------------------------------"

if [ -n "$AGGRESSIVE_FLAG" ]; then
    ssh "$SERVER" "sudo $REMOTE_TMP/docker-cleanup-optimization.sh --aggressive" || true
else
    ssh "$SERVER" "sudo $REMOTE_TMP/docker-cleanup-optimization.sh" || true
fi

echo "-----------------------------------------------------------------------------"
echo ""
log_success "Docker cleanup completed"
echo ""

# Display post-cleanup status
log_info "Fetching updated Docker status..."
echo "-----------------------------------------------------------------------------"
ssh "$SERVER" "docker system df 2>/dev/null || echo 'Docker status unavailable'"
echo "-----------------------------------------------------------------------------"
echo ""

# Ask about benchmark
echo ""
read -p "Do you want to keep scripts on server for benchmarking? (Y/n): " -r
if [[ $REPLY =~ ^[Nn]$ ]]; then
    ssh "$SERVER" "rm -rf $REMOTE_TMP"
    log_success "Temporary files removed from server"
else
    log_success "Scripts available at: $SERVER:$REMOTE_TMP/"
    echo ""
    echo "To run benchmark on an app:"
    echo "  ssh $SERVER"
    echo "  sudo $REMOTE_TMP/docker-build-benchmark.sh /path/to/your/app"
    echo ""
    echo "To manually clean up later:"
    echo "  ssh $SERVER sudo rm -rf $REMOTE_TMP"
fi
echo ""

# Final recommendations
log_success "=== Deployment Complete ==="
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Rebuild your applications to test performance:"
echo "   ssh $SERVER"
echo "   cd /path/to/your/app"
echo "   time docker build -t myapp:latest ."
echo ""
echo "2. Verify the chown/chmod step completes in seconds (not minutes)"
echo ""
echo "3. Consider enabling BuildKit for additional performance:"
echo "   echo 'export DOCKER_BUILDKIT=1' >> ~/.bashrc"
echo ""
echo "4. Set up weekly cleanup cron job:"
echo "   0 2 * * 0 /usr/bin/docker system prune -f"
echo ""
echo "5. Monitor build performance with benchmark script:"
echo "   sudo $REMOTE_TMP/docker-build-benchmark.sh /path/to/app"
echo ""

log_success "Docker optimization deployed successfully!"
echo ""
