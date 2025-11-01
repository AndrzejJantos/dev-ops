# CDN Setup for Active Storage Files

## Overview

This document describes the nginx-based CDN solution for serving Active Storage files directly from the filesystem, bypassing Rails for improved performance.

**Domain**: `cdn.webet.pl`
**Storage Path**: `/var/storage/{app-name}/active_storage/`
**URL Pattern**: `https://cdn.webet.pl/{app-name}/blobs/{key}`

## Architecture

### Before (Inefficient)
```
User Request → nginx → Rails → File System → Rails → nginx → User
URL: https://api-public.brokik.com/rails/active_storage/blobs/{key}
```

### After (Optimized)
```
User Request → nginx → File System → User
URL: https://cdn.webet.pl/brokik-api/blobs/{key}
```

## Benefits

1. **Performance**: nginx serves static files directly without Rails overhead
2. **Reduced Load**: Rails processes are freed for API requests
3. **Scalability**: nginx can handle thousands of concurrent static file requests
4. **Caching**: Proper cache headers for browser and CDN caching
5. **Generic**: Works for any app following the storage structure

## Components

### 1. Nginx Configuration
**File**: `/Users/andrzej/Development/Brokik/DevOps/common/nginx/cdn.conf`
**Server Path**: `/etc/nginx/sites-available/cdn.conf`

Features:
- HTTP to HTTPS redirect
- SSL/TLS termination
- CORS headers for cross-origin requests
- Gzip compression
- Cache-Control headers (1 year cache)
- Security headers
- Support for both blobs and variants

### 2. Active Storage Initializer
**File**: `/Users/andrzej/Development/Brokik/brokik-api/config/initializers/active_storage.rb`

Changes:
- Modified `ActiveStorage::Attached::One#url` method
- Generates CDN URLs instead of Rails routes
- Uses `CDN_HOST` environment variable
- Falls back to Rails routes if CDN_HOST not set

### 3. Next.js Configuration
**File**: `/Users/andrzej/Development/Brokik/brokik-web/next.config.js`

Changes:
- Added `cdn.webet.pl` to `remotePatterns` for Next.js Image optimization

## Deployment Instructions

### Step 1: DNS Configuration

Add an A record or CNAME for `cdn.webet.pl` pointing to your server:

```
cdn.webet.pl.  IN  A  <your-server-ip>
```

Or if using a CNAME:
```
cdn.webet.pl.  IN  CNAME  <your-main-domain>
```

### Step 2: SSL Certificate

Obtain an SSL certificate for `cdn.webet.pl`:

```bash
# SSH to server
ssh hetzner-andrzej

# Obtain certificate using certbot
sudo certbot certonly --nginx -d cdn.webet.pl

# Verify certificate was created
sudo ls -la /etc/letsencrypt/live/cdn.webet.pl/
```

Expected output:
```
cert.pem
chain.pem
fullchain.pem
privkey.pem
```

### Step 3: Deploy Nginx Configuration

```bash
# From local machine, copy nginx config to DevOps repo on server
scp /Users/andrzej/Development/Brokik/DevOps/common/nginx/cdn.conf hetzner-andrzej:~/DevOps/common/nginx/

# SSH to server
ssh hetzner-andrzej

# Copy to nginx sites-available
sudo cp ~/DevOps/common/nginx/cdn.conf /etc/nginx/sites-available/cdn.conf

# Create symbolic link to sites-enabled
sudo ln -s /etc/nginx/sites-available/cdn.conf /etc/nginx/sites-enabled/cdn.conf

# Test nginx configuration
sudo nginx -t

# If test passes, reload nginx
sudo systemctl reload nginx
```

### Step 4: Update brokik-api Environment Variables

Edit the environment file for brokik-api:

```bash
# SSH to server
ssh hetzner-andrzej

# Edit .env file
nano ~/apps/brokik-api/.env
```

Add these environment variables:

```bash
# CDN Configuration
CDN_HOST=https://cdn.webet.pl
APP_NAME=brokik-api
```

**Important**: The `FILES_STORAGE_URL` variable is no longer used for Active Storage URLs when CDN is configured.

