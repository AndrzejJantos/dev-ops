# Redis Streams - DevOps Integration Guide

## Overview

Redis Streams is now fully integrated into the DevOps infrastructure. Configuration is automatic for new installations and available as a one-command upgrade for existing installations.

---

## For New Server Setup

Redis Streams configuration is **automatic** when you run the standard server initialization:

```bash
# On a fresh Ubuntu 22.04+ server
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/DevOps/master/ubuntu-init-setup.sh | bash
```

**What happens automatically:**
1. ✅ Redis installed with Streams configuration
2. ✅ AOF persistence enabled
3. ✅ Memory limits configured (2GB)
4. ✅ Stream optimization settings applied

Then deploy the API as usual:

```bash
cd ~/DevOps/apps/cheaperfordrug-api
./setup.sh    # Creates app with Redis Streams env vars
./deploy.sh deploy
```

**Done!** Redis Streams is configured and running.

---

## For Existing Server Upgrade

If you already have a server running, use this **one-command upgrade**:

```bash
cd ~/DevOps/apps/cheaperfordrug-api
./setup-redis-streams.sh
```

**What it does:**
1. ✅ Configures Redis for Streams (backs up existing config)
2. ✅ Enables Redis Streams in API environment
3. ✅ Verifies configuration
4. ✅ Provides deployment instructions

Then redeploy:

```bash
./deploy.sh deploy
```

**Time:** ~2-3 minutes total

---

## Configuration Files

### DevOps Configuration

**API App Config** (`DevOps/apps/cheaperfordrug-api/config.sh`):
```bash
# Redis Streams Configuration
export ENABLE_REDIS_STREAM_CONSUMERS="true"
export REDIS_STREAM_CONSUMER_COUNT="3"
```

**Rails App Type** (`DevOps/common/app-types/rails.sh`):
```bash
# Auto-generated in .env.production
ENABLE_REDIS_STREAM_CONSUMERS=false  # Set to true for API
REDIS_STREAM_CONSUMER_COUNT=3
REDIS_STREAM_BATCH_SIZE=10
REDIS_STREAM_BLOCK_MS=5000
REDIS_STREAMS_URL=redis://localhost:6379/3
```

---

## Architecture

### Directory Structure

```
DevOps/
├── ubuntu-init-setup.sh              # Server init (includes Redis Streams config)
├── common/
│   ├── redis-setup.sh                # Redis configuration functions
│   └── app-types/
│       └── rails.sh                  # Rails apps get Redis Streams env vars
└── apps/
    └── cheaperfordrug-api/
        ├── config.sh                 # Redis Streams enabled here
        └── setup-redis-streams.sh    # Upgrade script for existing installations
```

### Data Flow

```
1. Server Init (ubuntu-init-setup.sh)
   └─> Install Redis
   └─> Configure for Streams (persistence, memory, optimization)

2. App Setup (setup.sh)
   └─> Create .env.production with Redis Streams config
   └─> Use config from config.sh (ENABLE_REDIS_STREAM_CONSUMERS=true)

3. Deployment (deploy.sh)
   └─> Build Docker containers
   └─> Start scheduler container (runs Clockwork)
   └─> Clockwork starts consumer workers
   └─> Workers process messages from Redis Streams
```

---

## Verification Commands

### Check Redis Configuration

```bash
# Check Redis is configured for Streams
grep "Redis Streams Configuration" /etc/redis/redis.conf

# Check persistence enabled
redis-cli CONFIG GET appendonly

# Check memory limit
redis-cli CONFIG GET maxmemory

# Check Redis version (needs 5.0+)
redis-cli INFO server | grep redis_version
```

### Check API Configuration

```bash
# Check environment variables
grep REDIS_STREAM ~/apps/cheaperfordrug-api/.env.production

# Should show:
# ENABLE_REDIS_STREAM_CONSUMERS=true
# REDIS_STREAM_CONSUMER_COUNT=3
# REDIS_STREAMS_URL=redis://localhost:6379/3
```

### Check Deployment

```bash
# Check scheduler container running
docker ps | grep scheduler

# Check consumers are active
redis-cli -n 3 XINFO GROUPS cheaperfordrug:products:batch

# Check health endpoint
curl http://localhost:3000/admin/redis_streams/health
```

---

## Troubleshooting

### Problem: Redis Streams env vars not in .env.production

**Solution:**
```bash
# Redeploy to regenerate environment file
cd ~/DevOps/apps/cheaperfordrug-api
./deploy.sh deploy
```

Or manually add:
```bash
cat >> ~/apps/cheaperfordrug-api/.env.production << 'EOF'

# Redis Streams Configuration
ENABLE_REDIS_STREAM_CONSUMERS=true
REDIS_STREAM_CONSUMER_COUNT=3
REDIS_STREAMS_URL=redis://localhost:6379/3
EOF
```

### Problem: Scheduler container not starting

**Check config:**
```bash
cd ~/DevOps/apps/cheaperfordrug-api
grep SCHEDULER_ENABLED config.sh

# Should show:
# export SCHEDULER_ENABLED=true
```

**View logs:**
```bash
docker logs cheaperfordrug-api_scheduler_1 --tail 50
```

