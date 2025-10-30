# Nginx Rebuild Pre-Flight Checklist

Quick reference checklist to run before executing `rebuild-nginx-configs.sh`

## ✅ Pre-Flight Checks

### 1. Verify Containers Are Running

```bash
docker ps | grep cheaperfordrug
```

**Expected:** At least 7 containers running:
- [ ] cheaperfordrug-landing (2 containers)
- [ ] cheaperfordrug-web (3 containers)
- [ ] cheaperfordrug-api (2 containers)

---

### 2. Check Port Availability

```bash
sudo netstat -tlnp | grep -E ':(3010|3011|3020|3021|3030|3031|3032)'
```

**Expected ports listening:**
- [ ] 3010 (landing-1)
- [ ] 3011 (landing-2)
- [ ] 3020 (api-1)
- [ ] 3021 (api-2)
- [ ] 3030 (web-1)
- [ ] 3031 (web-2)
- [ ] 3032 (web-3)

---

### 3. Verify SSL Certificates

```bash
sudo certbot certificates
```

**Expected certificates:**
- [ ] taniejpolek.pl (covers www.taniejpolek.pl, presale.taniejpolek.pl)
- [ ] premiera.taniejpolek.pl
- [ ] api-public.cheaperfordrug.com
- [ ] api-internal.cheaperfordrug.com

**Check expiration:**
```bash
# Should show >30 days remaining
sudo certbot certificates | grep -A5 "VALID"
```

---

### 4. Test Container Health Endpoints

```bash
# Landing
curl -I http://localhost:3010/up
curl -I http://localhost:3011/up

# API
curl -I http://localhost:3020/up
curl -I http://localhost:3021/up

# Web (root endpoint)
curl -I http://localhost:3030/
curl -I http://localhost:3031/
curl -I http://localhost:3032/
```

**Expected:** All should return `200 OK`

- [ ] All landing containers respond with 200
- [ ] All api containers respond with 200
- [ ] All web containers respond with 200

---

### 5. Verify DNS Configuration

```bash
# Get server IP
curl -4 ifconfig.me

# Check DNS for each domain
dig +short taniejpolek.pl A
dig +short www.taniejpolek.pl A
dig +short presale.taniejpolek.pl A
dig +short premiera.taniejpolek.pl A
dig +short api-public.cheaperfordrug.com A
dig +short api-internal.cheaperfordrug.com A
```

**Verification:**
- [ ] All domains resolve to correct server IP
- [ ] No domains missing from DNS

---

### 6. Check Current Nginx Status

```bash
# Nginx should be running
sudo systemctl status nginx

# Current config should be valid
sudo nginx -t
```

**Expected:**
- [ ] Nginx is active (running)
- [ ] Current configuration syntax is ok
- [ ] Test is successful

---

### 7. Verify DevOps Directory Structure

```bash
cd ~/DevOps
ls -la apps/cheaperfordrug-*/config.sh
ls -la apps/cheaperfordrug-*/nginx.conf.template
```

**Expected files:**
- [ ] apps/cheaperfordrug-landing/config.sh
- [ ] apps/cheaperfordrug-landing/nginx.conf.template
- [ ] apps/cheaperfordrug-web/config.sh
- [ ] apps/cheaperfordrug-web/nginx.conf.template
- [ ] apps/cheaperfordrug-api/config.sh
- [ ] apps/cheaperfordrug-api/nginx.conf.template

---

### 8. Check Disk Space

```bash
df -h /
df -h /tmp
```

**Required:**
- [ ] At least 1GB free on `/` (for backups and configs)
- [ ] At least 500MB free on `/tmp` (for temporary backups)

---

### 9. Verify Backup Location Writable

```bash
# Test writing to /tmp
touch /tmp/test_write && rm /tmp/test_write && echo "OK" || echo "FAIL"
```

**Expected:**
- [ ] Can write to /tmp directory

---

### 10. Check for Conflicting Processes

```bash
# Check if anyone else is editing nginx configs
sudo lsof | grep /etc/nginx/
```

**Expected:**
- [ ] No unexpected processes have nginx config files open

---

## 🚀 Ready to Run

Once all checks pass:

### Step 1: Dry Run (Always Do This First!)

```bash
cd ~/DevOps
chmod +x rebuild-nginx-configs.sh
./rebuild-nginx-configs.sh --dry-run
```

