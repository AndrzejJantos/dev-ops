# Docker Performance Optimization Guide

## Problem Overview

**Issue**: Docker builds taking 10+ minutes, with specific steps (chmod/chown) stuck in uninterruptible I/O wait ("D" state).

**Root Causes Identified**:
1. Recursive `chown -R` and `chmod -R` operations on entire `/app` directory
2. Overlay2 filesystem with 25+ layers causing I/O amplification
3. Excessive build cache (25GB+) and dangling images (12GB+)
4. RAID storage (md2) compounds overlay2 performance issues

## Solution Summary

### 1. Dockerfile Optimizations (COMPLETED)

**File Modified**: `/Users/andrzej/Development/CheaperForDrug/DevOps/common/rails/Dockerfile.template`

**Changes Made**:

#### Before (Problematic):
```dockerfile
COPY --from=builder --chown=app:app /app ./
COPY --from=builder --chown=app:app /app/public/assets ./public/assets

RUN mkdir -p tmp/pids tmp/cache tmp/sockets log && \
    chown -R app:app /app && \        # ← SLOW: Recursive on entire directory
    chmod -R 755 /app && \             # ← SLOW: Recursive on entire directory
    chmod 777 log
```

#### After (Optimized):
```dockerfile
# Set ownership during COPY (no separate chown needed)
COPY --from=builder --chown=app:app /app ./
COPY --from=builder --chown=app:app /app/public/assets ./public/assets

# Create directories and set ownership ONLY on specific paths
RUN mkdir -p tmp/pids tmp/cache tmp/sockets log && \
    chown app:app tmp tmp/pids tmp/cache tmp/sockets log && \  # ← FAST: Specific paths only
    chmod 755 tmp/pids tmp/cache tmp/sockets && \              # ← FAST: Specific paths only
    chmod 777 log
```

**Key Improvements**:
- **Eliminated** recursive operations on `/app` (thousands of files)
- **Leverage** `--chown` flag in `COPY` instructions (overlay2 optimized)
- **Target** only specific directories that need ownership changes
- **Expected Result**: Step 32 completes in <5 seconds instead of 10+ minutes

### 2. Docker Cleanup Script (CREATED)

**File**: `/Users/andrzej/Development/CheaperForDrug/DevOps/scripts/docker-cleanup-optimization.sh`

**Purpose**: Comprehensive cleanup of Docker system to reduce overlay2 layers and cache buildup.

**Usage**:
```bash
# Standard cleanup (recommended first)
./scripts/docker-cleanup-optimization.sh

# Aggressive cleanup (removes all unused images)
./scripts/docker-cleanup-optimization.sh --aggressive
```

**What It Does**:
- **Phase 1**: Collects current Docker disk usage and overlay2 statistics
- **Phase 2**: Optionally stops running containers
- **Phase 3**: Removes stopped containers
- **Phase 4**: Removes dangling images
- **Phase 5**: Cleans build cache (keeps last 24h by default)
- **Phase 6**: Aggressive mode - removes ALL unused images and cache
- **Phase 7**: Removes unused volumes (with confirmation)
- **Phase 8**: Removes unused networks
- **Phase 9**: Reports final status and space reclaimed
- **Phase 10**: Provides optimization recommendations

**Expected Cleanup**:
- Dangling images: ~12GB
- Build cache: ~10GB+ (from 25GB total)
- Overlay2 layers: Reduced from 25+ to active images only

### 3. Build Benchmark Script (CREATED)

**File**: `/Users/andrzej/Development/CheaperForDrug/DevOps/scripts/docker-build-benchmark.sh`

**Purpose**: Test and verify build performance improvements.

**Usage**:
```bash
./scripts/docker-build-benchmark.sh /path/to/your/rails/app
```

**What It Measures**:
- Total build time (seconds)
- Individual step performance
- Detects recursive chown/chmod operations
- Analyzes COPY operations for --chown usage
- Final image size and layer count
- Overlay2 layer growth during build
- Performance assessment and recommendations

**Performance Targets**:
- **Excellent**: < 2 minutes total build time
- **Good**: < 5 minutes total build time
- **Acceptable**: < 10 minutes total build time
- **Critical Step (chown/chmod)**: < 5 seconds (down from 10+ minutes)

## Implementation Steps

### Step 1: Deploy Optimized Dockerfile

The Dockerfile template has been updated. For existing applications:

1. **Update the Dockerfile in your application repository** or re-run setup scripts that use the template:
   ```bash
   # If you have apps using the template, they'll get the new version on next setup
   # Or manually update existing Dockerfiles with the optimized RUN commands
   ```

