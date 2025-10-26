# CheaperForDrug Complete Deployment Guide

This guide covers deployment of the complete CheaperForDrug platform consisting of three applications:

1. **Landing Page** (presale.taniejpolek.pl) - Rails landing page
2. **API Backend** (cheaperfordrug.com) - Rails API with background processing
3. **Web Frontend** (premiera.taniejpolek.pl) - Next.js application

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                         Users                                │
└──────────────────┬───────────────────────────────────────────┘
                   │
          ┌────────┴────────┐
          ▼                 ▼
┌──────────────────┐  ┌──────────────────┐
│  Landing Page    │  │   Web Frontend   │
│  presale.        │  │  premiera.       │
│  taniejpolek.pl  │  │  taniejpolek.pl  │
│                  │  │                  │
│  Rails 8.0       │  │  Next.js         │
│  2 containers    │  │  2 containers    │
│  Ports 3010-3011 │  │  Ports 3030-3031 │
└──────────────────┘  └─────────┬────────┘
                                │
                                │ API Calls
                                ▼
                      ┌──────────────────┐
                      │   API Backend    │
                      │  cheaperfordrug  │
                      │     .com         │
                      │                  │
                      │  Rails API       │
                      │  3 web containers│
                      │  2 workers       │
                      │  1 scheduler     │
                      │  Ports 3020-3022 │
                      └─────────┬────────┘
                                │
                       ┌────────┴─────────┐
                       ▼                  ▼
                ┌─────────────┐    ┌──────────┐
                │ PostgreSQL  │    │  Redis   │
                │  Database   │    │  Queue   │
                └─────────────┘    └──────────┘
```

---

## Prerequisites

Before deploying, ensure your server has:

- Ubuntu 22.04 LTS or newer
- Docker installed
- Nginx installed
- PostgreSQL installed
- Redis installed
- Git configured with SSH keys
- DNS records configured for all domains

### DNS Configuration Required

Ensure DNS A records point to your server IP:
- `presale.taniejpolek.pl` → Server IP
- `premiera.taniejpolek.pl` → Server IP
- `cheaperfordrug.com` → Server IP
- `www.cheaperfordrug.com` → Server IP (optional)

---

## Application 1: Landing Page (presale.taniejpolek.pl)

### Overview
- **Type**: Rails 8.0 landing page
- **Domain**: presale.taniejpolek.pl
- **Purpose**: Marketing/pre-launch page
- **Architecture**: 2 web containers (no workers/scheduler needed)
- **Status**: ✅ Already deployed

### Configuration
```bash
# Location
~/DevOps/apps/cheaperfordrug-landing/

# Container setup
DEFAULT_SCALE=2              # 2 web containers
WORKER_COUNT=0               # No workers
SCHEDULER_ENABLED=false      # No scheduler
BASE_PORT=3010               # Ports 3010-3011
```

### Management Commands
```bash
cd ~/DevOps/apps/cheaperfordrug-landing

./deploy.sh deploy          # Deploy latest code
./deploy.sh restart         # Restart containers
./deploy.sh stop            # Stop containers
./deploy.sh scale <N>       # Scale web containers
./deploy.sh status          # Show container status
./deploy.sh console         # Rails console
./deploy.sh logs            # View logs
```

---

## Application 2: API Backend (cheaperfordrug.com)

### Overview
- **Type**: Rails API with full background processing
- **Domain**: cheaperfordrug.com
- **Purpose**: Backend API for web frontend
- **Architecture**: 3 web + 2 workers + 1 scheduler
- **Status**: 🆕 Ready to deploy

### Initial Setup

#### 1. Pull Latest DevOps Code
```bash
cd ~/DevOps
git pull origin master
```

#### 2. Run Setup Script
```bash
cd ~/DevOps/apps/cheaperfordrug-api
bash setup.sh
```

This will:
- Create directory structure
- Clone repository
- Generate SECRET_KEY_BASE and JWT_SECRET_KEY
- Create PostgreSQL database and user
- Setup nginx configuration
- Configure automated backups (every 30 minutes)

#### 3. Configure Environment Variables
```bash
nano ~/apps/cheaperfordrug-api/.env.production
```

Update the following:
- **SMTP credentials** (Mailgun):
  ```
  SMTP_USERNAME=postmaster@mg.cheaperfordrug.com
  SMTP_PASSWORD=your-mailgun-password
  ```

- **API Keys** (if needed):
  ```
  PHARMACY_API_KEY=
  GOOGLE_MAPS_API_KEY=
  STRIPE_SECRET_KEY=
  ```

- **CORS** (already configured for premiera.taniejpolek.pl):
  ```
  ALLOWED_ORIGINS=https://premiera.taniejpolek.pl
  ```

#### 4. Setup SSL Certificates
```bash
cd ~/DevOps/apps/cheaperfordrug-api
./deploy.sh ssl-setup
```

Follow certbot prompts to configure SSL for:
- cheaperfordrug.com
- www.cheaperfordrug.com

#### 5. Deploy Application
```bash
./deploy.sh deploy
```

This will:
- Pull latest code from repository
- Build Docker image
- Start 3 web containers (ports 3020-3022)
- Run database migrations
- Start 2 worker containers (Sidekiq)
- Start 1 scheduler container (Clockwork)
- Configure nginx with load balancing

### Container Architecture

**Web Containers (3)**
- Handle API requests
- Ports: 3020, 3021, 3022
- Behind nginx load balancer
- Zero-downtime deployments

**Worker Containers (2)**
- Process background jobs via Sidekiq
- Connected to Redis
- Handle emails, data processing, external API calls
- No port exposure

**Scheduler Container (1)**
- Runs Clockwork for recurring tasks
- Enqueues jobs to Sidekiq at scheduled times
- No port exposure

### Management Commands
```bash
cd ~/DevOps/apps/cheaperfordrug-api

