# Quick Reference Card

## 🚀 First Time Server Setup

```bash
# 1. Connect to server
ssh root@your-server-ip

# 2. Clone DevOps
cd /home/andrzej
git clone https://github.com/YOUR_USERNAME/DevOps.git DevOps

# 3. Initialize server
cd DevOps
sudo ./ubuntu-init-setup.sh

# 4. Reconnect (SSH port changed to 2222)
ssh -p 2222 andrzej@your-server-ip

# 5. Setup application
cd ~/DevOps/apps/cheaperfordrug-landing
./setup.sh

# 6. Configure environment
nano ~/apps/cheaperfordrug-landing/.env.production

# 7. Deploy
./deploy.sh deploy

# 8. Configure DNS
# Point presale.taniejpolek.pl to server IP

# 9. Enable SSL
sudo certbot --nginx -d presale.taniejpolek.pl
```

**Time:** ~30-45 minutes

---

## 📦 Daily Operations

### Deploy Updates
```bash
ssh -p 2222 andrzej@your-server-ip
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy
```

### Scale Application
```bash
./deploy.sh scale 4      # Scale to 4 instances
./deploy.sh scale 2      # Scale to 2 instances
```

### Restart
```bash
./deploy.sh restart
```

### Stop
```bash
./deploy.sh stop
```

---

## 🖥️ Rails Console & Tasks

### Console
```bash
cd ~/DevOps
./scripts/console.sh cheaperfordrug-landing
```

### Run Migrations
```bash
./scripts/rails-task.sh cheaperfordrug-landing db:migrate
```

### Other Tasks
```bash
./scripts/rails-task.sh cheaperfordrug-landing routes
./scripts/rails-task.sh cheaperfordrug-landing db:seed
./scripts/rails-task.sh cheaperfordrug-landing runner 'puts User.count'
```

---

## 📊 Monitoring

### Check Status
```bash
# Containers
docker ps | grep cheaperfordrug-landing

# Services
sudo systemctl status nginx
sudo systemctl status postgresql
sudo systemctl status redis-server
```

### View Logs
```bash
# Docker logs
docker logs cheaperfordrug-landing_web_1 -f

# Rails logs
tail -f ~/apps/cheaperfordrug-landing/repo/log/production.log

# Nginx logs
sudo tail -f /var/log/nginx/cheaperfordrug-landing-access.log
sudo tail -f /var/log/nginx/cheaperfordrug-landing-error.log

# Deployment history
tail -f ~/apps/cheaperfordrug-landing/logs/deployments.log
```

---

## 🛠️ Troubleshooting

### Containers won't start
```bash
docker logs cheaperfordrug-landing_web_1
cat ~/apps/cheaperfordrug-landing/.env.production
```

### Can't access website
```bash
sudo nginx -t
sudo systemctl reload nginx
docker ps
curl http://localhost:3010/up
```

### Database issues
```bash
sudo systemctl status postgresql
sudo -u postgres psql -l
```

### Fix permissions
```bash
sudo chown -R andrzej:andrzej ~/apps/cheaperfordrug-landing
```

---

## 📁 Important Paths

| Path | Purpose |
|------|---------|
| `~/DevOps/apps/cheaperfordrug-landing/` | App scripts & config |
| `~/apps/cheaperfordrug-landing/repo/` | Application code |
| `~/apps/cheaperfordrug-landing/.env.production` | Environment variables |
| `~/apps/cheaperfordrug-landing/backups/` | Database backups |
| `/etc/nginx/sites-enabled/cheaperfordrug-landing` | Nginx config |

---

## 🆕 Adding New App

### Rails App
```bash
cd ~/DevOps/apps
mkdir my-rails-app
cp cheaperfordrug-landing/* my-rails-app/
cd my-rails-app
nano config.sh  # Edit: APP_NAME, REPO_URL, DOMAIN, BASE_PORT, REDIS_DB_NUMBER
./setup.sh
./deploy.sh deploy
```

### Node.js App
```bash
cd ~/DevOps/apps
cp -r _examples/nodejs-app-template my-nodejs-app
cd my-nodejs-app
nano config.sh  # Edit configuration
./setup.sh
./deploy.sh deploy
```

---

## 🔐 Security

### Check Firewall
```bash
sudo ufw status
```

### SSL Certificate Renewal
```bash
sudo certbot renew --dry-run
```

### File Permissions
```bash
chmod 600 ~/apps/cheaperfordrug-landing/.env.production
```

---

## 📧 Email Notifications

Sent to: `andrzej@webet.pl`

Events:
- ✅ Setup completion
- ✅ Deployment success/failure
- ✅ Scaling changes
- ✅ Application stops

---

## 🎯 Port Allocation

| App | Ports | Redis DB |
|-----|-------|----------|
| cheaperfordrug-landing | 3010-3019 | 1 |
| Next app | 3020-3029 | 2 |
| Next app | 3030-3039 | 3 |

---

## 📚 Documentation

| File | Purpose |
|------|---------|
| `SERVER_SETUP_GUIDE.md` | Complete setup guide |
| `QUICKSTART.md` | Architecture quick start |
| `ARCHITECTURE.md` | Full architecture docs |
| `CONSOLE_ACCESS.md` | Rails console guide |
| `DEPLOYMENT_SUMMARY.md` | System summary |

---

## 🆘 Emergency Commands

### Rollback (if deployment fails)
```bash
# Old containers still running if deployment fails
docker ps -a | grep cheaperfordrug-landing

# Remove failed new containers
docker rm -f cheaperfordrug-landing_web_new_1
docker rm -f cheaperfordrug-landing_web_new_2
```

### Restore Database Backup
```bash
cd ~/apps/cheaperfordrug-landing/backups
gunzip backup_file.sql.gz
sudo -u postgres psql cheaperfordrug_landing_production < backup_file.sql
```

### Force Restart All
```bash
docker stop $(docker ps -q --filter "name=cheaperfordrug-landing")
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy
```

---

**Contact:** andrzej@webet.pl
**SSH:** `ssh -p 2222 andrzej@your-server-ip`
**Domain:** https://presale.taniejpolek.pl
