# CDN Deployment Checklist

Use this checklist to deploy the nginx-based CDN solution for Active Storage files.

## Pre-Deployment Checklist

- [ ] DNS record for `cdn.webet.pl` is configured
- [ ] Server is accessible via `ssh hetzner-andrzej`
- [ ] Storage directory `/var/storage/brokik-api/active_storage` exists
- [ ] DevOps repository is up to date on local machine
- [ ] brokik-api repository is up to date on local machine
- [ ] brokik-web repository is up to date on local machine

## DNS Configuration

- [ ] Add A record or CNAME for `cdn.webet.pl` pointing to server IP
- [ ] Verify DNS propagation: `nslookup cdn.webet.pl`
- [ ] Wait for DNS propagation if needed (up to 48 hours, usually minutes)

## SSL Certificate

- [ ] SSH to server: `ssh hetzner-andrzej`
- [ ] Obtain certificate: `sudo certbot certonly --nginx -d cdn.webet.pl`
- [ ] Verify certificate exists: `sudo ls -la /etc/letsencrypt/live/cdn.webet.pl/`
- [ ] Check certificate expiry: `sudo certbot certificates`

## Nginx Configuration Deployment

### Option 1: Automated Deployment (Recommended)

- [ ] From local machine, run: `cd /Users/andrzej/Development/Brokik/DevOps`
- [ ] Execute deployment script: `./scripts/deploy-cdn.sh`
- [ ] Follow the prompts and verify all steps complete successfully
- [ ] Skip to "Testing" section below

### Option 2: Manual Deployment

- [ ] Copy nginx config to server:
  ```bash
  scp /Users/andrzej/Development/Brokik/DevOps/common/nginx/cdn.conf hetzner-andrzej:~/DevOps/common/nginx/
  ```

- [ ] SSH to server: `ssh hetzner-andrzej`

- [ ] Copy to nginx sites-available:
  ```bash
  sudo cp ~/DevOps/common/nginx/cdn.conf /etc/nginx/sites-available/cdn.conf
  ```

- [ ] Create symbolic link:
  ```bash
  sudo ln -s /etc/nginx/sites-available/cdn.conf /etc/nginx/sites-enabled/cdn.conf
  ```

- [ ] Test nginx configuration:
  ```bash
  sudo nginx -t
  ```

- [ ] Reload nginx:
  ```bash
  sudo systemctl reload nginx
  ```

## Storage Directory Setup

- [ ] SSH to server (if not already): `ssh hetzner-andrzej`

- [ ] Verify storage directory exists:
  ```bash
  ls -la /var/storage/brokik-api/
  ```

- [ ] If directory doesn't exist, create it:
  ```bash
  sudo mkdir -p /var/storage/brokik-api/active_storage
  ```

- [ ] Set correct ownership:
  ```bash
  sudo chown -R andrzej:andrzej /var/storage/brokik-api
  ```

- [ ] Verify permissions:
  ```bash
  ls -la /var/storage/brokik-api/
  ```

## brokik-api Environment Configuration

- [ ] SSH to server (if not already): `ssh hetzner-andrzej`

- [ ] Edit environment file:
  ```bash
  nano ~/apps/brokik-api/.env
  ```

- [ ] Add CDN configuration:
  ```bash
  CDN_HOST=https://cdn.webet.pl
  APP_NAME=brokik-api
  ```

- [ ] Save and exit (Ctrl+O, Enter, Ctrl+X)

- [ ] Verify changes:
  ```bash
  grep CDN_HOST ~/apps/brokik-api/.env
  grep APP_NAME ~/apps/brokik-api/.env
  ```

## brokik-api Code Deployment

- [ ] From local machine, commit Active Storage changes:
  ```bash
  cd /Users/andrzej/Development/Brokik/brokik-api
  git status
  git add config/initializers/active_storage.rb
  git commit -m "Add CDN URL generation for Active Storage files"
  git push origin main
  ```

- [ ] SSH to server and pull changes:
  ```bash
  ssh hetzner-andrzej
  cd ~/apps/brokik-api/repo
  git pull origin main
  ```