# Deployment
./deploy.sh deploy          # Deploy latest code
./deploy.sh restart         # Restart all containers
./deploy.sh stop            # Stop all containers
./deploy.sh scale <N>       # Scale web containers (workers unaffected)

# Monitoring
./deploy.sh status          # Show all containers (web + workers + scheduler)
./deploy.sh logs            # View web logs
./deploy.sh logs worker_1   # View worker logs
./deploy.sh logs scheduler  # View scheduler logs

# Database
./deploy.sh console         # Rails console
./deploy.sh task db:migrate # Run migrations
~/apps/cheaperfordrug-api/restore.sh <backup>  # Restore database
```

### Database Backups
- **Automatic**: Every 30 minutes via cron
- **Location**: `~/apps/cheaperfordrug-api/backups/`
- **Retention**: 30 days
- **Restore**: `~/apps/cheaperfordrug-api/restore.sh <backup_file>`

### Monitoring Worker Health
```bash
# Check if workers are processing jobs
docker logs cheaperfordrug-api_worker_1 -f

# Check Sidekiq queue (in Rails console)
docker exec -it cheaperfordrug-api_web_1 rails console
> Sidekiq::Queue.all.map { |q| [q.name, q.size] }
```

---

## Application 3: Web Frontend (premiera.taniejpolek.pl)

### Overview
- **Type**: Next.js frontend application
- **Domain**: premiera.taniejpolek.pl
- **Purpose**: User-facing web application
- **Architecture**: 2 web containers (no workers/scheduler)
- **Status**: 🆕 Ready to deploy

### Initial Setup

#### 1. Pull Latest DevOps Code
```bash
cd ~/DevOps
git pull origin master
```

#### 2. Run Setup Script
```bash
cd ~/DevOps/apps/cheaperfordrug-web
bash setup.sh
```

This will:
- Create directory structure
- Clone repository
- Create .env.production template
- Setup nginx configuration
- Copy Next.js Dockerfile template

#### 3. Configure Next.js for Standalone Output

**IMPORTANT**: Your Next.js project needs standalone output configured for Docker deployment.

Edit `next.config.js` in your repository:
```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',

  // Other configuration...
}

module.exports = nextConfig
```

Commit and push this change to your repository.

#### 4. Configure Environment Variables
```bash
nano ~/apps/cheaperfordrug-web/.env.production
```

Update the following:
- **API URL** (backend):
  ```
  NEXT_PUBLIC_API_URL=https://cheaperfordrug.com
  NEXT_PUBLIC_API_BASE_URL=https://cheaperfordrug.com/api/v1
  ```

  Note: All API calls are client-side (browser), so we use the public HTTPS domain.

- **Google Maps** (if used):
  ```
  NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=your-key-here
  ```

- **Analytics** (if used):
  ```
  NEXT_PUBLIC_GA_MEASUREMENT_ID=G-XXXXXXXXXX
  ```

#### 5. Setup SSL Certificates
```bash
cd ~/DevOps/apps/cheaperfordrug-web
./deploy.sh ssl-setup
```

Follow certbot prompts to configure SSL for:
- premiera.taniejpolek.pl
- www.premiera.taniejpolek.pl

#### 6. Deploy Application
```bash
./deploy.sh deploy
```

This will:
- Pull latest code from repository
- Build Next.js Docker image
- Start 2 web containers (ports 3030-3031)
- Configure nginx with load balancing

### Container Architecture

**Web Containers (2)**
- Serve Next.js application
- Ports: 3030, 3031
- Behind nginx load balancer
- Zero-downtime deployments
- Static assets cached by nginx

### Management Commands
```bash
cd ~/DevOps/apps/cheaperfordrug-web

