# DevOps Infrastructure

Production-ready Docker-based deployment infrastructure for Rails and Next.js applications with automated SSL, backups, and zero-downtime deployments.

---

## Features

✅ **Zero-Downtime Deployments** - Rolling restarts with health checks
✅ **Automatic SSL** - Let's Encrypt certificates with auto-renewal
✅ **Database Backups** - Automated PostgreSQL backups every 30 minutes
✅ **Image Rollback** - Save Docker images for instant rollback capability
✅ **Auto Cleanup** - Daily cleanup of old images and backups
✅ **Load Balancing** - Nginx reverse proxy with least_conn algorithm
✅ **Background Jobs** - Sidekiq workers and Clockwork scheduler support
✅ **Security** - Default catch-all server to reject unknown domains
✅ **Monitoring** - Health checks and container status tracking

---

## Supported Application Stacks

### Rails Applications
- **Rails 8.0** with Puma web server
- PostgreSQL database
- Redis for caching and job queues
- Sidekiq for background job processing
- Clockwork for scheduled recurring tasks
- Asset precompilation and CDN support

### Next.js Applications
- **Next.js** with standalone output mode
- Server-side rendering (SSR) and static generation
- API routes support
- Image optimization
- Client-side API communication

---

## Quick Start

### 1. Clone This Repository
```bash
cd ~
git clone git@github.com:AndrzejJantos/DevOps.git
cd DevOps
```

### 2. Deploy Your First Application

**For Rails Applications:**
```bash
cd apps/your-app-name
bash setup.sh                          # Creates everything: nginx, SSL, database
nano ~/apps/your-app-name/.env.production   # Configure secrets
./deploy.sh deploy                     # Deploy!
```

**For Next.js Applications:**
```bash
cd apps/your-app-name
bash setup.sh                          # Creates everything: nginx, SSL
nano ~/apps/your-app-name/.env.production   # Configure API URLs
./deploy.sh deploy                     # Deploy!
```

That's it! Your application is now running with SSL enabled.

---

## Directory Structure

```
DevOps/
├── apps/                           # Application-specific configurations
│   ├── cheaperfordrug-landing/     # Rails landing page
│   ├── cheaperfordrug-api/         # Rails API backend
│   ├── cheaperfordrug-web/         # Next.js frontend
│   └── _examples/                  # Example templates
│       ├── rails-app-template/
│       └── nodejs-app-template/
├── common/                         # Shared utilities and templates
│   ├── rails/                      # Rails-specific files
│   │   ├── Dockerfile.template
│   │   ├── deploy.sh               # Rails deployment logic
│   │   └── setup.sh                # Rails setup logic
│   ├── nextjs/                     # Next.js-specific files
│   │   └── Dockerfile.template
│   ├── nginx/                      # Nginx configurations
│   │   └── default-server.conf     # Catch-all security server
│   ├── utils.sh                    # Common utility functions
│   ├── docker-utils.sh             # Docker helper functions
│   └── postgres-utils.sh           # Database utilities
└── README.md                       # This file
```

---

## Deployed Applications

### 1. CheaperForDrug Landing Page
- **Domain**: presale.taniejpolek.pl
- **Type**: Rails 8.0 landing page
- **Architecture**: 2 web containers (ports 3010-3011)
- **Purpose**: Marketing and pre-launch page

### 2. CheaperForDrug API
- **Domains**:
  - api-public.cheaperfordrug.com (public endpoints)
  - api-internal.cheaperfordrug.com (JWT-protected endpoints)
- **Type**: Rails 8.0 API with background processing
- **Architecture**:
  - 2 web containers (ports 3020-3021)
  - 1 worker container (Sidekiq)
  - 1 scheduler container (Clockwork)
- **Database**: PostgreSQL with automated backups
- **Cache**: Redis

### 3. CheaperForDrug Web Frontend
- **Domain**: premiera.taniejpolek.pl
- **Type**: Next.js SPA (Single Page Application)
- **Architecture**: 3 web containers (ports 3030-3032)
- **API Communication**: Client-side calls to API subdomains

---

## Production Features

### SSL Certificate Management
- Automatic certificate installation during setup
- Let's Encrypt certificates
- Auto-renewal via systemd certbot.timer
- Runs twice daily, renews when < 30 days remain

