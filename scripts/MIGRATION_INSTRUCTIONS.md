# Quick Migration Guide: Scaleway to Local Storage

## For brokik-api Migration

### Step 1: SSH to Server
```bash
ssh hetzner-andrzej
```

### Step 2: Run Migration Script
```bash
cd ~/DevOps
./scripts/migrate-scaleway-to-local-storage.sh
```

### Step 3: Follow Prompts
The script will:
- ✅ Check prerequisites
- ✅ Create `/var/storage/brokik-api/active_storage/`
- ✅ Download all 59 files from Scaleway
- ✅ Update `.env.production`
- ✅ Ask to restart application

### Step 4: Verify
```bash
# Check files were migrated
find /var/storage/brokik-api/active_storage -type f | wc -l
# Should show 59

# Check logs
docker logs brokik-api_web_1 -f

# Test uploading/downloading files in application
```

### Step 5: Monitor
Monitor for 24-48 hours to ensure everything works correctly.

## Rollback (if needed)
```bash
# Restore backup
cp ~/apps/brokik-api/.env.production.backup.scaleway.* ~/apps/brokik-api/.env.production

# Restart
cd ~/DevOps/apps/brokik-api && ./deploy.sh restart
```

## For New Apps

Just set in `.env.production`:
```bash
RAILS_ACTIVE_STORAGE_SERVICE=host_disk
ACTIVE_STORAGE_HOST_PATH=/var/storage/{app-name}/active_storage
```

Deployment scripts handle the rest automatically!

## Full Documentation

See: `DevOps/docs/active-storage-local-migration.md`
