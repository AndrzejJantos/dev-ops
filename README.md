# DevOps Infrastructure

Production-ready Docker-based deployment infrastructure for Rails and Next.js applications with automated SSL, backups, and zero-downtime deployments.

**Version 3.0** - Refactored with composition architecture for maximum DRY and scalability.

---

## Table of Contents

- [Features](#features)
- [Architecture Overview](#architecture-overview)
- [Quick Start](#quick-start)
- [Adding New Applications](#adding-new-applications)
- [Common Operations](#common-operations)
- [Disaster Recovery](#disaster-recovery)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)
- [Advanced Topics](#advanced-topics)

---

## Features

✅ **Zero-Downtime Deployments** - Rolling restarts with health checks
✅ **Automatic SSL** - Let's Encrypt certificates with auto-renewal
✅ **Database Backups** - Automated PostgreSQL backups (Rails apps)
✅ **Image Rollback** - Save Docker images for instant rollback capability
✅ **Centralized Cleanup** - Single daily cleanup for all applications
✅ **Load Balancing** - Nginx reverse proxy with least_conn algorithm
✅ **Background Jobs** - Sidekiq workers and Clockwork scheduler support (Rails)
✅ **Security** - Default catch-all server to reject unknown domains
✅ **Monitoring** - Health checks and container status tracking
✅ **DRY Architecture** - Composition-based design eliminates code duplication
✅ **Disaster Recovery** - One script to rebuild entire server from scratch

---

## Architecture Overview

### Composition-Based Design

The infrastructure uses a **composition over inheritance** pattern where:

1. **App-Type Modules** (`common/app-types/`) - Provide type-specific hooks (nextjs, rails)
2. **Generic Orchestrators** (`common/setup-app.sh`, `common/deploy-app.sh`) - Call app-type hooks
3. **Common Utilities** (`common/utils.sh`, `common/docker-utils.sh`) - Shared functions
4. **App Configurations** (`apps/*/config.sh`) - App-specific settings only

This eliminates code duplication and makes it trivial to add new apps.

### Directory Structure

```
DevOps/
├── apps/                           # Application-specific configurations
│   ├── cheaperfordrug-api/         # Rails API backend
│   ├── cheaperfordrug-web/         # Next.js frontend
│   └── cheaperfordrug-landing/     # Rails landing page
├── common/                         # Shared infrastructure
│   ├── app-types/                  # App-type modules (composition)
│   │   ├── nextjs.sh               # Next.js-specific hooks
│   │   └── rails.sh                # Rails-specific hooks
│   ├── setup-app.sh                # Generic setup orchestrator
│   ├── deploy-app.sh               # Generic deploy orchestrator
│   ├── utils.sh                    # Common utilities
│   ├── docker-utils.sh             # Docker operations
│   ├── nextjs/                     # Next.js templates
│   │   └── Dockerfile.template
│   ├── rails/                      # Rails templates
│   │   └── Dockerfile.template
│   └── nginx/                      # Nginx configurations
│       └── default-server.conf
├── scripts/                        # System-wide scripts
│   ├── disaster-recovery.sh        # Full server rebuild
│   ├── cleanup-all-apps.sh         # Centralized cleanup
│   ├── console.sh                  # Rails console helper
│   ├── rails-task.sh               # Rails task helper
│   └── setup-ssl.sh                # SSL setup helper
├── templates/                      # App templates
│   ├── nextjs-app/                 # Next.js template
│   └── rails-app/                  # Rails template
└── README.md                       # This file
```

### App Structure (Minimal)

Each app only needs 4 files:

```
apps/your-app/
├── config.sh               # App configuration (30 lines)
├── setup.sh                # Thin wrapper (15 lines)
├── deploy.sh               # Thin wrapper (20 lines)
└── nginx.conf.template     # Nginx config template
```

All logic is in `common/` - no duplication!

---

## Quick Start

### Prerequisites

Ubuntu 22.04+ server with:
- Docker
- Nginx
- PostgreSQL (for Rails apps)
- Redis (for Rails apps)
- Certbot (for SSL)

Run the init setup script if you haven't:
```bash
sudo ./ubuntu-init-setup.sh
```

### Deploy Your First Application

#### From Template (Recommended)

**For Next.js:**
```bash
cd ~/DevOps/apps
cp -r ../templates/nextjs-app my-nextjs-app
cd my-nextjs-app
nano config.sh              # Configure APP_NAME, DOMAIN, REPO_URL, etc.
chmod +x setup.sh deploy.sh
bash setup.sh               # One-time setup
./deploy.sh deploy          # Deploy!
```

**For Rails:**
```bash
cd ~/DevOps/apps
cp -r ../templates/rails-app my-rails-api
cd my-rails-api
nano config.sh              # Configure APP_NAME, DOMAIN, REPO_URL, etc.
chmod +x setup.sh deploy.sh
bash setup.sh               # One-time setup (creates DB, env file)
nano ~/apps/my-rails-api/.env.production  # Update credentials
./deploy.sh deploy          # Deploy!
```

That's it! Your application is now running with SSL enabled.

---

## Adding New Applications

### Option 1: Use Templates (Recommended)

1. **Copy Template**
   ```bash
   cd ~/DevOps/apps
   cp -r ../templates/nextjs-app my-new-app    # or rails-app
   cd my-new-app
   ```

2. **Configure `config.sh`**
   ```bash
   nano config.sh
   ```
   Update:
   - `APP_TYPE` - "nextjs" or "rails"
   - `APP_NAME` - Your app identifier
   - `APP_DISPLAY_NAME` - Human-readable name
   - `DOMAIN` - Your domain
   - `REPO_URL` - Git repository URL
   - `BASE_PORT` - Starting port (e.g., 3040)

3. **Run Setup**
   ```bash
   chmod +x setup.sh deploy.sh
   bash setup.sh
   ```

4. **Configure Environment**
   ```bash
   nano ~/apps/my-new-app/.env.production
   ```

5. **Deploy**
   ```bash
   ./deploy.sh deploy
   ```

### Option 2: Copy Existing App

```bash
cd ~/DevOps/apps
cp -r cheaperfordrug-web my-new-app
cd my-new-app
nano config.sh        # Update all configuration
bash setup.sh         # Run setup
./deploy.sh deploy    # Deploy
```

### Port Allocation

Choose a free port range for `BASE_PORT`:
- 3010-3012: cheaperfordrug-landing
- 3020-3022: cheaperfordrug-api
- 3030-3032: cheaperfordrug-web
- **3040-3049: Available**
- **3050-3059: Available**

---

## Common Operations

### Deployment

```bash
cd ~/DevOps/apps/your-app
./deploy.sh deploy              # Deploy latest code
./deploy.sh restart             # Restart with current image
./deploy.sh stop                # Stop all containers
```

### Scaling

```bash
./deploy.sh scale 5             # Scale to 5 web containers
./deploy.sh status              # Check container status
```

### Logs

```bash
./deploy.sh logs                # View web_1 logs
./deploy.sh logs web_2          # View web_2 logs
./deploy.sh logs worker_1       # View worker_1 logs (Rails)
./deploy.sh logs scheduler      # View scheduler logs (Rails)
```

### Rails Operations

```bash
# Rails console
./deploy.sh console
# Or: ~/DevOps/scripts/console.sh your-app

# Run Rails tasks
~/DevOps/scripts/rails-task.sh your-app db:seed
~/DevOps/scripts/rails-task.sh your-app db:migrate:status
```

### Database Operations (Rails)

```bash
# List backups
ls -lh ~/apps/your-app/backups/

# Restore database
~/apps/your-app/restore.sh

# Manual backup
~/apps/your-app/backup.sh
```

### SSL Management

```bash
# Setup SSL for new domain
./deploy.sh ssl-setup

# Check certificate status
sudo certbot certificates

# Manual renewal (auto-renewal is enabled)
sudo certbot renew
```

---

## Disaster Recovery

### Full Server Rebuild

The disaster recovery script rebuilds your entire infrastructure from scratch.

**1. Create Configuration**
```bash
cd ~/DevOps/scripts
cp disaster-recovery-config.example.sh disaster-recovery-config.sh
nano disaster-recovery-config.sh
```

Update:
- `RECOVERY_USER` - Your username
- `DEVOPS_REPO_URL` - This repository URL
- `APPS_TO_DEPLOY` - Array of app names

**2. Run Recovery**
```bash
./disaster-recovery.sh
```

This will:
1. Install all system dependencies (Docker, Nginx, PostgreSQL, Redis, Certbot, etc.)
2. Clone DevOps repository
3. Setup all applications (databases, nginx, etc.)
4. Prompt for environment variable configuration
5. Deploy all applications
6. Setup SSL certificates
7. Configure centralized cleanup
8. Verify deployment

**3. Restore Databases** (if recovering from backup)
```bash
cd ~/apps/your-rails-app
./restore.sh /path/to/backup.sql.gz
```

### Partial Recovery

To recover just one app:
```bash
cd ~/DevOps/apps/your-app
bash setup.sh           # Re-run setup
./deploy.sh deploy      # Deploy
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs your-app_web_1

# Check if port is in use
sudo lsof -i :3030

# Verify environment file
cat ~/apps/your-app/.env.production

# Check Docker daemon
sudo systemctl status docker
```

### SSL Certificate Issues

```bash
# Check DNS
dig +short your-domain.com

# Verify it matches server IP
curl -4 ifconfig.me

# Check certificate status
sudo certbot certificates

# Manual setup
sudo certbot --nginx -d your-domain.com -d www.your-domain.com
```

### Database Connection Errors (Rails)

```bash
# Check PostgreSQL
sudo systemctl status postgresql

# List databases
sudo -u postgres psql -l

# Test connection
sudo -u postgres psql your_database_name

# Check credentials in env file
cat ~/apps/your-app/.env.production | grep DATABASE
```

### Deployment Fails

```bash
# Check deployment logs
cat ~/apps/your-app/logs/deployments.log

# Verify Docker build
cd ~/apps/your-app/repo
docker build -t test .

# Check disk space
df -h

# Clean up old images
docker system prune -a
```

### Nginx Configuration Errors

```bash
# Test configuration
sudo nginx -t

# View error logs
sudo tail -f /var/log/nginx/error.log

# Reload configuration
sudo systemctl reload nginx

# Check app-specific logs
sudo tail -f /var/log/nginx/your-app-error.log
```

### Health Check Fails

```bash
# Check health endpoint
curl http://localhost:3030/           # Next.js
curl http://localhost:3020/up         # Rails

# Check container logs
docker logs your-app_web_1 --tail 50

# Verify environment variables
docker exec your-app_web_1 env | grep -E 'DATABASE|REDIS|SECRET'
```

---

## Maintenance

### SSL Auto-Renewal

SSL certificates renew automatically via `certbot.timer`.

**Check timer status:**
```bash
sudo systemctl status certbot.timer
```

**Test renewal:**
```bash
sudo certbot renew --dry-run
```

**Manual renewal (if needed):**
```bash
sudo certbot renew
```

### Automated Cleanup

A centralized cleanup runs daily at 2 AM for all apps.

**View cleanup logs:**
```bash
tail -f ~/DevOps/logs/cleanup-all.log
```

**Manual cleanup:**
```bash
~/DevOps/scripts/cleanup-all-apps.sh
```

**What gets cleaned:**
- Old Docker images (keeps last 20)
- Old image backups (keeps last 20)
- Old database backups (older than 30 days, Rails only)
- Old log files (older than 30 days)
- Dangling Docker images
- Stopped containers (older than 7 days)

### Database Backups (Rails)

Automatic backups run every 30 minutes (configured per app).

**Location:** `~/apps/your-app/backups/`

**Check backup cron:**
```bash
crontab -l | grep backup
```

**Manual backup:**
```bash
~/apps/your-app/backup.sh
```

**Restore:**
```bash
~/apps/your-app/restore.sh
```

### Monitoring

**System resources:**
```bash
htop                    # CPU/memory usage
df -h                   # Disk usage
docker stats            # Container resource usage
```

**Application health:**
```bash
cd ~/DevOps/apps/your-app
./deploy.sh status      # Container status
docker ps               # All containers
```

**Logs:**
```bash
# Application logs
./deploy.sh logs

# Nginx logs
sudo tail -f /var/log/nginx/your-app-access.log
sudo tail -f /var/log/nginx/your-app-error.log

# System logs
sudo journalctl -u docker -f
sudo journalctl -u nginx -f
```

---

## Advanced Topics

### Custom Docker Images

Both Next.js and Rails use templated Dockerfiles in `common/nextjs/` and `common/rails/`.

To customize:
1. Edit the template in `common/app-type/Dockerfile.template`
2. Redeploy your app: `./deploy.sh deploy`

### Custom Nginx Configuration

Each app has `nginx.conf.template` with placeholders:
- `{{NGINX_UPSTREAM_NAME}}` - Upstream name
- `{{UPSTREAM_SERVERS}}` - Server list
- `{{DOMAIN}}` - Domain name
- `{{APP_NAME}}` - App name

Customize and re-run setup:
```bash
nano nginx.conf.template
bash setup.sh            # Regenerates nginx config
```

### Multiple Domains Per App

Edit `nginx.conf.template`:
```nginx
server_name domain1.com domain2.com domain3.com;
```

Then setup SSL for all:
```bash
sudo certbot --nginx -d domain1.com -d domain2.com -d domain3.com
```

### Custom Deployment Hooks

You can extend the generic deployment by:

1. Sourcing the common scripts
2. Calling the generic functions
3. Adding pre/post hooks

Example:
```bash
source "$DEVOPS_DIR/common/deploy-app.sh"

# Pre-deployment hook
echo "Running custom pre-deployment checks..."

# Call generic deployment
deploy_application "$DEFAULT_SCALE"

# Post-deployment hook
echo "Sending Slack notification..."
```

### Extending App Types

To add a new app type (e.g., Python/Django):

1. Create `common/app-types/django.sh`
2. Implement required hooks:
   - `django_check_prerequisites()`
   - `django_setup_database()`
   - `django_create_env_file()`
   - `django_setup_requirements()`
   - `django_pull_code()`
   - `django_build_image()`
   - `django_deploy_fresh()`
   - `django_deploy_rolling()`
   - `django_display_deployment_summary()`
   - `django_stop_containers()`

3. Set `APP_TYPE="django"` in your app's `config.sh`

### Blue-Green Deployments

Current system uses rolling restarts. For true blue-green:

1. Deploy to new port range
2. Test new deployment
3. Switch nginx upstream
4. Remove old deployment

This can be added as a custom deployment mode.

### Container Orchestration

Current setup uses Docker standalone. For orchestration:
- **Docker Swarm**: Native Docker clustering
- **Kubernetes**: Full orchestration platform (overkill for small deployments)
- **Nomad**: Lightweight orchestration

The current architecture can be adapted to any of these.

---

## Configuration Reference

### config.sh Options

**Identity:**
```bash
export APP_TYPE="nextjs|rails"
export APP_NAME="your-app-name"
export APP_DISPLAY_NAME="Your App Name"
export DOMAIN="your-domain.com"
```

**Repository:**
```bash
export REPO_URL="git@github.com:user/repo.git"
export REPO_BRANCH="master"
```

**Containers:**
```bash
export DEFAULT_SCALE=2              # Web containers
export WORKER_COUNT=1               # Workers (Rails only)
export SCHEDULER_ENABLED=true       # Scheduler (Rails only)
export BASE_PORT=3020               # Starting port
export CONTAINER_PORT=3000          # Internal port
```

**Database (Rails only):**
```bash
export DB_NAME="app_production"
export DB_USER="app_user"
export DB_HOST="localhost"
export DB_PORT="5432"
```

**Redis (Rails only):**
```bash
export REDIS_DB_NUMBER=0
export REDIS_URL="redis://localhost:6379/0"
```

**Deployment:**
```bash
export ZERO_DOWNTIME_ENABLED=true
export HEALTH_CHECK_PATH="/up"
export HEALTH_CHECK_TIMEOUT=60
```

**Backups:**
```bash
export BACKUP_ENABLED=true                  # Database backups (Rails)
export BACKUP_RETENTION_DAYS=30
export SAVE_IMAGE_BACKUPS=true              # Docker image backups
export MAX_IMAGE_BACKUPS=20
```

**Cleanup:**
```bash
export AUTO_CLEANUP_ENABLED=true
export MAX_IMAGE_VERSIONS=20
```

---

## Quick Reference

```bash
# Setup new app
cd ~/DevOps/apps/my-app
bash setup.sh

# Deploy
./deploy.sh deploy

# Status
./deploy.sh status

# Scale
./deploy.sh scale 5

# Logs
./deploy.sh logs

# Restart
./deploy.sh restart

# Stop
./deploy.sh stop

# Console (Rails)
./deploy.sh console

# SSL setup
./deploy.sh ssl-setup

# Disaster recovery
~/DevOps/scripts/disaster-recovery.sh

# Centralized cleanup
~/DevOps/scripts/cleanup-all-apps.sh
```

---

## Migration from Version 2.x

If you're upgrading from the previous version:

1. **Backup Everything**
   ```bash
   cd ~/DevOps
   git pull
   ```

2. **Update App Configs**
   Add `APP_TYPE` to each `config.sh`:
   ```bash
   export APP_TYPE="nextjs"  # or "rails"
   ```

3. **Update Scripts** (Optional)
   Your old scripts will continue to work, but you can update to the new thin wrappers:
   ```bash
   cd ~/DevOps/apps/your-app
   cp ../templates/nextjs-app/setup.sh setup.sh.new
   cp ../templates/nextjs-app/deploy.sh deploy.sh.new
   # Review and rename if satisfied
   ```

4. **Test Deployment**
   ```bash
   ./deploy.sh deploy
   ```

5. **Update Cron Jobs**
   Replace per-app cleanup with centralized:
   ```bash
   crontab -e
   # Remove old: 0 2 * * * ~/apps/*/cleanup.sh
   # Add new: 0 2 * * * ~/DevOps/scripts/cleanup-all-apps.sh
   ```

---

## Support & Contributing

### Documentation
- Template READMEs: `templates/*/README.md`
- Disaster Recovery Config: `scripts/disaster-recovery-config.example.sh`

### Logs
```bash
# Application logs
~/apps/your-app/logs/deployments.log
~/apps/your-app/logs/cleanup.log
~/apps/your-app/logs/backup.log

# System logs
~/DevOps/logs/cleanup-all.log
/var/log/nginx/your-app-*.log
```

### Getting Help
1. Check logs
2. Review troubleshooting section
3. Check app-specific README in templates/
4. Review example apps in apps/

---

**Last Updated**: 2025-01-27
**Version**: 3.0 (Composition Architecture Refactor)
**Maintained by**: Andrzej Jantos

---

## What's New in Version 3.0

✨ **Composition Architecture** - App-type modules eliminate all code duplication
✨ **Disaster Recovery** - One script rebuilds entire server
✨ **Centralized Cleanup** - Single cron job for all apps
✨ **App Templates** - Complete templates for Next.js and Rails
✨ **Simplified Apps** - Apps now need only 4 files (down from 10+)
✨ **Better Documentation** - Comprehensive guides and examples
✨ **Easier Scaling** - Add dozens of apps without code duplication