### Database Backups (Rails Apps Only)
- **Frequency**: Every 30 minutes via cron
- **Location**: `~/apps/your-app/backups/`
- **Retention**: 30 days (configurable)
- **Format**: Compressed .sql.gz files
- **Restore**: `~/apps/your-app/restore.sh <backup-file>`

### Docker Image Backups
- Save Docker images before each deployment
- Keep last 20 versions (configurable)
- Instant rollback capability
- Location: `~/apps/your-app/docker-images/`

### Automated Cleanup
- **Frequency**: Daily at 2 AM via cron
- Removes old Docker images (keeps last 20)
- Removes old database backups (older than 30 days)
- Removes old image backups (keeps last 20)
- Logs: `~/apps/your-app/logs/cleanup.log`

### Security
- Default catch-all nginx server rejects unknown domains
- Return 444 (close connection) for unmatched requests
- Exact server_name matching (no wildcard vulnerabilities)
- CORS configuration for API endpoints

---

## Common Operations

### Deploy Application
```bash
cd ~/DevOps/apps/your-app-name
./deploy.sh deploy
```

### Deploy with Custom Scale
```bash
./deploy.sh deploy 5              # Deploy with 5 web containers
```

### Check Container Status
```bash
./deploy.sh status
```

### Scale Web Containers
```bash
./deploy.sh scale 5               # Scale to 5 web containers
```

### Restart All Containers
```bash
./deploy.sh restart
```

### Stop All Containers
```bash
./deploy.sh stop
```

### View Logs
```bash
./deploy.sh logs                  # View web container logs
./deploy.sh logs worker_1         # View worker logs
./deploy.sh logs scheduler        # View scheduler logs
```

### Rails Console (Rails Apps)
```bash
./deploy.sh console
```

### Rollback to Previous Version
```bash
./deploy.sh rollback -1           # Rollback to previous version
./deploy.sh rollback -2           # Rollback 2 versions back
./deploy.sh list-images           # List available image backups
```

### Database Operations (Rails Apps)
```bash
# Restore from backup
~/apps/your-app-name/restore.sh <backup-file>

# List available backups
~/apps/your-app-name/restore.sh

# Manual backup
~/apps/your-app-name/backup.sh

# View backup logs
tail -f ~/apps/your-app-name/logs/backup.log
```

---

## Deployment Workflow

### First-Time Setup
1. **Create application directory**
   ```bash
   cd ~/DevOps/apps
   cp -r _examples/rails-app-template your-app-name
   # or
   cp -r _examples/nodejs-app-template your-app-name
   ```

2. **Configure your application**
   ```bash
   cd your-app-name
   nano config.sh              # Set repository URL, ports, scaling
   ```

3. **Run setup**
   ```bash
   bash setup.sh               # Handles nginx, SSL, database, backups
   ```

4. **Configure environment**
   ```bash
   nano ~/apps/your-app-name/.env.production
   ```

5. **Deploy**
   ```bash
   ./deploy.sh deploy
   ```

### Regular Deployments (Updates)
```bash
cd ~/DevOps/apps/your-app-name
./deploy.sh deploy              # Pull latest code and deploy
```

### Emergency Rollback
```bash
./deploy.sh rollback -1         # Instant rollback to previous version
```

---

## Configuration Files

Each application has these key files in `apps/your-app-name/`:

### config.sh
Application-specific configuration:
- Repository URL and branch
- Container scaling (web, workers, scheduler)
- Port allocation
- Backup settings
- Deployment options

### deploy.sh
Deployment script (symlinked from common/):
- Handles deployment workflow
- Zero-downtime deployments
- Health checks
- Image backup/rollback
- Scaling operations

### setup.sh
Initial setup script:
- Creates directory structure
- Configures nginx
- Sets up SSL certificates
- Creates database (Rails)
- Configures automated backups
- Sets up cron jobs

### nginx.conf.template
Nginx configuration template:
- Upstream server definitions
- SSL configuration
- Load balancing
- Health check endpoints
- CORS headers (for APIs)

### .env.production.template
Environment variable template:
- Database credentials
- API keys
- SMTP configuration
- Application secrets

---

## Application Configuration Reference

### config.sh Options

**Application Identity:**
```bash
export APP_NAME="your-app-name"
export APP_DISPLAY_NAME="Your App Display Name"
export DOMAIN="your-domain.com"
```

**Repository:**
```bash
export REPO_URL="git@github.com:user/repo.git"
export REPO_BRANCH="master"
```