# Deployment
./deploy.sh deploy          # Deploy latest code
./deploy.sh restart         # Restart all containers
./deploy.sh stop            # Stop all containers
./deploy.sh scale <N>       # Scale web containers

# Monitoring
./deploy.sh status          # Show container status
./deploy.sh logs            # View logs
./deploy.sh logs web_2      # View specific container logs
```

### No Database or Workers
Frontend application has no database or background processing. All data operations go through the API backend.

### Client-Side API Communication

All API calls are **client-side** (happen in the browser):

```javascript
// In React components, hooks, event handlers
// Browser makes direct HTTPS requests to API
const response = await fetch(
  `${process.env.NEXT_PUBLIC_API_BASE_URL}/drugs`,
  {
    headers: { 'Authorization': `Bearer ${token}` }
  }
);
```

**Architecture:**
```
User's Browser → Internet (HTTPS) → cheaperfordrug.com (API)
                 ↑
            (all API calls)
```

Note: This is a **SPA (Single Page Application)** architecture, not SSR. The Next.js containers serve static/pre-rendered content, and the browser handles all API communication.

---

## Complete Deployment Workflow

### First-Time Setup (All Apps)

```bash
# 1. Pull latest DevOps infrastructure
cd ~/DevOps
git pull origin master

# 2. Setup API (if not already done)
cd ~/DevOps/apps/cheaperfordrug-api
bash setup.sh
nano ~/apps/cheaperfordrug-api/.env.production  # Configure
./deploy.sh ssl-setup
./deploy.sh deploy

# 3. Setup Web Frontend
cd ~/DevOps/apps/cheaperfordrug-web
bash setup.sh
nano ~/apps/cheaperfordrug-web/.env.production  # Configure
./deploy.sh ssl-setup
./deploy.sh deploy

# 4. Landing page already deployed, update if needed
cd ~/DevOps/apps/cheaperfordrug-landing
git pull
./deploy.sh deploy
```

### Regular Deployment (Code Updates)

```bash
# Deploy all applications after code changes
cd ~/DevOps

# Deploy API
cd apps/cheaperfordrug-api && ./deploy.sh deploy

# Deploy Web Frontend
cd ../cheaperfordrug-web && ./deploy.sh deploy

# Deploy Landing (if changed)
cd ../cheaperfordrug-landing && ./deploy.sh deploy
```

### Monitoring All Applications

```bash
# Check status of all apps
cd ~/DevOps/apps

# Landing Page
cd cheaperfordrug-landing && ./deploy.sh status

# API Backend
cd ../cheaperfordrug-api && ./deploy.sh status

