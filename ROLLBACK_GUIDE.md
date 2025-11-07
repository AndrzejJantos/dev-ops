# Rollback Guide

Quick reference guide for rolling back deployments in the CheaperForDrug infrastructure.

## Quick Start

```bash
# Interactive rollback (recommended)
cd ~/DevOps/apps/APP_NAME
./deploy.sh rollback

# Follow the prompts to select a version
```

## What Gets Rolled Back

When you rollback, the system:
- ✅ Reverts application code to the selected version
- ✅ Uses the Docker image from that deployment
- ✅ Performs health checks before switching traffic
- ✅ Maintains zero-downtime during rollback
- ✅ Logs the rollback operation
- ❌ Does NOT rollback database migrations (see Database section)
- ❌ Does NOT rollback environment variables

## Available Applications

All applications support rollback:

```bash
# API
cd ~/DevOps/apps/cheaperfordrug-api
./deploy.sh rollback

# Web Frontend
cd ~/DevOps/apps/cheaperfordrug-web
./deploy.sh rollback

# Landing Page
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh rollback
```

## Rollback Process

### Step 1: View Available Versions

```bash
./deploy.sh rollback
```

**Output:**
```
[INFO] Currently deployed version: 20241106_143025

[INFO] Available Docker images:

#    VERSION (TAG)         CREATED               SIZE
--------------------------------------------------------------
1    20241106_143025       2024-11-06 14:30:25   1.2GB
2    20241106_120530       2024-11-06 12:05:30   1.2GB
3    20241105_183045       2024-11-05 18:30:45   1.1GB
4    20241105_091520       2024-11-05 09:15:20   1.1GB

Enter the version number to rollback to (or 'cancel' to abort):
>
```

### Step 2: Select Version

Enter the number corresponding to the version you want:

```
> 2
```

### Step 3: Confirm Rollback

```
[INFO] Current version: 20241106_143025
[INFO] Target version:  20241106_120530

Continue with rollback? (yes/no): yes
```

### Step 4: Monitor Progress

The system will:
1. Tag selected version as `:latest`
2. Start new containers with old version
3. Verify health checks pass
4. Stop old containers
5. Complete rollback

### Step 5: Verify

```bash
# Check status
./deploy.sh status

# Test the application
curl https://your-domain.com

# View logs
./deploy.sh logs
```

## Version Retention

### Current Configuration

By default, the system keeps the **last 3 versions** of each application.

**Check current settings:**

```bash
cat ~/DevOps/apps/APP_NAME/config.sh | grep -E "(AUTO_CLEANUP|MAX_IMAGE_VERSIONS)"
```

### Increase Version Retention

To keep more versions for rollback:

```bash
# Edit config.sh
nano ~/DevOps/apps/APP_NAME/config.sh

# Change these values:
AUTO_CLEANUP_ENABLED=true
MAX_IMAGE_VERSIONS=10  # Keep last 10 versions
```

### Disable Cleanup (Keep All Versions)

```bash
# Edit config.sh
AUTO_CLEANUP_ENABLED=false
```

**Warning:** This will consume more disk space over time.

### View Disk Usage

```bash
# Check Docker image sizes
docker images | grep "cheaperfordrug"

# Total Docker disk usage
docker system df
```

## Database Considerations

### Rollback Without Migrations

If your deployment **did not include database migrations**, rollback is safe and straightforward:

```bash
./deploy.sh rollback
# Select version and confirm
```

### Rollback WITH Migrations (⚠️ Complex)

If your deployment **included database migrations**, rolling back code alone may cause issues:

**Problem:** New code expects new database schema, old code expects old schema.

**Solution Options:**

#### Option 1: Rollback Migrations First (Recommended)

```bash
# 1. Connect to Rails console
cd ~/DevOps/apps/cheaperfordrug-api
./deploy.sh console

# 2. Rollback specific migrations
ActiveRecord::Migration.rollback(step: 1)  # Rollback 1 migration
# Or rollback to specific version:
ActiveRecord::MigrationContext.new('db/migrate').down(20241106120530)

# 3. Exit console and rollback code
exit

# 4. Rollback application code
./deploy.sh rollback
```

#### Option 2: Forward-Compatible Migrations

**Best Practice:** Always write migrations that are compatible with both old and new code versions.

**Example:**
```ruby
# Good: Add column with default value
class AddStatusToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :status, :string, default: 'active'
  end
end

# Old code: Works (column has default)
# New code: Works (column exists)
```

#### Option 3: Database Backup + Restore

If migrations can't be rolled back:

```bash
# 1. Restore database from backup
# (See Database Backup Guide)

# 2. Rollback application code
./deploy.sh rollback
```

### Migration Safety Checklist

Before deploying migrations:

- [ ] Migration is backward compatible with current code
- [ ] Database backup created (automatic in production)
- [ ] Migration tested in staging environment
- [ ] Migration can be rolled back if needed
- [ ] Rollback procedure documented

## Emergency Rollback

If the system is down and you need to rollback immediately:

### Quick Emergency Rollback