- [ ] Restart application:
  ```bash
  cd ~/apps/brokik-api
  docker compose restart web
  ```
  OR if using systemd:
  ```bash
  sudo systemctl restart brokik-api
  ```

- [ ] Verify application started successfully:
  ```bash
  docker compose logs -f web
  # OR
  sudo systemctl status brokik-api
  ```

- [ ] Check for errors in logs
- [ ] Exit logs (Ctrl+C)

## brokik-web Code Deployment

- [ ] From local machine, commit Next.js config changes:
  ```bash
  cd /Users/andrzej/Development/Brokik/brokik-web
  git status
  git add next.config.js
  git commit -m "Add CDN domain to Next.js image optimization"
  git push origin main
  ```

- [ ] SSH to server and pull changes:
  ```bash
  ssh hetzner-andrzej
  cd ~/apps/brokik-web/repo
  git pull origin main
  ```

- [ ] Rebuild and restart application:
  ```bash
  cd ~/apps/brokik-web
  docker compose build web
  docker compose restart web
  ```
  OR if using systemd:
  ```bash
  sudo systemctl restart brokik-web
  ```

- [ ] Verify application started successfully:
  ```bash
  docker compose logs -f web
  # OR
  sudo systemctl status brokik-web
  ```

- [ ] Check for errors in logs
- [ ] Exit logs (Ctrl+C)

## Testing

### 1. CDN Health Check

- [ ] From local machine or server, test health endpoint:
  ```bash
  curl https://cdn.webet.pl/health
  ```

- [ ] Expected output: `CDN OK`

### 2. Nginx Access Test

- [ ] SSH to server: `ssh hetzner-andrzej`

- [ ] Get a blob key from database:
  ```bash
  cd ~/apps/brokik-api
  docker compose exec web rails console
  ```

- [ ] In Rails console, get a blob key:
  ```ruby
  blob = ActiveStorage::Blob.first
  puts blob.key if blob
  exit
  ```

- [ ] Copy the blob key output

- [ ] Test CDN URL with the blob key:
  ```bash
  curl -I https://cdn.webet.pl/brokik-api/blobs/PASTE_KEY_HERE
  ```

- [ ] Expected: HTTP 200 OK

### 3. Headers Verification

- [ ] Test headers (replace KEY with actual blob key):
  ```bash
  curl -I https://cdn.webet.pl/brokik-api/blobs/KEY
  ```

- [ ] Verify these headers are present:
  - [ ] `HTTP/2 200`
  - [ ] `cache-control: public, immutable`
  - [ ] `expires: <future date>`
  - [ ] `access-control-allow-origin: *`
  - [ ] `x-content-type-options: nosniff`
  - [ ] `content-type: <appropriate mime type>`

### 4. Application URL Test

- [ ] SSH to server: `ssh hetzner-andrzej`

- [ ] Check what URLs Active Storage generates:
  ```bash
  cd ~/apps/brokik-api
  docker compose exec web rails console
  ```

- [ ] In Rails console:
  ```ruby
  attachment = ActiveStorage::Attachment.first
  puts attachment.blob.url if attachment
  exit
  ```

- [ ] Expected URL format: `https://cdn.webet.pl/brokik-api/blobs/{key}`
- [ ] If URL starts with `/rails/active_storage/`, CDN is not configured correctly

### 5. Browser Test

- [ ] Open brokik-web application in browser
- [ ] Navigate to a page with images
- [ ] Open browser Developer Tools (F12)
- [ ] Go to Network tab
- [ ] Filter by images
- [ ] Check image URLs:
  - [ ] Should be: `https://cdn.webet.pl/brokik-api/blobs/{key}`
  - [ ] Should NOT be: `https://api-public.brokik.com/rails/active_storage/...`

- [ ] Verify images load correctly
- [ ] Check response headers in Network tab:
  - [ ] Status: 200 OK
  - [ ] Cache-Control: public, immutable
  - [ ] Expires: <1 year from now>

### 6. Upload Test

- [ ] In brokik-web, upload a new image
- [ ] Verify the upload succeeds
- [ ] Check the image URL in browser DevTools
- [ ] Should be CDN URL: `https://cdn.webet.pl/brokik-api/blobs/{key}`
- [ ] Verify new file exists on server:
  ```bash
  ssh hetzner-andrzej
  ls -lh /var/storage/brokik-api/active_storage/ | tail -5
  ```