### Step 5: Verify Storage Structure

Ensure the storage directory exists with correct permissions:

```bash
# SSH to server
ssh hetzner-andrzej

# Check if storage directory exists
ls -la /var/storage/brokik-api/

# If not, create it
sudo mkdir -p /var/storage/brokik-api/active_storage

# Set ownership (replace 'andrzej' with actual app user if different)
sudo chown -R andrzej:andrzej /var/storage/brokik-api/

# Verify permissions
ls -la /var/storage/
```

### Step 6: Deploy brokik-api Changes

```bash
# From local machine, commit and push changes
cd /Users/andrzej/Development/Brokik/brokik-api
git add config/initializers/active_storage.rb
git commit -m "Add CDN URL generation for Active Storage"
git push origin main

# Deploy to server (use your deployment script)
ssh hetzner-andrzej
cd ~/apps/brokik-api/repo
git pull origin main

# Restart Rails application
docker compose restart web
# OR if using systemd
sudo systemctl restart brokik-api
```

### Step 7: Deploy brokik-web Changes

```bash
# From local machine, commit and push changes
cd /Users/andrzej/Development/Brokik/brokik-web
git add next.config.js
git commit -m "Add CDN domain to Next.js image optimization"
git push origin main

# Deploy to server (use your deployment script)
ssh hetzner-andrzej
cd ~/apps/brokik-web/repo
git pull origin main

# Rebuild and restart
docker compose build web
docker compose restart web
# OR if using systemd
sudo systemctl restart brokik-web
```

### Step 8: Test the CDN

1. **Test nginx health check**:
```bash
curl https://cdn.webet.pl/health
# Expected: "CDN OK"
```

2. **Test file serving** (replace with actual blob key):
```bash
# Get a blob key from your database
ssh hetzner-andrzej
cd ~/apps/brokik-api/repo
docker compose exec web rails console

# In Rails console:
blob = ActiveStorage::Blob.first
puts blob.key
# Copy the key output

# Test CDN URL
curl -I https://cdn.webet.pl/brokik-api/blobs/{paste-key-here}
# Expected: HTTP 200 OK with proper headers
```

3. **Test from application**:
- Access your application
- Upload an image
- Inspect the image URL in browser DevTools
- It should be: `https://cdn.webet.pl/brokik-api/blobs/{key}`
- Verify the image loads correctly

4. **Check headers**:
```bash
curl -I https://cdn.webet.pl/brokik-api/blobs/{key}
```

Expected headers:
```
HTTP/2 200
cache-control: public, immutable
expires: <1 year from now>
access-control-allow-origin: *
x-content-type-options: nosniff
content-type: image/jpeg (or appropriate)
```

## Troubleshooting

### Issue: 404 Not Found

**Possible causes**:
1. File doesn't exist at expected path
2. Incorrect permissions
3. Wrong blob key

**Debug**:
```bash
# Check if file exists
ls -la /var/storage/brokik-api/active_storage/{key}

# Check nginx error logs
sudo tail -f /var/log/nginx/cdn-error.log

# Check nginx access logs
sudo tail -f /var/log/nginx/cdn-access.log
```

### Issue: 403 Forbidden

**Possible causes**:
1. Incorrect file permissions
2. Nginx user doesn't have read access

**Fix**:
```bash
# Fix permissions
sudo chown -R www-data:www-data /var/storage/brokik-api/active_storage/
sudo chmod -R 755 /var/storage/brokik-api/active_storage/
```

### Issue: SSL Certificate Error

**Possible causes**:
1. Certificate not obtained for cdn.webet.pl
2. Certificate path incorrect in nginx config

**Fix**:
```bash
# Obtain certificate
sudo certbot certonly --nginx -d cdn.webet.pl

# Verify nginx config points to correct certificate
sudo nginx -t
```

### Issue: Old URLs Still Using Rails Routes

**Possible causes**:
1. CDN_HOST environment variable not set
2. Application not restarted after changes
3. Cached responses

