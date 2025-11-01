# CDN Quick Reference

## Quick Deploy

```bash
# From local DevOps directory
cd /Users/andrzej/Development/Brokik/DevOps
./scripts/deploy-cdn.sh
```

## Environment Variables (brokik-api)

Add to `~/apps/brokik-api/.env`:

```bash
CDN_HOST=https://cdn.webet.pl
APP_NAME=brokik-api
```

## URL Pattern

| Type | Old URL | New CDN URL |
|------|---------|-------------|
| Blob | `https://api-public.brokik.com/rails/active_storage/blobs/{key}` | `https://cdn.webet.pl/brokik-api/blobs/{key}` |
| Variant | `https://api-public.brokik.com/rails/active_storage/variants/{key}` | `https://cdn.webet.pl/brokik-api/variants/{key}` |

## File Structure

```
/var/storage/
└── brokik-api/
    └── active_storage/
        ├── {key1}    # Blob file
        ├── {key2}    # Blob file
        └── ...
```

## Quick Tests

```bash
# Health check
curl https://cdn.webet.pl/health

# Test file serving (replace {key} with actual blob key)
curl -I https://cdn.webet.pl/brokik-api/blobs/{key}

# Check headers
curl -I https://cdn.webet.pl/brokik-api/blobs/{key} | grep -i "cache-control\|expires\|access-control"
```

## Quick Troubleshooting

### 404 Not Found
```bash
# Check if file exists
ssh hetzner-andrzej "ls -la /var/storage/brokik-api/active_storage/{key}"

# Check nginx logs
ssh hetzner-andrzej "sudo tail -n 50 /var/log/nginx/cdn-error.log"
```

### 403 Forbidden
```bash
# Fix permissions
ssh hetzner-andrzej "sudo chown -R www-data:www-data /var/storage/brokik-api/active_storage/"
ssh hetzner-andrzej "sudo chmod -R 755 /var/storage/brokik-api/active_storage/"
```

### Application Still Using Old URLs
```bash
# Verify environment variables
ssh hetzner-andrzej "grep CDN_HOST ~/apps/brokik-api/.env"

# Restart application
ssh hetzner-andrzej "cd ~/apps/brokik-api && docker compose restart web"
```

## Quick Commands

```bash
# Reload nginx (after config changes)
ssh hetzner-andrzej "sudo systemctl reload nginx"

# Test nginx config
ssh hetzner-andrzej "sudo nginx -t"

# View access logs
ssh hetzner-andrzej "sudo tail -f /var/log/nginx/cdn-access.log"

# View error logs
ssh hetzner-andrzej "sudo tail -f /var/log/nginx/cdn-error.log"

# Check storage usage
ssh hetzner-andrzej "du -sh /var/storage/brokik-api/"

# Get blob key from Rails console
ssh hetzner-andrzej "cd ~/apps/brokik-api && docker compose exec web rails console"
# Then: ActiveStorage::Blob.first.key
```

## Nginx Config Location

- **Local**: `/Users/andrzej/Development/Brokik/DevOps/common/nginx/cdn.conf`
- **Server**: `/etc/nginx/sites-available/cdn.conf`
- **Enabled**: `/etc/nginx/sites-enabled/cdn.conf` (symlink)

## Application Files Modified

1. **brokik-api**: `config/initializers/active_storage.rb`
2. **brokik-web**: `next.config.js`

## Rollback

```bash
# Remove CDN_HOST from .env
ssh hetzner-andrzej "nano ~/apps/brokik-api/.env"

# Restart app
ssh hetzner-andrzej "cd ~/apps/brokik-api && docker compose restart web"

# Application falls back to Rails routes automatically
```

## Adding New Apps

```bash
# Create storage directory
ssh hetzner-andrzej "sudo mkdir -p /var/storage/{new-app}/active_storage"
ssh hetzner-andrzej "sudo chown -R {user}:{group} /var/storage/{new-app}"

# Add environment variables to new app
CDN_HOST=https://cdn.webet.pl
APP_NAME={new-app}

# Test
curl https://cdn.webet.pl/{new-app}/blobs/{key}
```

## Full Documentation

See `docs/cdn-setup.md` for complete documentation.
