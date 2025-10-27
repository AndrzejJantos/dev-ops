# Fixing premiera.taniejpolek.pl

## The Problem

Your deployment succeeded, but the domain isn't accessible because:

1. **SSL Certificates Missing** - HTTPS can't work without certificates
2. **Domain Conflict** - Another nginx config (`webet.pl`) is also claiming `premiera.taniejpolek.pl`, causing nginx to ignore your config

## The Solution - Run the Fix Script

### On your remote server:

```bash
# Pull the latest fixes
cd ~/DevOps
git pull

# Navigate to the app directory
cd apps/cheaperfordrug-web

# Run the fix script
bash fix-domain-and-ssl.sh
```

## What the Fix Script Does

The script will:

1. ✅ **Detect domain conflicts** in all nginx configs
2. 🔧 **Automatically remove** conflicting domains (with your approval)
3. 🧪 **Test nginx configuration**
4. 🔄 **Reload nginx**
5. 🌐 **Check DNS configuration**
6. 🔐 **Setup SSL certificates** from Let's Encrypt
7. ✅ **Verify site accessibility**

## Expected Output

```
==========================================================================
  Domain Conflict Resolver & SSL Setup
  Application: CheaperForDrug Web
  Domain: premiera.taniejpolek.pl
==========================================================================

[INFO] Step 1: Checking for domain conflicts in nginx configs...
[WARNING] Found conflict in: webet.pl
...
Do you want to automatically remove premiera.taniejpolek.pl from these configs? (y/n): y
[SUCCESS] All conflicts resolved

[INFO] Step 2: Testing nginx configuration...
[SUCCESS] Nginx configuration is valid

[INFO] Step 3: Reloading nginx...
[SUCCESS] Nginx reloaded successfully

[INFO] Step 4: Checking DNS configuration...
  Server IP: xxx.xxx.xxx.xxx
  Domain IP: xxx.xxx.xxx.xxx
[SUCCESS] DNS correctly configured

[INFO] Step 5: Checking for existing SSL certificates...
[INFO] No SSL certificates found

[INFO] Step 6: Obtaining SSL certificates from Let's Encrypt...
Enter your email address for Let's Encrypt notifications: your@email.com
[SUCCESS] SSL certificates obtained and configured successfully!

[INFO] Step 7: Verifying site accessibility...
[SUCCESS] HTTPS working! (200)

==========================================================================
  Setup Complete!
==========================================================================

Site Status:
  Primary URL:  https://premiera.taniejpolek.pl
  Alternative:  https://www.premiera.taniejpolek.pl
```

## If You Have Issues

### DNS Not Configured
If DNS check fails, configure your DNS:
```
premiera.taniejpolek.pl     A    [your-server-ip]
www.premiera.taniejpolek.pl A    [your-server-ip]
```

Then run the fix script again.

### Manual SSL Setup
If automatic SSL fails:
```bash
sudo certbot --nginx -d premiera.taniejpolek.pl -d www.premiera.taniejpolek.pl
```

### Check Container Status
```bash
docker ps | grep cheaperfordrug-web
docker logs cheaperfordrug-web_web_1 -f
```

### Test Directly
```bash
# Test container
curl -I http://localhost:3030/

# Test nginx
curl -I https://premiera.taniejpolek.pl
```

## Other Diagnostic Tools

```bash
# Quick check (fast)
bash quick-check.sh

# Full diagnostics (comprehensive)
bash diagnose.sh
```

## After SSL is Working

Your site will be accessible at:
- https://premiera.taniejpolek.pl
- https://www.premiera.taniejpolek.pl

SSL certificates will auto-renew every 90 days via certbot.timer.

## Prevention for Future Apps

The `setup.sh` has been updated to:
- ✅ Check for domain conflicts before creating nginx configs
- ✅ Better DNS verification
- ✅ Improved SSL setup with error handling
- ✅ Reference to fix script if issues occur

This prevents these issues for future app deployments.