**Fix**:
```bash
# Verify environment variable
ssh hetzner-andrzej
cd ~/apps/brokik-api
cat .env | grep CDN_HOST

# Restart application
docker compose restart web

# Clear Rails cache if needed
docker compose exec web rails console
Rails.cache.clear
```

### Issue: CORS Errors

**Symptoms**: Browser console shows CORS errors when loading images

**Fix**: CORS headers are already configured in nginx. If issues persist:
```bash
# Verify CORS headers
curl -I https://cdn.webet.pl/brokik-api/blobs/{key}

# Should include:
# access-control-allow-origin: *
```

## Adding New Applications

To add CDN support for additional applications:

1. **Ensure storage structure**:
```bash
sudo mkdir -p /var/storage/{new-app-name}/active_storage
sudo chown -R {app-user}:{app-group} /var/storage/{new-app-name}
```

2. **Add environment variables** to the new app:
```bash
CDN_HOST=https://cdn.webet.pl
APP_NAME={new-app-name}
```

3. **Update Active Storage initializer** (similar to brokik-api)

4. **Test**:
```bash
curl https://cdn.webet.pl/{new-app-name}/blobs/{key}
```

No nginx reconfiguration needed - the existing config supports all apps!

## Performance Monitoring

### Monitor nginx access logs:
```bash
sudo tail -f /var/log/nginx/cdn-access.log
```

### Monitor cache hit rates:
```bash
# Check response times
curl -w "@curl-format.txt" -o /dev/null -s https://cdn.webet.pl/brokik-api/blobs/{key}
```

### curl-format.txt:
```
time_namelookup:  %{time_namelookup}\n
time_connect:  %{time_connect}\n
time_appconnect:  %{time_appconnect}\n
time_pretransfer:  %{time_pretransfer}\n
time_redirect:  %{time_redirect}\n
time_starttransfer:  %{time_starttransfer}\n
----------\n
time_total:  %{time_total}\n
```

## Security Considerations

1. **HTTPS Only**: All traffic forced through HTTPS
2. **CORS**: Configured to allow all origins (public CDN)
3. **No Directory Listing**: nginx doesn't expose directory structure
4. **No Hidden Files**: Access to dotfiles denied
5. **Immutable Cache**: Files cached with immutable flag (blobs don't change)

## Maintenance

### Certificate Renewal
Certbot auto-renewal is configured. Verify:
```bash
sudo certbot renew --dry-run
```

### Log Rotation
Nginx logs are automatically rotated by logrotate:
```bash
cat /etc/logrotate.d/nginx
```

### Storage Cleanup
Monitor storage usage:
```bash
du -sh /var/storage/*
```

To clean up orphaned files (use with caution):
```bash
# List files older than 90 days not referenced in database
# This should be done through Rails, not directly
cd ~/apps/brokik-api/repo
docker compose exec web rails console
# ActiveStorage::Blob cleanup logic here
```

## Rollback Plan

If CDN causes issues, disable it by:

1. **Remove CDN_HOST environment variable**:
```bash
# Edit .env, remove or comment out:
# CDN_HOST=https://cdn.webet.pl

# Restart app
docker compose restart web
```

2. Application will fall back to Rails routes automatically

3. **Remove nginx config** (optional):
```bash
sudo rm /etc/nginx/sites-enabled/cdn.conf
sudo systemctl reload nginx
```

## Next Steps

Consider adding:
1. **CDN Layer**: Cloudflare or similar in front of nginx for global caching
2. **Image Optimization**: nginx image filter module for on-the-fly resizing
3. **Monitoring**: Add monitoring for CDN response times and error rates
4. **Backup Strategy**: Ensure /var/storage is included in backup scripts

## References

- Nginx configuration: `/Users/andrzej/Development/Brokik/DevOps/common/nginx/cdn.conf`
- Active Storage initializer: `/Users/andrzej/Development/Brokik/brokik-api/config/initializers/active_storage.rb`
- Next.js config: `/Users/andrzej/Development/Brokik/brokik-web/next.config.js`
- Rails Active Storage docs: https://edgeguides.rubyonrails.org/active_storage_overview.html