### Step 2: Review Dry Run Output

Look for:
- [ ] No errors in pre-flight checks
- [ ] All 3 applications discovered
- [ ] SSL certificates validated
- [ ] Container ports all active

### Step 3: Execute Rebuild

```bash
./rebuild-nginx-configs.sh
```

### Step 4: Monitor

```bash
# In one terminal, watch error log
sudo tail -f /var/log/nginx/error.log

# In another terminal, watch access log
sudo tail -f /var/log/nginx/access.log
```

---

## ⚠️ If Any Check Fails

### Containers Not Running?

```bash
# Start missing containers
cd ~/apps/cheaperfordrug-landing
docker-compose up -d

cd ~/apps/cheaperfordrug-web
docker-compose up -d

cd ~/apps/cheaperfordrug-api
docker-compose up -d
```

### SSL Certificates Missing?

```bash
# Create missing certificates
sudo certbot --nginx -d taniejpolek.pl -d www.taniejpolek.pl -d presale.taniejpolek.pl
sudo certbot --nginx -d premiera.taniejpolek.pl
sudo certbot --nginx -d api-public.cheaperfordrug.com -d api-internal.cheaperfordrug.com
```

### DNS Not Configured?

1. Update DNS records at your DNS provider
2. Wait for propagation (up to 48 hours, usually 5-15 minutes)
3. Check again with `dig +short domain.com A`

### Nginx Not Running?

```bash
# Start nginx
sudo systemctl start nginx

# If it fails to start, check logs
sudo journalctl -u nginx -n 50
```

---

## 🆘 Emergency Contacts

If something goes wrong during rebuild:

1. **The script will auto-restore from backup** if nginx test fails
2. **Backup location:** `/tmp/nginx_backup_YYYYMMDD_HHMMSS/`
3. **Manual restore:**
   ```bash
   BACKUP_DIR="/tmp/nginx_backup_20251030_143052"  # Use latest
   sudo cp -r $BACKUP_DIR/sites-available/* /etc/nginx/sites-available/
   sudo ln -sf /etc/nginx/sites-available/cheaperfordrug-* /etc/nginx/sites-enabled/
   sudo nginx -t && sudo systemctl reload nginx
   ```

---

## 📋 Quick Command Reference

```bash
# Full pre-flight check in one go
cd ~/DevOps && \
docker ps | grep cheaperfordrug && \
sudo netstat -tlnp | grep -E ':(3010|3011|3020|3021|3030|3031|3032)' && \
sudo certbot certificates && \
sudo nginx -t && \
echo "✅ All checks passed!"

# Dry run
./rebuild-nginx-configs.sh --dry-run

# Execute rebuild
./rebuild-nginx-configs.sh

# Monitor logs after rebuild
sudo tail -f /var/log/nginx/error.log
```

---

## ✨ Post-Rebuild Verification

After successful rebuild:

```bash
# Test each domain
curl -I https://www.taniejpolek.pl
curl -I https://presale.taniejpolek.pl
curl -I https://premiera.taniejpolek.pl
curl -I https://api-public.cheaperfordrug.com/up
curl -I https://api-internal.cheaperfordrug.com/up

# All should return 200 or appropriate redirects
```

**Final checks:**
- [ ] All domains return 200 OK
- [ ] HTTPS working (no certificate errors)
- [ ] No errors in nginx logs
- [ ] Containers still running healthy

---

## 📊 Checklist Summary

```
Pre-Flight Checks:
✅ Containers running (7 total)
✅ Ports listening (7 ports)
✅ SSL certificates valid (4 certificates)
✅ Container health endpoints responding
✅ DNS configured correctly
✅ Nginx running and config valid
✅ DevOps directory structure correct
✅ Sufficient disk space
✅ /tmp writable
✅ No conflicting processes

Ready to proceed: YES ✅
```

---

## 📚 Additional Resources

- **Full Documentation:** [NGINX_REBUILD_GUIDE.md](NGINX_REBUILD_GUIDE.md)
- **Script Location:** `~/DevOps/rebuild-nginx-configs.sh`
- **Backup Location:** `/tmp/nginx_backup_*/`
- **Nginx Configs:** `/etc/nginx/sites-available/`
- **Nginx Logs:** `/var/log/nginx/`
