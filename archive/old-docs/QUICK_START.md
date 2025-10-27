# Quick Start Guide

Get up and running in 5 minutes.

---

## New Application Setup

### Next.js App

```bash
# 1. Copy template
cd ~/DevOps/apps
cp -r ../templates/nextjs-app my-app
cd my-app

# 2. Configure
nano config.sh
# Update: APP_NAME, DOMAIN, REPO_URL, BASE_PORT

# 3. Setup
chmod +x setup.sh deploy.sh
bash setup.sh

# 4. Configure environment
nano ~/apps/my-app/.env.production
# Update API URLs and keys

# 5. Deploy
./deploy.sh deploy
```

**Done!** Your Next.js app is live at https://your-domain.com

---

### Rails App

```bash
# 1. Copy template
cd ~/DevOps/apps
cp -r ../templates/rails-app my-api
cd my-api

# 2. Configure
nano config.sh
# Update: APP_NAME, DOMAIN, REPO_URL, BASE_PORT, REDIS_DB_NUMBER

# 3. Setup
chmod +x setup.sh deploy.sh
bash setup.sh

# 4. Configure environment
nano ~/apps/my-api/.env.production
# Update Mailgun credentials and API keys

# 5. Deploy
./deploy.sh deploy
```

**Done!** Your Rails API is live at https://your-domain.com/up

---

## Common Commands

### Deployment
```bash
./deploy.sh deploy          # Deploy latest code
./deploy.sh restart         # Restart containers
./deploy.sh stop            # Stop all containers
```

### Scaling
```bash
./deploy.sh scale 5         # Scale to 5 containers
./deploy.sh status          # Check status
```

### Logs
```bash
./deploy.sh logs            # View logs
./deploy.sh logs web_2      # Specific container
```

### Rails Operations
```bash
./deploy.sh console         # Rails console
~/DevOps/scripts/rails-task.sh my-app db:seed  # Run task
```

### SSL
```bash
./deploy.sh ssl-setup       # Setup SSL certificate
```

---

## Disaster Recovery

```bash
# 1. Create config
cd ~/DevOps/scripts
cp disaster-recovery-config.example.sh disaster-recovery-config.sh
nano disaster-recovery-config.sh

# 2. Run recovery
./disaster-recovery.sh
```

---

## Port Allocation

Choose a free port range for `BASE_PORT` in config.sh:

- 3010-3012: cheaperfordrug-landing
- 3020-3022: cheaperfordrug-api
- 3030-3032: cheaperfordrug-web
- **3040-3049: Available**
- **3050-3059: Available**

---

## Troubleshooting

### Container won't start
```bash
docker logs my-app_web_1
cat ~/apps/my-app/.env.production
```

### DNS not configured
```bash
dig +short your-domain.com
# Should match: curl -4 ifconfig.me
```

### SSL fails
```bash
sudo certbot certificates
sudo certbot --nginx -d your-domain.com
```

### Database issues (Rails)
```bash
sudo systemctl status postgresql
sudo -u postgres psql -l | grep my_app
```

---

## Architecture

### Per-App Files (Only 4!)
```
apps/my-app/
├── config.sh           # 30 lines - configuration
├── setup.sh            # 15 lines - thin wrapper
├── deploy.sh           # 20 lines - thin wrapper
└── nginx.conf.template # Nginx config
```

### Where Logic Lives
- `common/app-types/nextjs.sh` - Next.js logic
- `common/app-types/rails.sh` - Rails logic
- `common/setup-app.sh` - Setup orchestrator
- `common/deploy-app.sh` - Deploy orchestrator
- `common/utils.sh` - Utilities
- `common/docker-utils.sh` - Docker ops

---

## Next Steps After Setup

### 1. Verify Deployment
```bash
curl https://your-domain.com
./deploy.sh status
./deploy.sh logs
```

### 2. Configure Monitoring
```bash
# View logs
tail -f ~/apps/my-app/logs/deployments.log

# Check resources
docker stats
```

### 3. Test Operations
```bash
# Scale up
./deploy.sh scale 3

# Deploy update
./deploy.sh deploy

# Check status
./deploy.sh status
```

---

## Need Help?

- **README.md** - Comprehensive guide
- **MIGRATION_GUIDE.md** - Migration instructions
- **templates/*/README.md** - App-specific guides
- **TROUBLESHOOTING** section in README.md

---

## Quick Reference

| Task | Command |
|------|---------|
| Deploy | `./deploy.sh deploy` |
| Scale | `./deploy.sh scale 5` |
| Status | `./deploy.sh status` |
| Logs | `./deploy.sh logs` |
| Restart | `./deploy.sh restart` |
| Stop | `./deploy.sh stop` |
| Console (Rails) | `./deploy.sh console` |
| SSL Setup | `./deploy.sh ssl-setup` |

---

**Version**: 3.0
**Updated**: January 27, 2025
