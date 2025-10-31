# Active Storage Migration: Scaleway to Local Host Storage

This document describes the migration from Scaleway S3 storage to local host storage for Rails Active Storage, and how to configure new apps to use local storage.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [For Existing Apps: Migration from Scaleway](#migration-from-scaleway)
4. [For New Apps: Local Storage Setup](#local-storage-setup)
5. [How It Works](#how-it-works)
6. [Troubleshooting](#troubleshooting)
7. [Rollback Procedures](#rollback-procedures)

## Overview

### What Changed

- **Before**: Active Storage files stored in Scaleway S3 bucket
- **After**: Active Storage files stored on host machine at `/var/storage/{app-name}/active_storage`

### Benefits of Local Storage

- **No external dependencies**: Files stored directly on server
- **No additional costs**: No S3 storage fees
- **Faster access**: Direct disk I/O instead of network requests
- **Simpler architecture**: One less service to manage
- **Persists across deployments**: Files survive container restarts

### Storage Structure

```
/var/storage/
├── brokik-api/
│   └── active_storage/
│       ├── XX/
│       │   └── YY/
│       │       └── {hash}  # Actual file
│       └── variants/       # Image variants (thumbnails, etc.)
└── {other-app}/
    └── active_storage/
        └── ...
```

## Architecture

### Directory Structure

```
Host Machine:
/var/storage/{app-name}/active_storage/  ← Actual files stored here
                                          ↓ Mounted as volume
Docker Container:
/var/storage/{app-name}/active_storage/  ← Same path accessible in container
```

### Configuration Files

1. **config/storage.yml** - Defines storage services
2. **.env.production** - Configures which service to use
3. **DevOps scripts** - Automatically mount volumes during deployment

## Migration from Scaleway

### Prerequisites

- SSH access to server (`hetzner-andrzej`)
- Application running with Scaleway configuration
- Enough disk space for all files

### Migration Steps

#### Step 1: Prepare the Migration

```bash
# SSH to server
ssh hetzner-andrzej

# Navigate to DevOps directory
cd ~/DevOps
```

#### Step 2: Run Migration Script

```bash
# Run the migration script
./scripts/migrate-scaleway-to-local-storage.sh
```

The script will:
1. ✅ Check prerequisites (app running, env file exists)
2. ✅ Create local storage directory structure
3. ✅ Download all files from Scaleway to local disk
4. ✅ Update `.env.production` to use `host_disk` service
5. ✅ Backup original configuration
6. ✅ Verify file counts match
7. ✅ Offer to restart application

#### Step 3: Verify Migration

After restart, test the application:

```bash
# Check container logs
docker logs brokik-api_web_1 -f

# Verify files are accessible
ls -lR /var/storage/brokik-api/active_storage/ | head -20

# Check file count
find /var/storage/brokik-api/active_storage -type f | wc -l
```

Test in application:
- Upload a new file
- View existing files
- Download files

#### Step 4: Monitor for Issues

Monitor for 24-48 hours:
- Check logs for any storage-related errors
- Test all file upload/download features
- Verify image variants are generated correctly

#### Step 5: Cleanup (Optional)

After confirming everything works:

```bash
# Remove Scaleway credentials from env file
cd ~/apps/brokik-api
nano .env.production
# Delete commented-out SCALEWAY_* lines

# You can now delete files from Scaleway bucket if desired
# (Keep for a few days as backup)
```

## Local Storage Setup

### For New Rails Apps

When setting up a new Rails app, local storage is now the default.

#### 1. Application Configuration

Your `config/storage.yml` should include:

```yaml
host_disk:
  service: Disk
  root: <%= ENV.fetch("ACTIVE_STORAGE_HOST_PATH", "/var/storage/my-app/active_storage") %>
  public: true
```

#### 2. Environment Configuration

In `.env.production`:

```bash
# Active Storage Configuration
RAILS_ACTIVE_STORAGE_SERVICE=host_disk
ACTIVE_STORAGE_HOST_PATH=/var/storage/my-app/active_storage
FILES_STORAGE_URL=my-app.com
```

#### 3. Deployment

The deployment scripts automatically:
- Create the storage directory
- Set proper permissions (777 for container access)
- Mount it as a volume in all containers (web, worker, scheduler)

No manual intervention needed!

## How It Works

### Deployment Flow

1. **Pull Code** (`rails_pull_code`)
   - Loads `ACTIVE_STORAGE_HOST_PATH` from `.env.production`
   - Creates directory if it doesn't exist

2. **Start Container** (`start_container`)
   - Detects Rails app with `ACTIVE_STORAGE_HOST_PATH`
   - Adds volume mount: `-v /var/storage/app:/var/storage/app`
   - Container sees same files as host

3. **Active Storage Access**
   - Rails writes files to `ACTIVE_STORAGE_HOST_PATH`
   - Files persist on host, survive container restarts
   - All containers (web, worker, scheduler) share same volume

### Volume Mounting

The deployment scripts automatically mount volumes for:

```bash
# Web containers
docker run ... -v /var/storage/app:/var/storage/app ...

# Worker containers
docker run ... -v /var/storage/app:/var/storage/app ...

# Scheduler containers
docker run ... -v /var/storage/app:/var/storage/app ...
```

### File Permissions

- **Directory**: 777 (allows container user to write)
- **Files**: 644 (written by container user)
- **Owner**: Container user (usually `app` or `root`)

## Troubleshooting

### Files not accessible after migration

**Symptom**: 404 errors or "File not found"

**Solution**:
```bash
# Check if directory exists and has correct permissions
ls -la /var/storage/brokik-api/active_storage/
chmod 777 /var/storage/brokik-api/active_storage/

# Verify volume is mounted in container
docker inspect brokik-api_web_1 | grep -A 5 Mounts

# Restart containers
cd ~/DevOps/apps/brokik-api && ./deploy.sh restart
```

### Permission denied errors

**Symptom**: "Permission denied" in logs

**Solution**:
```bash
# Fix directory permissions
sudo chmod 777 /var/storage/brokik-api/active_storage/
sudo chmod -R 644 /var/storage/brokik-api/active_storage/*
sudo find /var/storage/brokik-api/active_storage/ -type d -exec chmod 755 {} \;
```

### Files uploaded but not visible

**Symptom**: Upload succeeds but file doesn't appear

**Solution**:
```bash
# Check if files are being written
ls -lth /var/storage/brokik-api/active_storage/ | head

# Verify Rails is using correct service
docker exec brokik-api_web_1 bundle exec rails runner "puts Rails.configuration.active_storage.service"
# Should output: host_disk

# Check environment variable
docker exec brokik-api_web_1 env | grep ACTIVE_STORAGE
```

### Disk space issues

**Symptom**: "No space left on device"

**Solution**:
```bash
# Check disk space
df -h /var/storage

# Find largest files
du -h /var/storage/brokik-api/active_storage/ | sort -rh | head -20

# Clean up old files if needed (be careful!)
# Consider implementing file cleanup policy
```

## Rollback Procedures

### Rollback to Scaleway

If you need to rollback to Scaleway storage:

#### Option 1: Using Backup File

```bash
# Restore env file from backup
cd ~/apps/brokik-api
cp .env.production.backup.scaleway.YYYYMMDD_HHMMSS .env.production

# Restart application
cd ~/DevOps/apps/brokik-api
./deploy.sh restart
```

#### Option 2: Manual Configuration

```bash
# Edit env file
cd ~/apps/brokik-api
nano .env.production

# Change these values:
RAILS_ACTIVE_STORAGE_SERVICE=scaleway

# Uncomment Scaleway credentials:
SCALEWAY_ENDPOINT=https://brokik-prod.s3.fr-par.scw.cloud
SCALEWAY_ACCESS_KEY_ID=SCWPJ4K2WNCJVAANCYZ1
SCALEWAY_SECRET_ACCESS_KEY=2696045c-6256-46b3-a61b-d040d9f38940
SCALEWAY_REGION=fr-par
SCALEWAY_BUCKET_NAME=i

# Restart
cd ~/DevOps/apps/brokik-api
./deploy.sh restart
```

### Migrate Back to Scaleway

To migrate files back to Scaleway (if needed):

```bash
# Create reverse migration script
docker exec brokik-api_web_1 bundle exec rails runner '
  # Switch to scaleway service temporarily
  old_service = Rails.configuration.active_storage.service

  ActiveStorage::Blob.find_each do |blob|
    # This will re-upload to current service (scaleway)
    # Only needed if blobs reference local files
    blob.upload(blob.download) unless blob.service_name == :scaleway
  end
'

# Update configuration
sed -i 's/^RAILS_ACTIVE_STORAGE_SERVICE=.*/RAILS_ACTIVE_STORAGE_SERVICE=scaleway/' ~/apps/brokik-api/.env.production

# Restart
cd ~/DevOps/apps/brokik-api && ./deploy.sh restart
```

## Best Practices

### Backup Strategy

1. **Regular Backups**: Include `/var/storage` in your backup strategy
2. **Test Restores**: Periodically test restoring files
3. **Monitor Disk Usage**: Set up alerts for disk space

### Monitoring

```bash
# Add to monitoring script
STORAGE_PATH="/var/storage/brokik-api/active_storage"
FILE_COUNT=$(find "$STORAGE_PATH" -type f | wc -l)
DISK_USAGE=$(du -sh "$STORAGE_PATH" | cut -f1)

echo "Active Storage: $FILE_COUNT files, $DISK_USAGE total"
```

### Security

1. **Permissions**: Keep 777 on directory, 644 on files
2. **Access**: Only containers should write to this directory
3. **Backup**: Regular backups with encryption

## Reference

### Configuration Files Modified

1. **brokik-api/config/storage.yml**
   - Added `host_disk` service configuration

2. **DevOps/apps/brokik-api/.env.production.template**
   - Added Active Storage environment variables
   - Documented service options

3. **DevOps/common/docker-utils.sh**
   - Updated `start_container()` to mount Active Storage volume
   - Updated `start_worker_container()` to mount Active Storage volume
   - Updated `start_scheduler_container()` to mount Active Storage volume

4. **DevOps/common/app-types/rails.sh**
   - Added `rails_load_active_storage_config()` function
   - Automatically creates storage directory during deployment

### Migration Script

**Location**: `DevOps/scripts/migrate-scaleway-to-local-storage.sh`

**Features**:
- Automated migration with progress tracking
- Preserves Active Storage directory structure
- Backup of original configuration
- Verification of file counts
- Interactive restart prompt
- Detailed error reporting

### Environment Variables

```bash
# Required for host_disk service
RAILS_ACTIVE_STORAGE_SERVICE=host_disk
ACTIVE_STORAGE_HOST_PATH=/var/storage/{app-name}/active_storage
FILES_STORAGE_URL={your-domain.com}

# Optional (for Scaleway rollback)
# SCALEWAY_ENDPOINT=https://...
# SCALEWAY_ACCESS_KEY_ID=...
# SCALEWAY_SECRET_ACCESS_KEY=...
# SCALEWAY_REGION=...
# SCALEWAY_BUCKET_NAME=...
```

## Support

For issues or questions:

1. Check logs: `docker logs brokik-api_web_1 -f`
2. Verify configuration: `cat ~/apps/brokik-api/.env.production | grep STORAGE`
3. Check volume mounts: `docker inspect brokik-api_web_1 | grep -A 5 Mounts`
4. Review this documentation
5. Check migration script output for errors

---

**Last Updated**: 2025-11-01
**Version**: 1.0
**Author**: DevOps Team
