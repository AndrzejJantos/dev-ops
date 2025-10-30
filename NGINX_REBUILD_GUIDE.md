# Nginx Configuration Rebuild Guide

## Overview

The `rebuild-nginx-configs.sh` script provides a safe, automated way to cleanly rebuild all nginx configurations from templates. It performs comprehensive validation, creates backups, and ensures zero-downtime deployment.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Pre-Flight Checklist](#pre-flight-checklist)
- [Usage](#usage)
- [What the Script Does](#what-the-script-does)
- [Dry Run Mode](#dry-run-mode)
- [Troubleshooting](#troubleshooting)
- [Recovery Procedures](#recovery-procedures)

---

## Features

✅ **Automatic Discovery**: Finds all applications with nginx templates
✅ **Safe Backup**: Creates timestamped backups before making changes
✅ **Container Verification**: Checks if application containers are running
✅ **SSL Validation**: Verifies SSL certificates exist and are valid
✅ **Configuration Testing**: Tests nginx config before applying
✅ **Dry Run Mode**: Preview changes without modifying anything
✅ **Rollback Support**: Automatic restore on failure
✅ **Color-Coded Output**: Easy-to-read status messages

---

## Prerequisites

### Required Tools

The script checks for these automatically, but ensure they're installed:

```bash
# Nginx (required)
sudo apt-get install nginx

# Perl (required for config generation)
sudo apt-get install perl

# Docker (recommended for container checks)
sudo apt-get install docker.io

# Certbot (required for SSL management)
sudo apt-get install certbot python3-certbot-nginx

# Network tools (recommended for port checks)
sudo apt-get install net-tools  # for netstat
# or
sudo apt-get install iproute2   # for ss
```

### Directory Structure

Ensure your DevOps directory has this structure:

```
DevOps/
├── rebuild-nginx-configs.sh          # This script
├── apps/
│   ├── cheaperfordrug-landing/
│   │   ├── config.sh                 # Required
│   │   └── nginx.conf.template       # Required
│   ├── cheaperfordrug-web/
│   │   ├── config.sh
│   │   └── nginx.conf.template
│   └── cheaperfordrug-api/
│       ├── config.sh
│       └── nginx.conf.template
└── common/
    └── nginx/
        └── default-server.conf
```

### Required Permissions

The script needs sudo access for:
- Reading/writing `/etc/nginx/` directories
- Testing nginx configuration
- Reloading nginx service
- Checking SSL certificates in `/etc/letsencrypt/`

---

## Pre-Flight Checklist

Before running the script, verify:

### 1. Applications Are Deployed

```bash
# Check if application containers are running
docker ps | grep cheaperfordrug

# Expected output: containers for landing, web, and api
```

### 2. Containers Are Listening on Expected Ports

```bash
# Check ports
sudo netstat -tlnp | grep -E ':(3010|3011|3020|3021|3030|3031|3032)'

# Or with ss
sudo ss -tlnp | grep -E ':(3010|3011|3020|3021|3030|3031|3032)'
```

Expected ports:
- **cheaperfordrug-landing**: 3010-3011 (2 containers)
- **cheaperfordrug-api**: 3020-3021 (2 containers)
- **cheaperfordrug-web**: 3030-3032 (3 containers)

### 3. SSL Certificates Exist

```bash
# Check SSL certificates
sudo certbot certificates

# Should show certificates for:
# - taniejpolek.pl (landing)
# - premiera.taniejpolek.pl (web)
# - api-public.cheaperfordrug.com and api-internal.cheaperfordrug.com (api)
```

### 4. DNS Is Configured

```bash
# Verify DNS resolution
dig +short taniejpolek.pl A
dig +short www.taniejpolek.pl A
dig +short presale.taniejpolek.pl A
dig +short premiera.taniejpolek.pl A
dig +short api-public.cheaperfordrug.com A
dig +short api-internal.cheaperfordrug.com A

# All should return your server's IP address
```

### 5. Current Nginx Is Working

```bash
# Check nginx status
sudo systemctl status nginx

# Test current configuration
sudo nginx -t
```

---

## Usage

### Basic Usage

```bash
# Navigate to DevOps directory
cd ~/DevOps

# Make script executable (first time only)
chmod +x rebuild-nginx-configs.sh

# Run with dry-run first (RECOMMENDED)
./rebuild-nginx-configs.sh --dry-run

# If dry-run looks good, run for real
./rebuild-nginx-configs.sh
```

### Command-Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--dry-run` | `-d` | Preview changes without modifying anything |
| `--skip-ssl` | `-s` | Skip SSL certificate validation |
| `--force` | `-f` | Continue even if validation fails |
| `--help` | `-h` | Show help message |

### Usage Examples

#### Example 1: Safe Rebuild (Recommended)

```bash
# Step 1: Dry run to preview
./rebuild-nginx-configs.sh --dry-run

# Step 2: If everything looks good, run for real
./rebuild-nginx-configs.sh
```

#### Example 2: Quick Rebuild Without SSL Check

If you know SSL certificates exist and are valid:

```bash
./rebuild-nginx-configs.sh --skip-ssl
```

#### Example 3: Force Rebuild Despite Warnings

If some containers aren't running but you want to rebuild anyway:

```bash
./rebuild-nginx-configs.sh --force
```

⚠️ **Warning**: Using `--force` skips safety checks. Use only if you know what you're doing.

#### Example 4: Rebuild After Fixing Issues

```bash
# First, start any missing containers
cd ~/apps/cheaperfordrug-landing
docker-compose up -d

# Then rebuild
cd ~/DevOps
./rebuild-nginx-configs.sh
```

---

## What the Script Does

### Step-by-Step Process

#### 1. Pre-Flight Checks
- Verifies nginx is installed
- Checks for perl (required for template processing)
- Validates DevOps directory structure
- Checks docker availability

#### 2. Discovery
- Scans `DevOps/apps/` for applications
- Finds all `config.sh` and `nginx.conf.template` files
- Lists discovered applications

#### 3. Backup
- Creates timestamped backup directory: `/tmp/nginx_backup_YYYYMMDD_HHMMSS/`
- Backs up all files from `/etc/nginx/sites-available/`
- Saves list of enabled sites

#### 4. Cleanup
- Removes old configs from `/etc/nginx/sites-enabled/`
- Removes old configs from `/etc/nginx/sites-available/`
- Preserves `default` and `000-default` files

#### 5. Container Verification
- Checks if application containers are running
- Verifies ports are listening
- Reports any missing containers

#### 6. Configuration Generation
- Sources each application's `config.sh`
- Generates upstream server blocks
- Processes templates with perl
- Creates new configs in `/etc/nginx/sites-available/`

#### 7. SSL Validation
- Checks for SSL certificate files
- Validates certificate expiration dates
- Warns if certificates expire within 30 days
- Provides commands to create missing certificates

#### 8. Testing
- Creates symlinks in `/etc/nginx/sites-enabled/`
- Runs `nginx -t` to validate configuration
- Rolls back if validation fails

#### 9. Reload
- Reloads nginx with `systemctl reload nginx`
- Verifies nginx is running
- Reports any errors

#### 10. Verification
- Confirms all sites are enabled
- Tests HTTP to HTTPS redirects
- Displays final summary

---

## Dry Run Mode

**Always run in dry-run mode first!**

```bash
./rebuild-nginx-configs.sh --dry-run
```

### What Dry Run Does

- ✅ Runs all pre-flight checks
- ✅ Discovers applications
- ✅ Verifies containers are running
- ✅ Validates SSL certificates
- ✅ Shows what would be changed
- ❌ Does NOT create backups
- ❌ Does NOT modify any files
- ❌ Does NOT reload nginx

### Dry Run Output

```
[INFO] Would create backup in: /tmp/nginx_backup_20251030_143052
[INFO] Would remove all nginx configs except:
  - default
  - 000-default
[INFO] Would generate: /etc/nginx/sites-available/cheaperfordrug-landing
[INFO] Would generate: /etc/nginx/sites-available/cheaperfordrug-web
[INFO] Would generate: /etc/nginx/sites-available/cheaperfordrug-api
[INFO] Would test nginx configuration
[INFO] Would reload nginx
```

---

## Troubleshooting

### Problem: Script Says "Perl is not installed"

**Solution:**
```bash
sudo apt-get update
sudo apt-get install perl
```

### Problem: "SSL validation failed"

**Symptoms:**
```
[ERROR] ✗ Certificate not found at /etc/letsencrypt/live/taniejpolek.pl/fullchain.pem
```

**Solution 1: Create the certificate**
```bash
sudo certbot --nginx \
  -d taniejpolek.pl \
  -d www.taniejpolek.pl \
  -d presale.taniejpolek.pl
```

**Solution 2: Skip SSL validation (temporary)**
```bash
./rebuild-nginx-configs.sh --skip-ssl
```

### Problem: "Port 3010 is NOT listening"

**Symptoms:**
```
[WARNING] ✗ Port 3010 is NOT listening
```

**Solution:**
```bash
# Check if containers are running
docker ps | grep cheaperfordrug-landing

# If not running, start them
cd ~/apps/cheaperfordrug-landing
docker-compose up -d

# Verify they're running
docker ps
curl -I http://localhost:3010/up
```

### Problem: "Nginx configuration test failed"

**Symptoms:**
```
[ERROR] Nginx configuration test failed!
nginx: [emerg] duplicate upstream "cheaperfordrug_landing_backend"
```

**Solution:**

The script automatically restores from backup. Check what went wrong:

```bash
# View the problematic config
sudo cat /etc/nginx/sites-available/cheaperfordrug-landing

# Check for syntax errors
sudo nginx -t
```

Common issues:
- Duplicate upstream blocks
- Missing SSL certificate files
- Invalid server_name directives
- Port conflicts

### Problem: "Nginx failed to reload"

**Symptoms:**
```
[ERROR] Nginx failed to reload!
```

**Solution:**
```bash
# Check nginx status
sudo systemctl status nginx

# View error logs
sudo journalctl -u nginx -n 50

# Check what's wrong
sudo nginx -t

# Restart nginx (more forceful than reload)
sudo systemctl restart nginx
```

### Problem: Script hangs during SSL check

**Solution:**

Press `Ctrl+C` and run with `--skip-ssl`:

```bash
./rebuild-nginx-configs.sh --skip-ssl
```

### Problem: "Docker is not installed"

The script will work but skip container checks:

```
[WARNING] Docker is not installed - container checks will be skipped
```

This is fine if you're confident containers are running. Otherwise:

```bash
# Check containers manually
ps aux | grep docker
sudo systemctl status docker
```

---

## Recovery Procedures

### Scenario 1: Script Failed, Need to Restore

If the script fails and auto-restore doesn't work:

```bash
# Find the backup directory
ls -ltr /tmp/nginx_backup_*

# Use the most recent one
BACKUP_DIR="/tmp/nginx_backup_20251030_143052"

# Restore sites-available
sudo rm -rf /etc/nginx/sites-available/*
sudo cp -r $BACKUP_DIR/sites-available/* /etc/nginx/sites-available/

# Manually recreate enabled sites
sudo ln -sf /etc/nginx/sites-available/cheaperfordrug-landing /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/cheaperfordrug-web /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/cheaperfordrug-api /etc/nginx/sites-enabled/

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

### Scenario 2: Need to Manually Regenerate One Config

If only one app config is problematic:

```bash
cd ~/DevOps/apps/cheaperfordrug-landing

# Source the configuration
source config.sh

# Generate upstream servers
UPSTREAM_SERVERS="    server localhost:3010 max_fails=3 fail_timeout=30s;
    server localhost:3011 max_fails=3 fail_timeout=30s;"

# Generate config
perl -pe "s|{{NGINX_UPSTREAM_NAME}}|${NGINX_UPSTREAM_NAME}|g; s|{{DOMAIN}}|${DOMAIN}|g; s|{{APP_NAME}}|${APP_NAME}|g;" nginx.conf.template | perl -pe "BEGIN{undef \$/;} s|{{UPSTREAM_SERVERS}}|${UPSTREAM_SERVERS}|gs" | sudo tee /etc/nginx/sites-available/$APP_NAME > /dev/null

# Enable it
sudo ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

### Scenario 3: Complete Nginx Reset

If everything is broken and you need to start fresh:

```bash
# Stop nginx
sudo systemctl stop nginx

# Remove all custom configs
sudo rm /etc/nginx/sites-enabled/*
sudo rm /etc/nginx/sites-available/*

# Restore default nginx config
sudo apt-get install --reinstall nginx

# Now run the rebuild script
cd ~/DevOps
./rebuild-nginx-configs.sh
```

---

## Advanced Usage

### Running on Remote Server

```bash
# Copy script to server
scp rebuild-nginx-configs.sh andrzej@webet:~/DevOps/

# SSH into server
ssh andrzej@webet

# Run script
cd ~/DevOps
./rebuild-nginx-configs.sh --dry-run
```

### Automating Rebuilds

⚠️ **Not recommended for production** - only use for testing environments:

```bash
# Add to cron (rebuild nightly at 3 AM)
crontab -e

# Add this line:
0 3 * * * cd ~/DevOps && ./rebuild-nginx-configs.sh --skip-ssl >> ~/DevOps/rebuild.log 2>&1
```

### Integrating with CI/CD

```yaml
# Example GitHub Actions workflow
- name: Deploy Nginx Configs
  run: |
    scp rebuild-nginx-configs.sh server:~/DevOps/
    ssh server "cd ~/DevOps && ./rebuild-nginx-configs.sh --skip-ssl"
```

---

## Post-Rebuild Verification

After successful rebuild, verify everything works:

### 1. Test Each Domain

```bash
# Test landing page
curl -I https://www.taniejpolek.pl
curl -I https://presale.taniejpolek.pl

# Test web app
curl -I https://premiera.taniejpolek.pl

# Test API
curl -I https://api-public.cheaperfordrug.com/up
curl -I https://api-internal.cheaperfordrug.com/up
```

Expected: All should return `200 OK` or appropriate redirects.

### 2. Check Logs

```bash
# Nginx error logs
sudo tail -f /var/log/nginx/error.log

# Nginx access logs
sudo tail -f /var/log/nginx/access.log

# Per-app logs (if configured)
sudo tail -f /var/log/nginx/cheaperfordrug-landing-error.log
```

### 3. Monitor Container Health

```bash
# Check container logs
docker logs cheaperfordrug-landing-web-1 --tail 50
docker logs cheaperfordrug-web-1 --tail 50
docker logs cheaperfordrug-api-web-1 --tail 50

# Check container resource usage
docker stats
```

### 4. Test from Browser

Open each domain in a browser:
- https://www.taniejpolek.pl
- https://presale.taniejpolek.pl
- https://premiera.taniejpolek.pl

Verify:
- ✅ HTTPS is working (green padlock)
- ✅ No certificate warnings
- ✅ Pages load correctly
- ✅ HTTP redirects to HTTPS

---

## Best Practices

### 1. Always Dry Run First

```bash
./rebuild-nginx-configs.sh --dry-run
```

### 2. Run During Low Traffic

Schedule rebuilds during maintenance windows or low-traffic periods.

### 3. Keep Backups

Backups are created automatically, but keep them for a while:

```bash
# Backups are in /tmp/nginx_backup_*
# Move important backups to a safe location
sudo cp -r /tmp/nginx_backup_20251030_143052 ~/nginx_backups/
```

### 4. Monitor After Changes

Watch logs for 5-10 minutes after rebuild:

```bash
# Watch error log
sudo tail -f /var/log/nginx/error.log

# In another terminal, watch access log
sudo tail -f /var/log/nginx/access.log
```

### 5. Document Changes

Keep notes about why you rebuilt:

```bash
# Example
echo "$(date): Rebuilt nginx configs after adding new domain" >> ~/DevOps/rebuild-history.txt
```

---

## Getting Help

If you encounter issues not covered here:

1. Check nginx error logs: `sudo tail -f /var/log/nginx/error.log`
2. Test nginx config: `sudo nginx -t`
3. Check script output carefully - it's color-coded for easy diagnosis
4. Review the backup: Files are in `/tmp/nginx_backup_*`
5. Contact DevOps team with:
   - Script output
   - Nginx error logs
   - Output of `sudo nginx -t`
   - Container status: `docker ps`

---

## Appendix: Configuration Template Variables

The script replaces these variables in `nginx.conf.template`:

| Variable | Example Value | Source |
|----------|---------------|--------|
| `{{NGINX_UPSTREAM_NAME}}` | `cheaperfordrug_landing_backend` | `config.sh` |
| `{{DOMAIN}}` | `taniejpolek.pl` | `config.sh` |
| `{{APP_NAME}}` | `cheaperfordrug-landing` | `config.sh` |
| `{{UPSTREAM_SERVERS}}` | `server localhost:3010...` | Generated from `BASE_PORT` + `DEFAULT_SCALE` |

---

## Version History

- **v1.0** (2025-10-30): Initial release
  - Automatic application discovery
  - Backup and restore functionality
  - Container verification
  - SSL validation
  - Dry-run mode