### Problem: Redis not configured for Streams

**Run configuration script:**
```bash
cd ~/DevOps/apps/cheaperfordrug-api
./setup-redis-streams.sh
```

Or configure manually:
```bash
# Use common utility
source ~/DevOps/common/redis-setup.sh
setup_redis_for_streams
```

---

## Files Modified/Created

### Created Files

1. **`DevOps/common/redis-setup.sh`**
   - Redis configuration functions
   - Can be sourced from any script
   - Handles Redis Streams setup

2. **`DevOps/apps/cheaperfordrug-api/setup-redis-streams.sh`**
   - One-command upgrade script
   - For existing installations
   - Integrated with DevOps workflow

3. **`DevOps/REDIS_STREAMS_DEVOPS_GUIDE.md`** (this file)
   - DevOps integration documentation

### Modified Files

1. **`DevOps/ubuntu-init-setup.sh`**
   - Added Redis Streams configuration to install_databases()
   - Automatic for new servers

2. **`DevOps/common/app-types/rails.sh`**
   - Added Redis Streams env vars to rails_create_env_file()
   - Automatic for all Rails apps

3. **`DevOps/apps/cheaperfordrug-api/config.sh`**
   - Added ENABLE_REDIS_STREAM_CONSUMERS=true
   - Added REDIS_STREAM_CONSUMER_COUNT=3

---

## Integration with Existing Workflow

### New Server

```bash
# 1. Initialize server (includes Redis Streams)
./ubuntu-init-setup.sh

# 2. Setup API (includes Redis Streams env vars)
cd ~/DevOps/apps/cheaperfordrug-api
./setup.sh

# 3. Deploy (starts scheduler and consumers)
./deploy.sh deploy

# Done! Redis Streams is working
```

### Existing Server

```bash
# 1. One-command upgrade
cd ~/DevOps/apps/cheaperfordrug-api
./setup-redis-streams.sh

# 2. Redeploy
./deploy.sh deploy

# Done! Redis Streams is working
```

---

## Environment-Specific Settings

### Development

```bash
# In config.sh for dev environments
export ENABLE_REDIS_STREAM_CONSUMERS="false"  # Use HTTP for testing
export REDIS_STREAM_CONSUMER_COUNT="1"        # Minimal for dev
```

### Staging

```bash
export ENABLE_REDIS_STREAM_CONSUMERS="true"
export REDIS_STREAM_CONSUMER_COUNT="2"
```

### Production

```bash
export ENABLE_REDIS_STREAM_CONSUMERS="true"
export REDIS_STREAM_CONSUMER_COUNT="3"  # Or more based on load
```

---

## Monitoring Integration

Add to your monitoring scripts:

```bash
# Check Redis Streams health
redis-cli -n 3 XLEN cheaperfordrug:products:batch

# Alert if queue depth > 1000
QUEUE_DEPTH=$(redis-cli -n 3 XLEN cheaperfordrug:products:batch)
if [ "$QUEUE_DEPTH" -gt 1000 ]; then
    # Send alert
    echo "Redis Streams queue depth high: $QUEUE_DEPTH"
fi

# Check consumer count
CONSUMER_COUNT=$(redis-cli -n 3 XINFO GROUPS cheaperfordrug:products:batch | grep -A1 consumers | tail -1)
if [ "$CONSUMER_COUNT" -lt 3 ]; then
    # Send alert
    echo "Redis Streams consumers below threshold: $CONSUMER_COUNT"
fi
```

---

## Backup Considerations

### Redis Data

```bash
# AOF backup (automatic with persistence enabled)
ls -lh /var/lib/redis/appendonly.aof

# Manual backup
cp /var/lib/redis/appendonly.aof /backup/redis/appendonly.aof.$(date +%Y%m%d)
```

### Configuration

```bash
# Automatically backed up during setup
ls -l /etc/redis/redis.conf.backup-*
```

---

## Rollback

If you need to disable Redis Streams:

```bash
# 1. Disable in environment
nano ~/apps/cheaperfordrug-api/.env.production
# Change: ENABLE_REDIS_STREAM_CONSUMERS=false

# 2. Restart API
cd ~/DevOps/apps/cheaperfordrug-api
./deploy.sh restart

# Scrapers will automatically fall back to HTTP
```

---

## Next Steps

1. **Monitor performance**
   - Track queue depth
   - Monitor consumer health
   - Check processing latency

2. **Scale if needed**
   ```bash
   # Increase consumers
   nano ~/DevOps/apps/cheaperfordrug-api/config.sh
   # Change: REDIS_STREAM_CONSUMER_COUNT="5"

   # Redeploy
   ./deploy.sh deploy
   ```

3. **Add to disaster recovery**
   - Include Redis data in backups
   - Document Redis Streams in runbooks
   - Test failover scenarios

---

## Summary

Redis Streams is now a **first-class citizen** in your DevOps infrastructure:

- ✅ **Automatic** for new servers
- ✅ **One-command** upgrade for existing servers
- ✅ **Integrated** with deployment workflow
- ✅ **Configured** by default for API
- ✅ **Monitored** via standard tools
- ✅ **Documented** in DevOps guides

**No manual configuration needed** - everything is automated! 🚀