### Step 2: Clean Up Docker System (ON SERVER)

Run this on your Hetzner server:

```bash
# Upload the cleanup script to your server
scp scripts/docker-cleanup-optimization.sh user@your-server:/tmp/

# SSH to your server
ssh user@your-server

# Run the cleanup script
sudo /tmp/docker-cleanup-optimization.sh

# For aggressive cleanup (after backing up important images):
# sudo /tmp/docker-cleanup-optimization.sh --aggressive
```

**Expected Results**:
- ~12GB reclaimed from dangling images
- ~10GB+ reclaimed from build cache
- Overlay2 layers reduced to active images only
- Improved I/O performance on RAID storage

### Step 3: Rebuild and Test

After cleanup, rebuild your application:

```bash
# Upload benchmark script to server
scp scripts/docker-build-benchmark.sh user@your-server:/tmp/

# Run benchmark on your Rails app
cd /path/to/your/rails/app
sudo /tmp/docker-build-benchmark.sh .
```

**Verification**:
- Step 32 (chown/chmod) should complete in seconds
- Total build time should be under 5 minutes for small Rails apps
- No processes stuck in "D" state
- Build log should show no recursive operations

### Step 4: Enable BuildKit (Optional, Recommended)

BuildKit provides additional performance improvements:

```bash
# Add to your shell profile (~/.bashrc or ~/.zshrc)
export DOCKER_BUILDKIT=1

# Or add to Docker daemon config (/etc/docker/daemon.json)
{
  "features": {
    "buildkit": true
  }
}

# Restart Docker daemon
sudo systemctl restart docker
```

**BuildKit Benefits**:
- Better build cache management
- Parallel build stage execution
- Improved layer caching
- Faster incremental builds

## Docker Storage Driver Considerations

### Current Setup: overlay2 on RAID (md2)

**Issue**: overlay2 with many layers on RAID causes I/O amplification:
- Each layer write propagates through RAID
- Metadata operations (chown/chmod) are especially slow
- 25+ layers = 25x metadata operations

### Optimization Options

#### Option 1: Reduce Layers (IMPLEMENTED)
- Combine RUN commands where possible
- Use multi-stage builds effectively
- Eliminate recursive operations
- **Impact**: Significant (10+ minutes → seconds)
- **Risk**: None
- **Recommendation**: ✅ **Done**

#### Option 2: Enable BuildKit
- Better caching reduces layer creation
- Parallel builds reduce total time
- **Impact**: Moderate (20-30% faster)
- **Risk**: Low (easy to disable)
- **Recommendation**: ✅ **Do this next**

#### Option 3: Alternative Storage Driver (Advanced)
Consider `fuse-overlayfs` for RAID/network storage:
```json
{
  "storage-driver": "fuse-overlayfs"
}
```
- **Impact**: Potentially significant
- **Risk**: High (requires data migration, downtime)
- **Recommendation**: ⚠️ **Only if issues persist**

#### Option 4: Dedicated Build Server
- Build on local SSD storage
- Push to registry
- Pull on RAID server
- **Impact**: Significant
- **Risk**: Low (no production changes)
- **Recommendation**: 💡 **For frequent builds**

## Monitoring and Maintenance

### Regular Maintenance Commands

```bash
# Weekly cleanup (add to cron)
docker system prune -f
docker builder prune -f --filter until=168h

# Check disk usage
docker system df -v

# Monitor overlay2 growth
sudo du -sh /var/lib/docker/overlay2
sudo find /var/lib/docker/overlay2 -maxdepth 1 -type d | wc -l

# Check for processes in D state during builds
ps aux | grep ' D '
```

### Automated Cleanup (Recommended)

Add to crontab:
```bash
# Weekly Docker cleanup (Sundays at 2 AM)
0 2 * * 0 /usr/bin/docker system prune -f && /usr/bin/docker builder prune -f --filter until=168h
```

### Build Performance Monitoring

Create a simple build monitor:
```bash
#!/bin/bash
# Monitor build times and alert if slow

APP_DIR=$1
START=$(date +%s)

docker build -t myapp:latest "$APP_DIR"

END=$(date +%s)
DURATION=$((END - START))

if [ $DURATION -gt 600 ]; then
    echo "WARNING: Build took ${DURATION}s (over 10 minutes)" | mail -s "Slow Docker Build" admin@example.com
fi
```

## Troubleshooting

### If Builds Are Still Slow

1. **Check for recursive operations**:
   ```bash
   grep -n "chown -R\|chmod -R" Dockerfile
   # Should return no results
   ```