### 7. Performance Test

- [ ] Measure CDN response time:
  ```bash
  curl -w "Time: %{time_total}s\n" -o /dev/null -s https://cdn.webet.pl/brokik-api/blobs/KEY
  ```

- [ ] Expected: < 0.1s (100ms) for files already in cache
- [ ] Compare with old Rails route (if still accessible)

## Log Monitoring

- [ ] Monitor CDN access logs:
  ```bash
  ssh hetzner-andrzej
  sudo tail -f /var/log/nginx/cdn-access.log
  ```

- [ ] Monitor CDN error logs (in separate terminal):
  ```bash
  ssh hetzner-andrzej
  sudo tail -f /var/log/nginx/cdn-error.log
  ```

- [ ] Check for any errors or unusual patterns
- [ ] Exit logs when satisfied (Ctrl+C)

## Post-Deployment Verification

- [ ] All tests pass
- [ ] No errors in nginx logs
- [ ] No errors in application logs
- [ ] Images load correctly in browser
- [ ] CDN URLs are generated (not Rails routes)
- [ ] Response times are fast (< 100ms)
- [ ] Cache headers are correct
- [ ] CORS headers allow cross-origin requests

## Documentation Update

- [ ] Update team documentation with CDN information
- [ ] Share CDN URL pattern with team
- [ ] Document any environment-specific configurations

## Monitoring Setup (Optional but Recommended)

- [ ] Set up monitoring for CDN uptime
- [ ] Configure alerts for CDN errors
- [ ] Add CDN metrics to monitoring dashboard
- [ ] Set up log aggregation for CDN logs

## Rollback Plan (If Issues Occur)

If you encounter issues, you can quickly rollback:

- [ ] SSH to server: `ssh hetzner-andrzej`

- [ ] Edit environment file:
  ```bash
  nano ~/apps/brokik-api/.env
  ```

- [ ] Comment out or remove CDN_HOST:
  ```bash
  # CDN_HOST=https://cdn.webet.pl
  ```

- [ ] Save and exit

- [ ] Restart brokik-api:
  ```bash
  cd ~/apps/brokik-api
  docker compose restart web
  ```

- [ ] Application will fall back to Rails routes automatically

- [ ] To fully remove CDN (optional):
  ```bash
  sudo rm /etc/nginx/sites-enabled/cdn.conf
  sudo systemctl reload nginx
  ```

## Success Criteria

Deployment is successful when:

- [x] Health check responds: `curl https://cdn.webet.pl/health` returns "CDN OK"
- [x] Files are served with correct headers (cache, CORS, etc.)
- [x] Active Storage generates CDN URLs (not Rails routes)
- [x] Images load in browser from cdn.webet.pl domain
- [x] Browser DevTools shows CDN URLs in Network tab
- [x] Cache headers show 1 year expiry
- [x] CORS headers allow cross-origin requests
- [x] Response times are fast (< 100ms for cached files)
- [x] No errors in nginx access/error logs
- [x] No errors in Rails application logs
- [x] New file uploads work and use CDN URLs

## Next Steps After Deployment

- [ ] Monitor logs for 24-48 hours
- [ ] Check server load and performance metrics
- [ ] Verify storage usage is as expected
- [ ] Consider adding global CDN (Cloudflare) in front
- [ ] Set up automated backups for /var/storage
- [ ] Document any issues or improvements needed

## Support

If you encounter issues:

1. Check logs: `/var/log/nginx/cdn-error.log`
2. Verify environment variables are set
3. Test with curl commands from troubleshooting guide
4. Review `/Users/andrzej/Development/Brokik/DevOps/docs/cdn-setup.md`
5. Check `/Users/andrzej/Development/Brokik/DevOps/docs/cdn-quick-reference.md`

## Additional Resources

- Full documentation: `docs/cdn-setup.md`
- Quick reference: `docs/cdn-quick-reference.md`
- Implementation summary: `docs/cdn-summary.md`
- Nginx config: `common/nginx/cdn.conf`
- Deployment script: `scripts/deploy-cdn.sh`