# Web Frontend
cd ../cheaperfordrug-web && ./deploy.sh status
```

---

## Nginx Configuration

All applications are behind nginx with:
- **SSL/TLS**: Let's Encrypt certificates (auto-renew)
- **HTTP → HTTPS**: Automatic redirect
- **Load Balancing**: least_conn algorithm
- **Static Caching**: Optimized for Next.js assets
- **CORS**: Configured for API

### View Nginx Status
```bash
sudo systemctl status nginx
sudo nginx -t                    # Test configuration
sudo tail -f /var/log/nginx/*.log  # View logs
```

---

## Scaling Strategies

### Landing Page (Low Traffic)
```bash
# Currently: 2 containers
# Scale if needed: ./deploy.sh scale 3
```

### API Backend (Medium Traffic)
```bash
# Web containers: 3 (can scale to 5-10 for high load)
cd ~/DevOps/apps/cheaperfordrug-api
./deploy.sh scale 5

# Workers: 2 (increase if job queue backs up)
# Edit config.sh: WORKER_COUNT=3
# Then: ./deploy.sh deploy
```

### Web Frontend (High Traffic Expected)
```bash
# Currently: 2 containers
# Scale for launch: ./deploy.sh scale 4
cd ~/DevOps/apps/cheaperfordrug-web
./deploy.sh scale 4
```

---

## Troubleshooting

### API Container Not Starting
```bash
# Check logs
docker logs cheaperfordrug-api_web_1

# Common issues:
# 1. Database connection - check DATABASE_URL in .env.production
# 2. Redis connection - ensure Redis is running
# 3. Missing SECRET_KEY_BASE - regenerate with: rails secret
```

### Web Frontend Build Failing
```bash
# Check if standalone output is configured
# In next.config.js: output: 'standalone'

# Check environment variables
cat ~/apps/cheaperfordrug-web/.env.production

# View build logs
docker logs cheaperfordrug-web_web_1
```

### SSL Certificate Issues
```bash
# Check certificate status
sudo certbot certificates

# Renew manually
sudo certbot renew

# Re-run SSL setup
cd ~/DevOps/apps/<app-name>
./deploy.sh ssl-setup
```

### Worker Not Processing Jobs
```bash
# Check worker logs
docker logs cheaperfordrug-api_worker_1 -f

# Check Redis connection
docker exec cheaperfordrug-api_worker_1 redis-cli -h localhost ping

# Restart workers
cd ~/DevOps/apps/cheaperfordrug-api
./deploy.sh restart
```

---

## Backup and Recovery

### API Database Backups
```bash
# List backups
ls -lh ~/apps/cheaperfordrug-api/backups/

# Restore from backup
~/apps/cheaperfordrug-api/restore.sh ~/apps/cheaperfordrug-api/backups/cheaperfordrug_production_20250126_120000.sql.gz
```

### Docker Image Rollback
```bash
# List available images
cd ~/DevOps/apps/<app-name>
ls -lh ~/apps/<app-name>/docker-images/

# Rollback is handled automatically (keeps last 20 versions)
```

---

## Port Allocation Summary

```
Application              Ports          Purpose
─────────────────────────────────────────────────────
Landing Page            3010-3011      Web containers
API Backend             3020-3022      Web containers
API Workers             (no port)      Background jobs
API Scheduler           (no port)      Recurring tasks
Web Frontend            3030-3031      Web containers

External Ports          80, 443        Nginx (HTTP/HTTPS)
Database                5432           PostgreSQL
Cache/Queue             6379           Redis
```

---

## Security Checklist

- [ ] All applications use HTTPS (SSL certificates installed)
- [ ] Environment files contain strong randomly-generated secrets
- [ ] Database passwords are strong and unique
- [ ] CORS is configured correctly (API allows only premiera.taniejpolek.pl)
- [ ] Nginx security headers are in place
- [ ] Docker containers run as non-root users
- [ ] Automated backups are running (check crontab)
- [ ] Sensitive files are not in Docker images (.env files removed)

---

## Monitoring and Maintenance

### Daily Checks
```bash
# Check all containers are running
docker ps | grep cheaper

# Check nginx is healthy
sudo systemctl status nginx

# Check disk space
df -h
```

### Weekly Checks
```bash
# Review backup status
ls -lh ~/apps/*/backups/ | tail -20

# Check logs for errors
cd ~/DevOps/apps
grep -i error */logs/*.log | tail -50
```

### Monthly Maintenance
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Clean up old Docker images (done automatically, but verify)
docker images | grep cheaper

# Review and rotate logs if needed
sudo journalctl --vacuum-time=30d
```

---

## Support and References

- **DevOps Repository**: `~/DevOps/`
- **Architecture Documentation**: `~/DevOps/docs/ARCHITECTURE.md`
- **Application Directories**:
  - Landing: `~/apps/cheaperfordrug-landing/`
  - API: `~/apps/cheaperfordrug-api/`
  - Web: `~/apps/cheaperfordrug-web/`

For issues with deployment scripts, check:
- `~/DevOps/common/` - Shared utilities
- `~/DevOps/apps/<app>/deployment-info.txt` - App-specific info

---

## Quick Reference

### Deploy Everything
```bash
cd ~/DevOps/apps/cheaperfordrug-api && ./deploy.sh deploy
cd ~/DevOps/apps/cheaperfordrug-web && ./deploy.sh deploy
cd ~/DevOps/apps/cheaperfordrug-landing && ./deploy.sh deploy
```

### Check All Status
```bash
cd ~/DevOps/apps/cheaperfordrug-api && ./deploy.sh status
cd ~/DevOps/apps/cheaperfordrug-web && ./deploy.sh status
cd ~/DevOps/apps/cheaperfordrug-landing && ./deploy.sh status
```

### View All Logs
```bash
# API
docker logs cheaperfordrug-api_web_1 -f --tail=100
docker logs cheaperfordrug-api_worker_1 -f --tail=100

# Web
docker logs cheaperfordrug-web_web_1 -f --tail=100

# Landing
docker logs cheaperfordrug-landing_web_1 -f --tail=100
```