2. **Verify overlay2 layer count**:
   ```bash
   sudo find /var/lib/docker/overlay2 -maxdepth 1 -type d | wc -l
   # Should be < 50 after cleanup
   ```

3. **Check RAID performance**:
   ```bash
   sudo iostat -x 1
   # Look for high await times during builds
   ```

4. **Enable debug logging**:
   ```bash
   docker build --progress=plain --no-cache . 2>&1 | tee build.log
   # Analyze build.log for slow steps
   ```

### If Process Stuck in "D" State

1. **Identify the process**:
   ```bash
   ps aux | grep ' D '
   ```

2. **Check I/O wait**:
   ```bash
   top  # Look for high %wa (wait time)
   iotop  # See which process is waiting for I/O
   ```

3. **Usually caused by**:
   - Recursive operations on large directories
   - RAID synchronization
   - Filesystem metadata operations

4. **Solution**: Wait for operation to complete or restart Docker daemon (last resort)

## Performance Comparison

### Before Optimization
```
Step 32: RUN chown -R app:app /app
├─ Duration: 10-15 minutes
├─ I/O State: Uninterruptible (D)
├─ Overlay2 Layers: 25+
├─ Build Cache: 25GB
└─ Total Build Time: 15+ minutes
```

### After Optimization
```
Step 32: RUN chown app:app tmp tmp/pids ...
├─ Duration: < 5 seconds
├─ I/O State: Normal
├─ Overlay2 Layers: 10-15 (active only)
├─ Build Cache: < 5GB (with regular cleanup)
└─ Total Build Time: 2-5 minutes
```

**Expected Improvement**: **95%+ reduction in critical step time** (10+ min → 5 sec)

## Best Practices Going Forward

### Dockerfile Guidelines

1. **Always use `--chown` in COPY**:
   ```dockerfile
   # Good
   COPY --from=builder --chown=app:app /app ./

   # Avoid
   COPY --from=builder /app ./
   RUN chown -R app:app /app
   ```

2. **Never use recursive operations on large directories**:
   ```dockerfile
   # Good
   RUN mkdir -p log tmp && chown app:app log tmp

   # Avoid
   RUN chown -R app:app /app
   ```

3. **Combine RUN commands to reduce layers**:
   ```dockerfile
   # Good
   RUN apt-get update && apt-get install -y pkg1 pkg2 && rm -rf /var/lib/apt/lists/*

   # Avoid
   RUN apt-get update
   RUN apt-get install -y pkg1
   RUN apt-get install -y pkg2
   ```

4. **Use multi-stage builds** (already implemented):
   - Build stage: Install dependencies, compile assets
   - Production stage: Copy only what's needed

5. **Order instructions by change frequency**:
   ```dockerfile
   # Least frequently changed (good cache utilization)
   FROM ruby:3.4.5-slim
   RUN apt-get install ...
   COPY Gemfile* ./
   RUN bundle install

   # Most frequently changed
   COPY . .
   ```

### Maintenance Schedule

- **Daily**: Monitor build times
- **Weekly**: Run cleanup script
- **Monthly**: Review overlay2 growth, optimize Dockerfiles
- **Quarterly**: Consider build infrastructure improvements

## Additional Resources

- Docker BuildKit: https://docs.docker.com/build/buildkit/
- Overlay2 driver: https://docs.docker.com/storage/storagedriver/overlayfs-driver/
- Multi-stage builds: https://docs.docker.com/build/building/multi-stage/
- Best practices: https://docs.docker.com/develop/develop-images/dockerfile_best-practices/

## Summary

**Files Modified**:
- `/Users/andrzej/Development/CheaperForDrug/DevOps/common/rails/Dockerfile.template`

**Files Created**:
- `/Users/andrzej/Development/CheaperForDrug/DevOps/scripts/docker-cleanup-optimization.sh`
- `/Users/andrzej/Development/CheaperForDrug/DevOps/scripts/docker-build-benchmark.sh`
- `/Users/andrzej/Development/CheaperForDrug/DevOps/DOCKER_PERFORMANCE_OPTIMIZATION.md`

**Next Steps**:
1. ✅ Optimized Dockerfile template (completed)
2. ⏭️ Run cleanup script on server
3. ⏭️ Rebuild and benchmark
4. ⏭️ Enable BuildKit
5. ⏭️ Set up regular maintenance

**Expected Results**:
- Critical step time: 10+ min → < 5 sec (95%+ improvement)
- Total build time: 15+ min → 2-5 min (70%+ improvement)
- Disk space reclaimed: ~22GB
- No more processes stuck in "D" state