**Container Architecture:**
```bash
export DEFAULT_SCALE=2              # Number of web containers
export WORKER_COUNT=1               # Number of worker containers (Rails only)
export SCHEDULER_ENABLED=true       # Enable scheduler (Rails only)
export BASE_PORT=3010               # Starting port number
```

**Backup Configuration (Rails only):**
```bash
export BACKUP_ENABLED=true
export BACKUP_RETENTION_DAYS=30
export MIGRATION_BACKUP_ENABLED=true
```

**Image Backup:**
```bash
export SAVE_IMAGE_BACKUPS=true
export MAX_IMAGE_BACKUPS=20
export MAX_IMAGE_VERSIONS=20
```

**Deployment:**
```bash
export ZERO_DOWNTIME_ENABLED=true
export HEALTH_CHECK_PATH="/up"      # For Rails 8
export HEALTH_CHECK_TIMEOUT=60
```

---

## Troubleshooting

### Container Won't Start
```bash
# Check container logs
docker logs your-app-name_web_1

# Check if port is already in use
sudo lsof -i :3010

# Verify environment variables
cat ~/apps/your-app-name/.env.production
```

### SSL Certificate Issues
```bash
# Check DNS configuration
dig +short your-domain.com

# Check certificate status
sudo certbot certificates

# Manually obtain certificate
sudo certbot --nginx -d your-domain.com
```

### Database Connection Errors
```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Check database exists
sudo -u postgres psql -l | grep your_database_name

# Test connection
sudo -u postgres psql your_database_name
```

### Nginx Configuration Issues
```bash
# Test nginx configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# Check nginx logs
sudo tail -f /var/log/nginx/error.log
```

### Deployment Fails
```bash
# Check deploy logs
cat ~/apps/your-app-name/logs/deploy.log

# Verify Docker is running
sudo systemctl status docker

# Check disk space
df -h
```

### Rollback Not Working
```bash
# List available image backups
./deploy.sh list-images

# Manually load image
docker load -i ~/apps/your-app-name/docker-images/backup-file.tar.gz

# Check Docker images
docker images | grep your-app-name
```

---

## Server Requirements

### Operating System
- Ubuntu 22.04 LTS or newer (recommended)
- Debian 11+ also supported

### Software Requirements
- **Docker** - Container runtime
- **Nginx** - Reverse proxy and load balancer
- **PostgreSQL** - Database (for Rails apps)
- **Redis** - Cache and job queue (for Rails apps)
- **Git** - Version control
- **Certbot** - SSL certificate management

### Installation Script
```bash
# Run as root or with sudo
sudo apt-get update
sudo apt-get install -y docker.io nginx postgresql redis-server git certbot python3-certbot-nginx

# Start services
sudo systemctl enable docker nginx postgresql redis-server
sudo systemctl start docker nginx postgresql redis-server

# Add your user to docker group
sudo usermod -aG docker $USER
```

### Port Allocation
Make sure these ports are available:
- **80** - HTTP (nginx)
- **443** - HTTPS (nginx)
- **3010-3050** - Application containers
- **5432** - PostgreSQL
- **6379** - Redis

---

## DNS Configuration

Before deploying, ensure DNS A records point to your server:

```
your-domain.com              →  Your Server IP
subdomain.your-domain.com    →  Your Server IP
```

Verify DNS:
```bash
dig +short your-domain.com
```

---

## Support

### View Logs
```bash
# Application logs
tail -f ~/apps/your-app-name/logs/deploy.log
tail -f ~/apps/your-app-name/logs/backup.log
tail -f ~/apps/your-app-name/logs/cleanup.log

# Container logs
docker logs your-app-name_web_1 -f
docker logs your-app-name_worker_1 -f
docker logs your-app-name_scheduler -f

# Nginx logs
sudo tail -f /var/log/nginx/your-app-name-access.log
sudo tail -f /var/log/nginx/your-app-name-error.log
```

### Check System Status
```bash
# All containers
docker ps -a

# Application status
cd ~/DevOps/apps/your-app-name && ./deploy.sh status

# Disk space
df -h

# Memory usage
free -h

# Cron jobs
crontab -l
```

---

## License

This infrastructure is proprietary and maintained by Andrzej Jantos.

---

## Quick Reference Card

```bash
# Setup new app
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

# Rollback
./deploy.sh rollback -1

# Console (Rails)
./deploy.sh console
```

---

**Last Updated**: 2025-01-27
**Version**: 2.0
