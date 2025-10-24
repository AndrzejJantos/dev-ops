# DevOps - Multi-App Deployment System

Production-ready deployment system for Rails and Node.js applications with Docker, zero-downtime deployments, and native Rails console access.

## 🚀 Quick Start

### Step 1: Initialize Server (One-Time)

```bash
# On fresh server
git clone https://github.com/YOUR_USERNAME/DevOps.git /home/andrzej/DevOps
cd /home/andrzej/DevOps
sudo ./ubuntu-init-setup.sh
```

Installs: Docker, PostgreSQL, Redis, Nginx, Ruby, Node.js
**Time:** 10-15 minutes

### Step 2: Setup Application

```bash
# As deploy user
cd ~/DevOps/apps/cheaperfordrug-landing
./setup.sh
```

Creates database, installs gems, builds Docker image, configures Nginx
**Time:** 5-10 minutes

### Step 3: Configure Environment

```bash
nano ~/apps/cheaperfordrug-landing/.env.production
```

Update API keys, credentials, etc.

### Step 4: Deploy

```bash
./deploy.sh deploy
```

Starts 2 containers, configures load balancer
**Time:** 3-5 minutes

### Step 5: Setup SSL (When DNS Ready)

```bash
cd ~/DevOps
sudo ./scripts/setup-ssl.sh cheaperfordrug-landing
```

Obtains Let's Encrypt certificate, configures HTTPS
**Time:** 1-2 minutes

### Daily Operations
```bash
# Deploy updates
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy

# Scale application
./deploy.sh scale 4

# Restart
./deploy.sh restart

# Rails console
cd ~/DevOps
./scripts/console.sh cheaperfordrug-landing

# Run migrations
./scripts/rails-task.sh cheaperfordrug-landing db:migrate
```

## 📁 Directory Structure

```
DevOps/
├── ubuntu-init-setup.sh         # Server initialization
│
├── common/                      # Shared utilities
│   ├── utils.sh                # Logging, DB, notifications
│   ├── docker-utils.sh         # Docker operations
│   ├── rails/                  # Rails framework modules
│   └── nodejs/                 # Node.js framework modules
│
├── apps/                        # Applications
│   ├── cheaperfordrug-landing/ # Rails app example
│   │   ├── config.sh
│   │   ├── setup.sh           # Executable
│   │   ├── deploy.sh          # Executable
│   │   └── nginx.conf.template
│   └── _examples/
│       └── nodejs-app-template/
│
└── scripts/                     # Helper scripts
    ├── console.sh              # Rails console access
    └── rails-task.sh           # Rails task runner
```

## 📚 Documentation

| File | Purpose | When to Read |
|------|---------|-------------|
| **[SERVER_SETUP_GUIDE.md](SERVER_SETUP_GUIDE.md)** | Complete setup guide | First time deployment |
| **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** | Command cheat sheet | Daily operations |
| **[QUICKSTART.md](QUICKSTART.md)** | Architecture overview | Understanding system |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | Detailed architecture | Deep dive |
| **[CONSOLE_ACCESS.md](CONSOLE_ACCESS.md)** | Rails console guide | Using Rails console |

## ✨ Features

- ✅ **Zero-downtime deployments** - Rolling restarts with health checks
- ✅ **Native Rails console** - Direct `bundle exec rails c` access
- ✅ **Framework modules** - Dedicated Rails & Node.js support
- ✅ **App-specific scripts** - Each app has own setup.sh & deploy.sh
- ✅ **Easy customization** - Override any function per app
- ✅ **Database migrations** - Automatic with backups
- ✅ **Email notifications** - Deployment status via Mailgun
- ✅ **Load balancing** - Nginx with health checks
- ✅ **Auto-scaling** - 1-10 instances per app

## 🎯 Adding New Application

### Rails App
```bash
cd ~/DevOps/apps
mkdir my-rails-app
cp cheaperfordrug-landing/* my-rails-app/
cd my-rails-app
nano config.sh  # Edit configuration
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

## 🔧 Key Configuration

Edit app config: `apps/<app-name>/config.sh`

```bash
export APP_NAME="my-app"
export REPO_URL="https://github.com/user/my-app.git"
export DOMAIN="myapp.example.com"
export BASE_PORT=3020        # Unique port range
export REDIS_DB_NUMBER=2     # Unique Redis DB
export DEFAULT_SCALE=2       # Default instances
```

## 📊 Monitoring

```bash
# Check containers
docker ps | grep cheaperfordrug-landing

# View logs
docker logs cheaperfordrug-landing_web_1 -f
tail -f ~/apps/cheaperfordrug-landing/repo/log/production.log

# Check services
sudo systemctl status nginx postgresql redis-server
```

## 🆘 Troubleshooting

See **[SERVER_SETUP_GUIDE.md](SERVER_SETUP_GUIDE.md)** - Troubleshooting section

Quick fixes:
```bash
# Restart containers
./apps/<app-name>/deploy.sh restart

# Check logs
docker logs <app-name>_web_1

# Fix permissions
sudo chown -R andrzej:andrzej ~/apps/<app-name>

# Reload Nginx
sudo nginx -t && sudo systemctl reload nginx
```

## 🔐 Security

- SSH port: 2222
- Firewall: UFW enabled
- SSL/TLS: Via certbot
- Environment: chmod 600 .env.production
- Root login: Disabled
- Password auth: Disabled (SSH keys only)

## 📧 Contact

- **Email:** andrzej@webet.pl
- **Notifications:** Mailgun → andrzej@webet.pl
- **Domain:** presale.taniejpolek.pl

## 📦 Applications

| App | Domain | Ports | Redis DB | Status |
|-----|--------|-------|----------|--------|
| cheaperfordrug-landing | presale.taniejpolek.pl | 3010-3019 | 1 | ✅ Active |

---

**Version:** 2.0
**Last Updated:** October 2025
**Start Here:** [SERVER_SETUP_GUIDE.md](SERVER_SETUP_GUIDE.md)