```bash
# 1. SSH to server
ssh user@server

# 2. Navigate to app directory
cd ~/DevOps/apps/APP_NAME

# 3. Run rollback (select most recent stable version)
./deploy.sh rollback
```

### If Rollback Command Fails

Manually rollback to last known good version:

```bash
# 1. Find the last good version
docker images | grep APP_NAME

# 2. Tag it as latest
docker tag APP_NAME:TIMESTAMP APP_NAME:latest

# 3. Restart containers
./deploy.sh restart

# 4. Verify health
./deploy.sh status
```

## Troubleshooting

### "No previous versions found"

**Problem:** All old images were cleaned up.

**Solution:**
```bash
# Check if any images exist
docker images | grep APP_NAME

# If none exist, you must redeploy from git
git log --oneline  # Find commit hash
git checkout COMMIT_HASH
./deploy.sh deploy
```

**Prevention:** Increase `MAX_IMAGE_VERSIONS` in config.sh

### Rollback Fails Health Checks

**Problem:** Rolled back version fails health checks.

**Possible Causes:**
- Database schema incompatibility
- Missing environment variables
- Configuration changes

**Solution:**
```bash
# 1. Check logs
./deploy.sh logs

# 2. Check environment variables
docker exec APP_NAME_web_1 env | grep -E "(DATABASE|REDIS|API)"

# 3. Rollback to an even older version
./deploy.sh rollback  # Try version 3 or 4

# 4. If all versions fail, check database and external dependencies
```

### Container Won't Start After Rollback

**Problem:** Containers immediately crash or exit.

**Solution:**
```bash
# 1. View container logs
docker logs APP_NAME_web_1

# 2. Common issues:
# - Database connection failed
# - Missing environment variable
# - Port already in use

# 3. Verify database is running (for Rails apps)
sudo systemctl status postgresql

# 4. Check port conflicts
netstat -tulpn | grep PORT_NUMBER
```

## Best Practices

### 1. Regular Version Retention Check

```bash
# Weekly: Check available versions
cd ~/DevOps/apps/cheaperfordrug-api
docker images | grep cheaperfordrug-api | wc -l

# Should show at least 3-5 versions
```

### 2. Test Rollback in Staging

Before production deployment:

```bash
# In staging environment
1. Deploy new version
2. Test rollback to previous version
3. Verify rollback works correctly
4. Deploy to production with confidence
```

### 3. Document Each Deployment

Keep a log of what changed:

```bash
# Add to deployments.log
echo "[$(date)] Deployed v1.2.3 - Added user notifications feature" >> ~/apps/APP_NAME/logs/deployments.log
```

### 4. Monitor After Rollback

After rollback, monitor for:
- Response times
- Error rates
- Health check status
- Log messages

```bash
# Watch logs in real-time
./deploy.sh logs

# Check error rate
curl https://your-domain.com/api/health
```

### 5. Preserve Critical Versions

Tag important stable versions:

```bash
# Tag a known stable version
docker tag cheaperfordrug-api:20241106_120530 cheaperfordrug-api:stable-1.2.3

# This prevents cleanup from removing it
```

## Rollback Checklist

Use this checklist when performing rollbacks:

- [ ] Identify the issue requiring rollback
- [ ] Determine last known good version
- [ ] Check if deployment included database migrations
- [ ] Create database backup (if needed)
- [ ] Run `./deploy.sh rollback`
- [ ] Select appropriate version
- [ ] Confirm rollback
- [ ] Monitor health checks
- [ ] Verify application functionality
- [ ] Check logs for errors
- [ ] Test critical user flows
- [ ] Document the rollback
- [ ] Investigate root cause
- [ ] Plan fix for next deployment

## Rollback Metrics

Track these metrics to improve deployment process:

```bash
# View deployment and rollback history
cat ~/apps/APP_NAME/logs/deployments.log

# Count rollbacks in last month
grep "Rolled back" ~/apps/APP_NAME/logs/deployments.log | grep "$(date +%Y-%m)" | wc -l

# Most common rollback reasons (add manually to log)
grep "Rolled back" ~/apps/APP_NAME/logs/deployments.log | cut -d'-' -f3 | sort | uniq -c | sort -rn
```

## Related Documentation

- [Zero-Downtime Deployment](./ZERO_DOWNTIME_DEPLOYMENT.md) - Full deployment strategy
- [Database Migrations](./DATABASE_MIGRATIONS.md) - Migration best practices (if exists)
- [Monitoring Guide](./MONITORING.md) - Post-rollback monitoring (if exists)

## Support

If you need help with rollback:

1. Check deployment logs: `~/apps/APP_NAME/logs/deployments.log`
2. Review Docker logs: `./deploy.sh logs`
3. Check this guide's Troubleshooting section
4. Contact DevOps team

## Quick Reference Commands

```bash
# Rollback
./deploy.sh rollback

# Check current version
docker ps | grep APP_NAME

# List available versions
docker images | grep APP_NAME

# View deployment history
cat ~/apps/APP_NAME/logs/deployments.log | tail -20

# Check container health
./deploy.sh status

# View logs
./deploy.sh logs

# Manual rollback
docker tag APP_NAME:TIMESTAMP APP_NAME:latest
./deploy.sh restart
```
