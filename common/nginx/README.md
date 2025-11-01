# Nginx Configuration Files

This directory contains common nginx configuration files used across all applications.

## Files

### cdn.conf
**Purpose**: CDN configuration for serving Active Storage files directly from nginx

**Domain**: `cdn.webet.pl`

**Features**:
- Direct file serving from `/var/storage/{app-name}/active_storage/`
- HTTP to HTTPS redirect
- SSL/TLS with Let's Encrypt certificates
- CORS headers for public access
- Gzip compression
- Aggressive caching (1 year with immutable flag)
- Security headers
- Health check endpoint at `/health`

**URL Pattern**:
- Blobs: `https://cdn.webet.pl/{app-name}/blobs/{key}`
- Variants: `https://cdn.webet.pl/{app-name}/variants/{key}`

**File Mapping**:
- URL: `https://cdn.webet.pl/brokik-api/blobs/abc123`
- File: `/var/storage/brokik-api/active_storage/abc123`

**Deployment**:
```bash
# Quick deploy
cd /Users/andrzej/Development/Brokik/DevOps
./scripts/deploy-cdn.sh

# Manual deploy
scp common/nginx/cdn.conf hetzner-andrzej:~/DevOps/common/nginx/
ssh hetzner-andrzej
sudo cp ~/DevOps/common/nginx/cdn.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/cdn.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

**Documentation**: See `/Users/andrzej/Development/Brokik/DevOps/docs/cdn-setup.md`

---

### default-server.conf
**Purpose**: Catch-all server block for undefined domains

**Features**:
- Catches requests that don't match any specific server_name
- Allows certbot for SSL certificate challenges
- Rejects all other requests with 444 status (close connection)
- Applies to both HTTP and HTTPS

**Deployment**:
```bash
sudo cp ~/DevOps/common/nginx/default-server.conf /etc/nginx/sites-available/000-default
sudo ln -s /etc/nginx/sites-available/000-default /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## Usage

These configurations are designed to be:
1. **Generic**: Work across multiple applications
2. **Reusable**: Can be deployed to multiple servers
3. **Production-ready**: Include security and performance best practices

## Security Best Practices

All nginx configurations follow these security principles:

1. **HTTPS Only**: Force HTTPS for all traffic
2. **Modern TLS**: TLS 1.2 and 1.3 only
3. **Security Headers**: X-Content-Type-Options, X-Frame-Options, HSTS
4. **No Directory Listing**: Prevent directory traversal
5. **Hidden Files Protected**: Deny access to dotfiles
6. **Rate Limiting**: Consider adding rate limiting for production

## Performance Optimizations

1. **HTTP/2**: Enabled on all HTTPS connections
2. **Gzip Compression**: Enabled for text-based content
3. **Keep-Alive**: Reuse connections
4. **Buffer Settings**: Optimized for typical workloads
5. **Cache Headers**: Aggressive caching for static assets

## Monitoring

Check nginx logs for issues:
```bash
# Access logs
sudo tail -f /var/log/nginx/cdn-access.log

# Error logs
sudo tail -f /var/log/nginx/cdn-error.log

# All nginx logs
sudo tail -f /var/log/nginx/*.log
```

## Testing

Test nginx configuration:
```bash
sudo nginx -t
```

Test specific endpoint:
```bash
curl -I https://cdn.webet.pl/health
curl -I https://cdn.webet.pl/brokik-api/blobs/{key}
```

## References

- Nginx documentation: https://nginx.org/en/docs/
- Let's Encrypt: https://letsencrypt.org/
- SSL configuration: https://ssl-config.mozilla.org/
