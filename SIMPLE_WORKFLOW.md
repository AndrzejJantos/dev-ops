# Simple Workflow - Setup & Deploy

## 🚀 Initial Setup (One Time)

### 1. Run Setup Script

```bash
# On fresh server
git clone https://github.com/YOUR_USERNAME/DevOps.git /home/andrzej/DevOps
cd /home/andrzej/DevOps
sudo bash setup-server.sh
```

**This does everything:**
- ✅ Installs Docker, PostgreSQL, Redis, Nginx, Ruby, Node.js
- ✅ Clones your app repository
- ✅ Creates database
- ✅ Installs gems natively
- ✅ Builds Docker images
- ✅ Starts 2 containers per app
- ✅ Configures Nginx
- ✅ Sets up SSL/HTTPS with certbot
- ✅ Runs migrations

**Time:** 20-30 minutes (automated)

### 2. Update Environment Variables (If Needed)

```bash
nano ~/apps/cheaperfordrug-landing/.env.production
```

Change API keys, credentials, etc.

### 3. Restart Containers

```bash
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh restart
```

**Done!** Your app is live at `https://presale.taniejpolek.pl` 🎉

---

## 🔄 Daily Workflow

### Deploy Code Updates

When you push changes to GitHub:

```bash
ssh -p 2222 andrzej@your-server
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy
```

**This automatically:**
- Pulls latest code
- Builds new Docker image
- Runs migrations (with backup)
- Zero-downtime restart
- Sends email notification

**Time:** 3-5 minutes

### Update Environment Variables

```bash
# 1. Edit environment file
nano ~/apps/cheaperfordrug-landing/.env.production

# 2. Restart containers to apply
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh restart
```

**Time:** 1 minute

### Access Rails Console

```bash
# Direct access
cd ~/apps/cheaperfordrug-landing/repo
RAILS_ENV=production bundle exec rails console

# Or use helper
cd ~/DevOps
./scripts/console.sh cheaperfordrug-landing
```

### Run Migrations

```bash
# Migrations run automatically during deploy
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy

# Or run manually
cd ~/apps/cheaperfordrug-landing/repo
RAILS_ENV=production bundle exec rails db:migrate
```

### Scale Application

```bash
cd ~/DevOps/apps/cheaperfordrug-landing

# Scale up to 4 instances
./deploy.sh scale 4

# Scale down to 2 instances
./deploy.sh scale 2
```

---

## 📁 File Locations

### Application Code (Native Rails)
```
/home/andrzej/apps/cheaperfordrug-landing/repo/
├── app/                    # Rails app
├── vendor/bundle/          # Installed gems
├── log/production.log      # Rails logs
└── .env.production         # Symlink
```

**Use this for:**
- Rails console: `cd repo && bundle exec rails console`
- Running tasks: `cd repo && bundle exec rails db:migrate`
- Debugging: `tail -f repo/log/production.log`

### Environment Variables
```
/home/andrzej/apps/cheaperfordrug-landing/.env.production
```

**Shared by:**
- ✅ Native Rails (via symlink)
- ✅ Docker containers

### Deployment Scripts
```
/home/andrzej/DevOps/apps/cheaperfordrug-landing/
├── config.sh       # Configuration
├── setup.sh        # Initial setup
└── deploy.sh       # Deployment
```

---

## 🎯 Common Commands

```bash
# Deploy
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy          # Deploy with migrations
./deploy.sh restart         # Restart current version
./deploy.sh scale 4         # Scale to 4 instances
./deploy.sh stop            # Stop all containers

# Rails console
cd ~/apps/cheaperfordrug-landing/repo
RAILS_ENV=production bundle exec rails console

# Run migrations
RAILS_ENV=production bundle exec rails db:migrate

# View logs
docker logs cheaperfordrug-landing_web_1 -f
tail -f ~/apps/cheaperfordrug-landing/repo/log/production.log

# Check status
docker ps | grep cheaperfordrug-landing
sudo systemctl status nginx postgresql redis-server
```

---

## ✨ The Setup Script Includes SSL!

The `setup-server.sh` now:
1. ✅ Installs certbot automatically
2. ✅ Prompts to setup SSL if DNS is ready
3. ✅ Obtains certificates from Let's Encrypt
4. ✅ Configures Nginx for HTTPS
5. ✅ Sets up auto-renewal

**Interactive prompts:**
```
Do you want to setup SSL certificates now? [y/N]: y
Is DNS configured and propagated? [y/N]: y
```

**Result:**
- ✅ HTTPS enabled
- ✅ HTTP → HTTPS redirect
- ✅ Auto-renewal configured

**Manual SSL setup (if needed):**
```bash
sudo certbot --nginx -d presale.taniejpolek.pl
```

---

## 🔄 Simple Update Workflow

### Scenario: You changed code and pushed to GitHub

```bash
# 1. SSH to server
ssh -p 2222 andrzej@your-server

# 2. Deploy
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy

# 3. Done!
```

**What happens automatically:**
- ✅ Pulls latest code
- ✅ Builds new Docker image
- ✅ Checks for migrations
- ✅ Creates database backup (if migrations)
- ✅ Runs migrations
- ✅ Starts new containers
- ✅ Waits for health checks
- ✅ Stops old containers
- ✅ Zero downtime!
- ✅ Email notification sent

---

## 🔧 Workflow: Update Environment Variables

### Scenario: You need to change Stripe API keys

```bash
# 1. SSH to server
ssh -p 2222 andrzej@your-server

# 2. Edit environment file
nano ~/apps/cheaperfordrug-landing/.env.production

# 3. Update the values
STRIPE_PUBLISHABLE_KEY=pk_live_NEW_KEY
STRIPE_SECRET_KEY=sk_live_NEW_KEY

# 4. Save and exit (Ctrl+X, Y, Enter)

# 5. Restart containers
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh restart

# 6. Done! New env vars loaded
```

**Time:** 1-2 minutes

---

## 📊 What's Running

After setup, you have:

### Docker Containers (Serving Traffic)
```
cheaperfordrug-landing_web_1 → Port 3010 → Nginx → HTTPS
cheaperfordrug-landing_web_2 → Port 3011 → Nginx → HTTPS
```

### Native Rails (Console & Tasks)
```
/home/andrzej/apps/cheaperfordrug-landing/repo/
- Full Rails app
- Gems installed
- Direct console access
```

### Services
```
✅ Nginx (reverse proxy + load balancer)
✅ PostgreSQL (database)
✅ Redis (cache)
✅ Docker (container runtime)
✅ Certbot (SSL certificates)
```

---

## 🎯 Summary

**Initial setup:**
```bash
sudo bash setup-server.sh  # One command, everything done!
```

**Update environment:**
```bash
nano ~/apps/<app>/.env.production
./deploy.sh restart
```

**Deploy code:**
```bash
./deploy.sh deploy
```

**Rails console:**
```bash
cd ~/apps/<app>/repo
bundle exec rails console
```

**That's it!** Simple, automated, production-ready. 🚀

---

**Questions?** See:
- [ONE_COMMAND_SETUP.md](ONE_COMMAND_SETUP.md) - Detailed setup guide
- [SERVER_SETUP_GUIDE.md](SERVER_SETUP_GUIDE.md) - Manual setup
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Command reference
