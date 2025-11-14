# CheaperForDrug DevOps Infrastructure

**Production-Ready Infrastructure for Rails APIs and Next.js Applications**

**Server:** Hetzner (65.109.22.232:2222)
**Last Updated:** 2025-11-14
**Total Containers:** 24 active (13 web, 2 workers, 1 scheduler, 8 scrapers)

---

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Infrastructure Services](#infrastructure-services)
4. [Application Services](#application-services)
5. [Scraper System](#scraper-system)
6. [Network Architecture](#network-architecture)
7. [Container Management](#container-management)
8. [Deployment Procedures](#deployment-procedures)
9. [Performance Optimization](#performance-optimization)
10. [CDN & Active Storage](#cdn--active-storage)
11. [Email Notifications](#email-notifications)
12. [Database & Redis](#database--redis)
13. [Security & SSL](#security--ssl)
14. [Monitoring & Health Checks](#monitoring--health-checks)
15. [Troubleshooting](#troubleshooting)
16. [Disaster Recovery](#disaster-recovery)

---

## Overview

This DevOps repository is the central infrastructure management system for the CheaperForDrug and Brokik platforms running on Ubuntu servers. It provides:

- **Automated Server Initialization** - Complete Ubuntu server setup from scratch
- **Multi-Application Deployment** - Rails APIs and Next.js frontends with zero-downtime deployments
- **Fully Automated SSL Management** - Let's Encrypt certificates automatically obtained and renewed
- **Container Orchestration** - Docker with health checks, rolling updates, and automatic restart
- **Load Balancing** - Nginx with dynamic upstream generation
- **Performance Optimization** - Docker build optimization (2000x improvement), database indexing
- **CDN Integration** - Direct nginx-based file serving for Active Storage
- **Scraper System** - VPN-enabled scraping with automated product updates
- **Email Notifications** - SendGrid integration for deployment alerts
- **Disaster Recovery** - Complete system rebuild capability

### Technology Stack

- **OS:** Ubuntu (22.04+)
- **Web Server:** Nginx with SSL (Let's Encrypt)
- **Containerization:** Docker with host networking
- **Backend:** Ruby on Rails 3.4.5 + Node.js 20.x
- **Frontend:** Next.js (standalone mode)
- **Database:** PostgreSQL 14+
- **Cache/Queues:** Redis 8+
- **Background Jobs:** Sidekiq
- **Search:** Elasticsearch (AWS)
- **SSL:** Certbot (auto-renewal)
- **Email:** SendGrid API

---

## System Architecture

### Container Overview (51 Total Across All Systems)

```
Production Environment (hetzner-andrzej: 65.109.22.232)
════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────┐
│                    BROKIK PLATFORM                          │
├─────────────────────────────────────────────────────────────┤
│ Brokik API (Rails)                                          │
│   • 2 Web Containers (ports 3040-3041)                     │
│   • 1 Sidekiq Worker                                        │
│   • 1 Clockwork Scheduler                                   │
│   • Domains: api-public.brokik.com                         │
│             api-internal.brokik.com                         │
│                                                              │
│ Brokik Web (Next.js)                                        │
│   • 3 Web Containers (ports 3050-3052)                     │
│   • Domain: www.brokik.com                                  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│               CHEAPERFORDRUG PLATFORM                        │
├─────────────────────────────────────────────────────────────┤
│ CheaperForDrug Landing (Rails)                              │
│   • 2 Web Containers (ports 3010-3011)                     │
│   • Domain: taniejpolek.pl, presale.taniejpolek.pl        │
│                                                              │
│ CheaperForDrug Web (Next.js)                                │
│   • 3 Web Containers (ports 3030-3032)                     │
│   • Domain: premiera.taniejpolek.pl                         │
│                                                              │
│ CheaperForDrug API (Rails)                                  │
│   • 3 Web Containers (ports 3020-3022)                     │
│   • 1 Sidekiq Worker                                        │
│   • Domains: api-public.cheaperfordrug.com                 │
│             api-internal.cheaperfordrug.com                 │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    SCRAPER SYSTEM                            │
├─────────────────────────────────────────────────────────────┤
│ VPN Scrapers (3 containers)                                 │
│   • scraper-vpn-poland (NordVPN PL)                        │
│   • scraper-vpn-germany (NordVPN DE)                       │
│   • scraper-vpn-czech (NordVPN CZ)                         │
│                                                              │
│ Product Update Workers (5 containers)                       │
│   • product-update-worker-poland-1                          │
│   • product-update-worker-poland-2                          │
│   • product-update-worker-poland-3                          │
│   • product-update-worker-poland-4                          │
│   • product-update-worker-poland-5                          │
│   • All connect to: http://localhost:3020-3022            │
└─────────────────────────────────────────────────────────────┘

TOTALS:
────────
• Web Containers: 13
• Workers: 2 (Sidekiq)
• Schedulers: 1 (Clockwork)
• Scrapers: 8 (3 VPN + 5 workers)
• GRAND TOTAL: 24 Active Containers
```

### Network Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    EXTERNAL TRAFFIC                           │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│                  NGINX (Port 443 SSL)                        │
│            Let's Encrypt Auto-Renewal                        │
└──────────────────────────────────────────────────────────────┘
                            │
                ┌───────────┴──────────┬──────────────┐
                ▼                      ▼              ▼
┌─────────────────────┐  ┌──────────────────┐  ┌────────────────┐
│  Rails API Apps     │  │  Next.js Apps    │  │  CDN Files     │
│  (Load Balanced)    │  │  (Load Balanced) │  │  (Direct)      │
│  • Brokik API       │  │  • Brokik Web    │  │  /var/storage  │
│  • CFD API          │  │  • CFD Web       │  │  cdn.webet.pl  │
│  • CFD Landing      │  │  • CFD Landing   │  │                │
└─────────────────────┘  └──────────────────┘  └────────────────┘
         │                        │
         └────────┬───────────────┘
                  ▼
┌──────────────────────────────────────────────────────────────┐
│                   SHARED SERVICES                             │
│                                                               │
│  PostgreSQL (localhost:5432)    Redis (localhost:6379)      │
│  ├─ brokik_production           ├─ DB 0: Brokik            │
│  ├─ cheaperfordrug_production   ├─ DB 1: CFD Landing       │
│  └─ cheaperfordrug_landing_...  ├─ DB 2: CFD API           │
│                                  └─ DB 3: Brokik API        │
└──────────────────────────────────────────────────────────────┘
```

---

## Infrastructure Services

### 1. Nginx Load Balancer

**Purpose:** SSL termination, load balancing, static file serving

**Key Features:**
- Automatic SSL certificate management (Let's Encrypt)
- Dynamic upstream generation based on container count
- Health checks with automatic failover
- HTTP/2 support
- Gzip compression
- Security headers (HSTS, XSS protection, etc.)
- CDN for Active Storage files

**Configuration Pattern:**
```nginx
upstream app_backend {
    server localhost:3020;  # Container 1
    server localhost:3021;  # Container 2
    server localhost:3022;  # Container 3
}

server {
    listen 443 ssl http2;
    server_name api-public.cheaperfordrug.com;

    ssl_certificate /etc/letsencrypt/live/.../fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/.../privkey.pem;

    location / {
        proxy_pass http://app_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        # ... additional headers
    }
}
```

**Management Commands:**
```bash
# Rebuild all nginx configs
./rebuild-nginx-configs.sh

# Test configuration
sudo nginx -t

# Reload without downtime
sudo systemctl reload nginx

# View logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### 2. Docker Container Platform

**Network Mode:** Host networking (required for Linux PostgreSQL/Redis access)

**Container Types:**

**Web Containers:**
- Rails: Puma with health endpoint `/up`
- Next.js: Standalone mode with built-in server
- Each container on unique port (host networking)

**Worker Containers:**
- Sidekiq for background job processing
- No exposed ports (internal communication via Redis)
- Graceful shutdown with 90-second timeout

**Scheduler Containers:**
- Clockwork for recurring tasks
- Enqueues jobs to Sidekiq

**Container Naming Convention:**
```
{app-name}_web_{number}       # Web containers
{app-name}_worker_{number}    # Worker containers
{app-name}_scheduler_{number} # Scheduler containers
```

**Port Allocation:**
```
Application                Ports        Containers
────────────────────────────────────────────────────
Brokik API                3040-3041    2 web + 1 worker + 1 scheduler
Brokik Web                3050-3052    3 web
CheaperForDrug Landing    3010-3011    2 web
CheaperForDrug Web        3030-3032    3 web
CheaperForDrug API        3020-3022    3 web + 1 worker
────────────────────────────────────────────────────
Reserved                  3060-3099    Future expansion
```

### 3. SSL/TLS Certificate Management

**Fully Automated** - No manual certificate commands required!

**How It Works:**
1. Every deployment automatically checks SSL certificates
2. Validates expiry (warns if < 30 days remaining)
3. Automatically obtains certificates if missing (DNS configured)
4. Configures nginx with SSL and HTTP→HTTPS redirect
5. Logs SSL status in deployment log

**Auto-Renewal:**
- Systemd timer checks twice daily
- Automatically renews when certificates expire within 30 days
- Nginx reloads automatically after renewal
- No manual intervention required

**Certificate Locations:**
```
/etc/letsencrypt/live/{domain}/
├── fullchain.pem  # Full certificate chain
├── privkey.pem    # Private key
├── cert.pem       # Certificate only
└── chain.pem      # Chain only
```

**Manual Operations (rarely needed):**
```bash
# Check certificate status
sudo certbot certificates

# Force renewal (if needed)
sudo certbot renew --force-renewal

# View renewal timer
systemctl status certbot.timer

# View logs
sudo tail -50 /var/log/letsencrypt/letsencrypt.log
```

### 4. PostgreSQL Database

**Version:** 14+
**Configuration:** Optimized for Docker host networking

**Setup:**
```bash
# Configure for Docker access
# postgresql.conf
listen_addresses = '*'

# pg_hba.conf
host    all    all    172.17.0.0/16    md5
```

**Database Allocation:**
```
Database                              Application
──────────────────────────────────────────────────────────
brokik_production                     Brokik API
cheaperfordrug_production             CheaperForDrug API
cheaperfordrug_landing_production     CheaperForDrug Landing
```

**Backup Strategy:**
- Daily automated backups before migrations
- Compressed format (.sql.gz)
- 30-day retention
- Location: `~/apps/{app-name}/backups/`

**Database Operations:**
```bash
# Manual backup
pg_dump -U {user} {database} | gzip > backup.sql.gz

# Restore
gunzip -c backup.sql.gz | psql -U {user} {database}

# Check size
sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('cheaperfordrug_production'));"
```

### 5. Redis Cache & Queues

**Version:** 8+
**Configuration:** Optimized for Streams and Sidekiq

**Redis DB Allocation:**
```
DB #    Application               Purpose
───────────────────────────────────────────────
0       Brokik API (test)        Testing
1       CFD Landing              Sessions, cache
2       CFD API                  Sidekiq, cache
3       Brokik API               Sidekiq, cache, scheduler
```

**Configuration Highlights:**
```ini
# /etc/redis/redis.conf
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly yes  # AOF persistence for durability
bind 0.0.0.0    # Allow Docker container access
```

**Monitoring:**
```bash
# Check Redis status
redis-cli info stats

# Monitor Sidekiq queues
redis-cli -n 2 LLEN queue:default  # CFD API
redis-cli -n 3 LLEN queue:default  # Brokik API

# View memory usage
redis-cli info memory
```

---

## Application Services

### Brokik API (Rails API)

**Type:** Rails 3.4.5 API with background processing
**Domains:** api-public.brokik.com, api-internal.brokik.com
**Container Architecture:** 2 web + 1 worker + 1 scheduler
**Ports:** 3040-3041 (host), 3000 (container)
**Database:** brokik_production (PostgreSQL)
**Redis:** DB 3
**Storage:** Local host disk at `/var/storage/brokik-api/active_storage`

**Architecture:**
- **api-public.brokik.com** - Public API endpoints (no auth required)
- **api-internal.brokik.com** - Protected API endpoints (JWT auth)
- Both domains route to same containers (Rails handles routing)

**Container Details:**
```
brokik-api_web_1      [Port 3040]  Web container #1
brokik-api_web_2      [Port 3041]  Web container #2
brokik-api_worker_1                Sidekiq worker
brokik-api_scheduler               Clockwork scheduler
```

**Deployment:**
```bash
cd ~/DevOps/apps/brokik-api
./deploy.sh deploy
```

**Key Features:**
- Dual-subdomain architecture (public/internal)
- Active Storage with CDN integration
- Background job processing (email, data sync, external APIs)
- Scheduled tasks (cleanup, reports, notifications)
- JWT authentication (devise-jwt)

---

### Brokik Web (Next.js Frontend)

**Type:** Next.js Pages Router
**Domain:** www.brokik.com
**Container Architecture:** 3 web containers
**Ports:** 3050-3052 (host), 3000 (container)
**Backend:** Brokik API (api-public/internal)

**Container Details:**
```
brokik-web_web_1  [Port 3050]  Next.js instance #1
brokik-web_web_2  [Port 3051]  Next.js instance #2
brokik-web_web_3  [Port 3052]  Next.js instance #3
```

**Deployment:**
```bash
cd ~/DevOps/apps/brokik-web
./deploy.sh deploy
```

**Features:**
- Static Site Generation (SSG) for performance
- Client-Side Rendering (CSR) for dynamic content
- Next.js Image optimization
- Multi-container load balancing
- Standalone mode for optimized Docker images

---

### CheaperForDrug Landing (Rails)

**Type:** Rails 3.4.5 Marketing/Landing Page
**Domains:** taniejpolek.pl, presale.taniejpolek.pl
**Container Architecture:** 2 web containers
**Ports:** 3010-3011 (host), 3000 (container)
**Database:** cheaperfordrug_landing_production
**Redis:** DB 1

**Container Details:**
```
cheaperfordrug-landing_web_1  [Port 3010]  Web container #1
cheaperfordrug-landing_web_2  [Port 3011]  Web container #2
```

**Deployment:**
```bash
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy
```

**Features:**
- Marketing landing pages
- Lead capture forms
- SendGrid email integration
- Google Analytics & Tag Manager
- Facebook Pixel tracking
- Stripe payment integration

---

### CheaperForDrug Web (Next.js Frontend)

**Type:** Next.js Application
**Domains:** premiera.taniejpolek.pl
**Container Architecture:** 3 web containers
**Ports:** 3030-3032 (host), 3000 (container)
**Backend:** CheaperForDrug API

**Container Details:**
```
cheaperfordrug-web_web_1  [Port 3030]  Next.js instance #1
cheaperfordrug-web_web_2  [Port 3031]  Next.js instance #2
cheaperfordrug-web_web_3  [Port 3032]  Next.js instance #3
```

**Deployment:**
```bash
cd ~/DevOps/apps/cheaperfordrug-web
./deploy.sh deploy
```

**Features:**
- Drug price comparison interface
- Elasticsearch-powered search
- Pharmacy catalog
- Multi-country support (Poland, Germany, Czech)
- Material-UI with custom theming
- Responsive design

---

### CheaperForDrug API (Rails API)

**Type:** Rails 3.4.5 API with Elasticsearch
**Domains:** api-public.cheaperfordrug.com, api-internal.cheaperfordrug.com
**Container Architecture:** 3 web + 1 worker
**Ports:** 3020-3022 (host), 3000 (container)
**Database:** cheaperfordrug_production
**Redis:** DB 2
**Search:** AWS Elasticsearch

**Container Details:**
```
cheaperfordrug-api_web_1     [Port 3020]  Web container #1
cheaperfordrug-api_web_2     [Port 3021]  Web container #2
cheaperfordrug-api_web_3     [Port 3022]  Web container #3
cheaperfordrug-api_worker_1               Sidekiq worker
```

**Deployment:**
```bash
cd ~/DevOps/apps/cheaperfordrug-api
./deploy.sh deploy
```

**Key Features:**
- Drug database with Searchkick/Elasticsearch
- Pharmacy price comparison
- Multi-country support (Poland, Germany, Czech)
- Background job processing (email, data sync, search indexing)
- Scraper API endpoints (token-authenticated)
- Active Storage for file uploads

**Performance Optimizations:**
- Database indexes for DISTINCT ON queries (60s → 0.5ms)
- Elasticsearch for fast drug search
- Redis caching for frequently accessed data
- Multi-container load balancing

---

## Scraper System

**Location:** `~/apps/cheaperfordrug-scraper`
**Total Containers:** 8 (3 VPN + 5 workers)
**Image:** scraper-vpn:latest (2.19GB)
**Management:** docker-compose.yml

### Architecture Overview

The scraper system consists of two types of containers:

1. **VPN Scrapers (3)** - Scrape pharmacy websites with NordVPN rotation
2. **Product Update Workers (5)** - Call CheaperForDrug API to update product data

**Connection Flow:**
```
VPN Scrapers
    ↓ (Scrape pharmacy websites)
    ↓ (Store data locally)
Product Update Workers
    ↓ (Read local data)
    ↓ (HTTP POST to localhost:3020-3022)
CheaperForDrug API (Nginx load balances)
    ↓ (3 web containers)
    ↓ (Process and validate)
PostgreSQL + Elasticsearch
```

### VPN Scraper Containers

**All use NordVPN with 5-minute rotation**

#### 1. Poland VPN Scraper
```
Container Name: scraper-vpn-poland
VPN Country: Poland
Rotation: Every 5 minutes
Resources: 2 CPU cores, 6GB RAM
Health Check: nordvpn status (every 60s)
```

**Pharmacies:**
- Gemini
- DOZ
- WaptekaPL
- i-Apteka
- ZikoApteka
- SuperPharm
- Melissa

**Operation:** Continuous scraping with 5-minute VPN rotation

#### 2. Germany VPN Scraper
```
Container Name: scraper-vpn-germany
VPN Country: Germany
Status: Standby (German pharmacies not yet configured)
```

#### 3. Czech Republic VPN Scraper
```
Container Name: scraper-vpn-czech
VPN Country: Czech Republic
Status: Standby (Czech pharmacies not yet configured)
```

### Product Update Workers (5 containers)

**All connect to Poland VPN, call CheaperForDrug API**

**Configuration:**
- VPN Rotation: Every 15 minutes
- API Endpoint: Nginx load balancer → localhost:3020-3022
- Authentication: Bearer token (SCRAPER_AUTH_TOKEN)
- Concurrency: 20 concurrent requests per worker
- Poll Interval: 1 second
- Batch Size: 20 items per batch

**Startup Timing (Staggered):**
```
Worker 1: 30.0s  (VPN wait + 0ms offset)
Worker 2: 30.2s  (VPN wait + 200ms offset)
Worker 3: 30.4s  (VPN wait + 400ms offset)
Worker 4: 30.6s  (VPN wait + 600ms offset)
Worker 5: 30.8s  (VPN wait + 800ms offset)
```

**Data Flow:**
```
1. Workers poll API for pending updates (1-second interval)
2. Fetch batch of 20 products
3. Process each product (max 20 concurrent)
4. POST updates to API (localhost:3020-3022)
5. API validates and stores in PostgreSQL
6. Elasticsearch indexes updated
7. Repeat continuously
```

**Management Commands:**
```bash
# Restart all scraper containers
cd ~/apps/cheaperfordrug-scraper
docker-compose restart

# Restart specific country scraper
docker-compose restart scraper-vpn-poland

# Restart specific worker
docker-compose restart product-update-worker-poland-1

# View logs
docker-compose logs -f scraper-vpn-poland
docker-compose logs -f product-update-worker-poland-1

# Check status
docker-compose ps
```

**Volume Mounts:**
```
./outputs:/app/scraper/outputs  # Scraped data
./logs:/app/scraper/logs        # Application logs
./state:/app/scraper/state      # Worker state/checkpoints
.:/app/scraper:ro               # Scraper code (read-only)
```

**Log Locations:**
- Docker logs: `~/apps/cheaperfordrug-scraper/docker-logs/{container-name}/`
- Application logs: `~/apps/cheaperfordrug-scraper/logs/`
- Worker logs: `~/apps/cheaperfordrug-scraper/logs/workers/`

---

## Network Architecture

### Port Allocation Strategy

**Web Services (Nginx Reverse Proxy):**
```
Application                 Port Range     Containers
─────────────────────────────────────────────────────────
Brokik API                  3040-3041      2
Brokik Web                  3050-3052      3
CheaperForDrug Landing      3010-3011      2
CheaperForDrug Web          3030-3032      3
CheaperForDrug API          3020-3022      3
─────────────────────────────────────────────────────────
Reserved for Future         3060-3099      Available
```

**Internal Services (No External Ports):**
- Sidekiq Workers (communicate via Redis)
- Clockwork Schedulers (communicate via Redis)
- VPN Scrapers (VPN connections only)
- Product Update Workers (HTTP to localhost API)

### SSL/TLS Configuration

**Certificate Provider:** Let's Encrypt (auto-renewal)

**Active Certificates:**
```
Domain                             Expiry         Days Left
───────────────────────────────────────────────────────────
api-public.brokik.com              2026-01-29     75
www.brokik.com                     2026-01-29     75
taniejpolek.pl                     2026-01-28     74
premiera.taniejpolek.pl            Valid          N/A
api-public.cheaperfordrug.com      2026-01-25     71
cdn.webet.pl                       Valid          N/A
```

**Certificate Auto-Renewal:**
- Systemd timer: certbot.timer (twice daily)
- Auto-renew certificates expiring within 30 days
- Nginx reloads automatically after renewal
- No manual intervention required

---

## Container Management

### Critical: Host Networking on Linux

**Why Host Networking?**

On native Linux (Ubuntu/Hetzner), Docker containers **cannot access host services** via `host.docker.internal` (this only works on Docker Desktop/macOS/Windows).

**Solution:** Use `--network host` mode, which allows containers to directly access `localhost` services.

**Trade-off:** Each web container must listen on a **different port** to avoid conflicts.

### Container Networking Pattern

```bash
# Database connection (in .env.production)
DATABASE_URL=postgresql://user:password@localhost/database_name
REDIS_URL=redis://localhost:6379/2

# Container creation
docker run -d \
  --name app_web_1 \
  --network host \
  --env-file .env.production \
  -e PORT=3020 \
  --restart unless-stopped \
  app:latest
```

**How It Works:**
- `--network host`: Container shares host network namespace
- `localhost` in container = `localhost` on host
- Each web container uses unique `PORT` environment variable
- Workers don't bind to ports (no conflicts)

### Adding New Web Containers

**Step 1: Choose unique port**
```
Existing:
- app_web_1: PORT=3020
- app_web_2: PORT=3021
- app_web_3: PORT=3022

New:
- app_web_4: PORT=3023  # Next available
```

**Step 2: Create container**
```bash
docker run -d \
  --name app_web_4 \
  --network host \
  --env-file /path/to/.env.production \
  -e PORT=3023 \
  --restart unless-stopped \
  app:latest
```

**Step 3: Update nginx load balancer**
```bash
cd ~/DevOps
./rebuild-nginx-configs.sh
```

### Adding Worker Containers

Workers don't bind to ports, so you can add multiple without conflicts:

```bash
docker run -d \
  --name app_worker_2 \
  --network host \
  --env-file /path/to/.env.production \
  --restart unless-stopped \
  app:latest \
  bundle exec sidekiq
```

### Port Allocation Best Practices

1. **Reserve 10 ports** per application (allows scaling to 10 web containers)
2. **Base ports** should be multiples of 10 for clarity
3. **Document allocations** in this file when adding applications
4. **Check for conflicts** before allocating: `lsof -i :3020`

### Container Management Commands

```bash
# List all containers for an app
docker ps --filter 'name=app-name'

# View container logs
docker logs -f app_web_1

# Restart a container
docker restart app_web_1

# Stop and remove container
docker stop app_web_1 && docker rm app_web_1

# Check container network mode
docker inspect app_web_1 --format='NetworkMode={{.HostConfig.NetworkMode}}'
# Should output: host

# Check container environment
docker exec app_web_1 env | grep DATABASE_URL
```

---

## Deployment Procedures

### Standard Deployment Workflow

Each application has a `deploy.sh` script with standardized commands:

```bash
cd ~/DevOps/apps/{app-name}
./deploy.sh deploy          # Deploy latest code
./deploy.sh restart         # Restart with current image
./deploy.sh stop            # Stop all containers
./deploy.sh scale <N>       # Scale web containers (1-10)
./deploy.sh status          # Show container status
./deploy.sh logs [name]     # View logs
./deploy.sh console         # Rails console (Rails only)
./deploy.sh help            # Show all commands
```

### Deployment Steps (Automated)

**For Rails Applications:**
1. Pull latest code from GitHub
2. Build Docker image with timestamp tag
3. Backup database (if migrations exist)
4. Run database migrations
5. Perform rolling restart (or fresh deployment)
6. Health check each container
7. Update nginx upstream if scaling changed
8. Check SSL certificates (auto-obtain if missing)
9. Cleanup old Docker images
10. Log deployment with SSL status
11. Send email notification (success/failure)

**For Next.js Applications:**
1. Pull latest code from GitHub
2. Build Docker image (includes Next.js build)
3. Perform rolling restart
4. Health check each container
5. Update nginx configuration
6. Check SSL certificates
7. Cleanup old Docker images
8. Log deployment
9. Send email notification

### Zero-Downtime Rolling Restart

**How It Works:**
1. Start new containers with new image
2. Wait for health check to pass
3. Stop old containers one by one
4. Remove old containers
5. If any step fails, rollback automatically

**Example (3 web containers):**
```
Existing: web_1, web_2, web_3 (old image)

1. Start web_1_new with new image
2. Health check web_1_new → OK
3. Stop web_1 (old)
4. Remove web_1 (old)
5. Rename web_1_new → web_1

Repeat for web_2, web_3...

Result: No downtime, all containers updated
```

### Scaling Operations

**Scale Up (add containers):**
```bash
cd ~/DevOps/apps/{app-name}
./deploy.sh scale 5  # Scale to 5 web containers
```

**What Happens:**
1. Determine new container count
2. Start additional containers with new ports
3. Wait for health checks
4. Update nginx upstream configuration
5. Reload nginx
6. Verify all containers healthy

**Scale Down (remove containers):**
```bash
./deploy.sh scale 2  # Scale to 2 web containers
```

**What Happens:**
1. Determine containers to remove
2. Stop excess containers gracefully
3. Remove stopped containers
4. Update nginx upstream configuration
5. Reload nginx
6. Verify remaining containers healthy

### Deployment Verification

**After Each Deployment:**
```bash
# 1. Check container status
docker ps --filter 'name=app-name'

# 2. Check health endpoints
curl https://your-domain.com/up

# 3. View logs
docker logs -f app_web_1

# 4. Verify nginx configuration
sudo nginx -t

# 5. Test application functionality
# (upload file, make API call, etc.)
```

---

## Performance Optimization

### 1. Docker Build Optimization

**Problem Solved:** Builds taking 10+ minutes, stuck in "D" state (uninterruptible I/O)

**Root Causes:**
- Recursive `chown -R` and `chmod -R` operations on entire `/app` directory
- Overlay2 filesystem with 25+ layers causing I/O amplification
- Excessive build cache (25GB+)
- RAID storage compounds overlay2 issues

**Solutions Implemented:**

#### Dockerfile Optimizations
```dockerfile
# ❌ BEFORE (SLOW - 10+ minutes)
COPY --from=builder /app ./
RUN chown -R app:app /app && \     # Recursive on thousands of files
    chmod -R 755 /app

# ✅ AFTER (FAST - <5 seconds)
COPY --from=builder --chown=app:app /app ./  # Set ownership during COPY
RUN mkdir -p tmp/pids tmp/cache tmp/sockets log && \
    chown app:app tmp tmp/pids tmp/cache tmp/sockets log && \  # Specific paths only
    chmod 755 tmp/pids tmp/cache tmp/sockets && \
    chmod 777 log
```

**Result:** 2000x improvement (10+ min → <5 sec)

#### Docker Cleanup
```bash
# Regular cleanup (weekly recommended)
docker system prune -f
docker builder prune -f --filter until=168h

# Check disk usage
docker system df -v

# Monitor overlay2 growth
sudo du -sh /var/lib/docker/overlay2
sudo find /var/lib/docker/overlay2 -maxdepth 1 -type d | wc -l
```

**Expected Results After Cleanup:**
- ~12GB reclaimed from dangling images
- ~10GB+ reclaimed from build cache
- Overlay2 layers reduced from 435 to active images only
- 25% disk usage (from 100% before optimization)

### 2. Database Performance

**Query Optimization Example:**

**Problem:** DISTINCT ON queries on large tables taking 60+ seconds

**Solution:** Add appropriate indexes
```sql
CREATE INDEX CONCURRENTLY index_online_pharmacy_drugs_on_name
  ON online_pharmacy_drugs(name);

CREATE INDEX CONCURRENTLY index_online_pharmacy_drugs_on_pharmacy_and_name
  ON online_pharmacy_drugs(online_pharmacy_id, name);
```

**Result:** Query time reduced from 60+ seconds to ~0.5ms (120,000x improvement)

**Best Practices:**
- Use EXPLAIN ANALYZE to identify slow queries
- Add indexes for columns used in WHERE, JOIN, ORDER BY
- Use CONCURRENTLY to avoid table locks during index creation
- Monitor query performance with pg_stat_statements

### 3. Redis Optimization

**Configuration for Streams workloads:**
```ini
# /etc/redis/redis.conf
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly yes               # AOF persistence
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

**Connection Pooling:**
```ruby
# config/initializers/redis.rb
Redis.new(
  url: ENV['REDIS_URL'],
  timeout: 5,
  reconnect_attempts: 3
)
```

### 4. Nginx Optimization

**Caching Configuration:**
```nginx
# Static assets - 365 days
location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2)$ {
    expires 365d;
    add_header Cache-Control "public, immutable";
}

# API responses - no cache
location / {
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    proxy_pass http://backend;
}
```

**Compression:**
```nginx
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_types text/plain text/css text/xml text/javascript
           application/json application/javascript
           application/xml+rss application/rss+xml;
```

---

## CDN & Active Storage

### Nginx-Based CDN

**Domain:** cdn.webet.pl
**Purpose:** Serve Active Storage files directly from nginx (bypassing Rails)

**Architecture:**
```
Before (Inefficient):
User → Nginx → Rails → Filesystem → Rails → Nginx → User
URL: https://api-public.brokik.com/rails/active_storage/blobs/{key}

After (Optimized):
User → Nginx → Filesystem → User
URL: https://cdn.webet.pl/brokik-api/blobs/{key}
```

**Performance Benefits:**
- Response Time: ~50-100ms → ~5-10ms (5-10x faster)
- Server Load: 90% reduction (nginx vs Rails)
- Concurrent Requests: 100x+ capacity

**File Structure:**
```
/var/storage/
├── brokik-api/
│   └── active_storage/
│       ├── XX/YY/{hash}  # Blob files
│       └── variants/     # Image variants
└── cheaperfordrug-api/
    └── active_storage/
        └── ...
```

**URL Pattern:**
```
https://cdn.webet.pl/{app-name}/blobs/{key}
https://cdn.webet.pl/{app-name}/variants/{key}
```

**Cache Headers:**
```
Cache-Control: public, immutable
Expires: {1 year from now}
Access-Control-Allow-Origin: *
```

**Configuration:**
```nginx
location ~* ^/([^/]+)/(blobs|variants)/(.+)$ {
    alias /var/storage/$1/active_storage/$3;
    expires 365d;
    add_header Cache-Control "public, immutable";
    add_header Access-Control-Allow-Origin "*";
}
```

### Active Storage Migration

**From Scaleway S3 to Local Storage:**

**Benefits:**
- No external dependencies
- No S3 storage fees
- Faster access (direct disk I/O)
- Simpler architecture
- Files persist across deployments

**Migration Script:**
```bash
cd ~/DevOps
./scripts/migrate-scaleway-to-local-storage.sh
```

**What It Does:**
1. Creates `/var/storage/{app-name}/active_storage/`
2. Downloads all files from Scaleway
3. Updates `.env.production` to use `host_disk` service
4. Backs up original configuration
5. Offers to restart application

**For New Applications:**
Just set in `.env.production`:
```bash
RAILS_ACTIVE_STORAGE_SERVICE=host_disk
ACTIVE_STORAGE_HOST_PATH=/var/storage/{app-name}/active_storage
```

Deployment scripts handle the rest automatically!

---

## Email Notifications

### SendGrid API Integration

**Why SendGrid?**
- Better deliverability than SMTP/sendmail
- Simple HTTPS API (works everywhere)
- Free tier: 100 emails/day
- Excellent reputation
- Easy monitoring via dashboard

**Architecture:**
```
┌─────────────────────────┐
│  email-notification.sh  │  (Orchestrator)
│  Public API Functions   │
└───────────┬─────────────┘
            │
    ┌───────┴────────┬──────────────┐
    ▼                ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ email-       │ │ sendgrid-    │ │ email-       │
│ templates.sh │ │ api.sh       │ │ config.sh    │
│ (Templates)  │ │ (Sender)     │ │ (Config)     │
└──────────────┘ └──────────────┘ └──────────────┘
```

**Configuration:**
```bash
# DevOps/common/email-config.sh
export DEPLOYMENT_EMAIL_ENABLED=true
export DEPLOYMENT_EMAIL_FROM="biuro@webet.pl"
export DEPLOYMENT_EMAIL_TO="andrzej@webet.pl"
export SENDGRID_API_KEY="SG.xxxxxxxxxxxxxxxxxxxx"
```

**Notification Types:**
- Deployment success (with git commit, container details)
- Deployment failure (with error details)
- Can easily add: backup complete, certificate expiry, etc.

**Email Templates:**
- Beautiful HTML emails with responsive design
- Plain text fallback
- Professional appearance

**Setup (3 Steps):**

1. **Get SendGrid API Key:**
   - Sign up at https://sendgrid.com
   - Settings > API Keys > Create API Key
   - Permission: "Mail Send - Full Access"
   - Copy the API key

2. **Configure:**
   ```bash
   # In email-config.sh
   export SENDGRID_API_KEY="SG.xxxxxxxxxxxxxxxxxxxx"
   ```

3. **Verify Sender Email:**
   - Settings > Sender Authentication
   - Verify biuro@webet.pl

**Test:**
```bash
cd ~/DevOps
./scripts/test-email-notification.sh
```

**Adding New Email Types:**

Step 1: Add template (email-templates.sh):
```bash
generate_backup_complete_email() {
    local app_name="$1"
    local backup_size="$2"

    export EMAIL_SUBJECT="Backup Complete: $app_name"
    export EMAIL_TEXT_BODY="Backup completed. Size: $backup_size"
    export EMAIL_HTML_BODY="<html>...</html>"
}
```

Step 2: Add public API (email-notification.sh):
```bash
send_backup_complete_email() {
    generate_backup_complete_email "$@"
    send_email_via_sendgrid \
        "$EMAIL_FROM" "$EMAIL_TO" \
        "$EMAIL_SUBJECT" "$EMAIL_TEXT_BODY" "$EMAIL_HTML_BODY"
}
```

Done! Call from any script: `send_backup_complete_email "app-name" "2.5GB"`

---

## Database & Redis

### PostgreSQL Setup

**Configuration for Docker Access:**
```ini
# /etc/postgresql/14/main/postgresql.conf
listen_addresses = '*'

# /etc/postgresql/14/main/pg_hba.conf
host    all    all    172.17.0.0/16    md5
```

**Per-Application Setup:**
```bash
# Create database and user
sudo -u postgres psql << EOF
CREATE USER app_user WITH PASSWORD 'secure_password';
CREATE DATABASE app_production OWNER app_user;
GRANT ALL PRIVILEGES ON DATABASE app_production TO app_user;
EOF
```

**Connection Testing:**
```bash
# From host
psql -h localhost -U app_user -d app_production

# From container
docker exec app_web_1 bash -c "cd /app && bundle exec rails runner 'puts ActiveRecord::Base.connection.active?'"
```

**Backup & Restore:**
```bash
# Backup
pg_dump -U app_user app_production | gzip > backup_$(date +%Y%m%d_%H%M%S).sql.gz

# Restore
gunzip -c backup.sql.gz | psql -U app_user app_production

# List backups
ls -lh ~/apps/{app-name}/backups/

# Automated backups (before migrations)
# Location: ~/apps/{app-name}/backups/
# Retention: 30 days
```

### Redis Setup

**Configuration:**
```ini
# /etc/redis/redis.conf
bind 0.0.0.0
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly yes
```

**Database Allocation:**
```
DB 0: Brokik API (test)
DB 1: CheaperForDrug Landing
DB 2: CheaperForDrug API
DB 3: Brokik API (production)
```

**Monitoring:**
```bash
# Check status
redis-cli ping

# Memory usage
redis-cli info memory

# Queue depth
redis-cli -n 2 LLEN queue:default

# Connected clients
redis-cli info clients
```

---

## Security & SSL

### Server Hardening

**SSH Configuration:**
- Custom port (2222, not default 22)
- Key-based authentication only
- Root login disabled
- Password authentication disabled
- Fail2ban installed

**Firewall (UFW):**
```bash
sudo ufw allow 2222/tcp  # SSH custom port
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

**Container Security:**
- Non-root user execution
- Read-only filesystem where possible
- No privileged containers
- Resource limits configured

### SSL/TLS Best Practices

**Configuration:**
- TLS 1.2 and 1.3 only (1.0, 1.1 disabled)
- Strong cipher suites
- HSTS headers (force HTTPS)
- Certificate auto-renewal

**Security Headers:**
```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
```

**Certificate Monitoring:**
```bash
# Check certificate expiry
sudo certbot certificates

# Test renewal
sudo certbot renew --dry-run

# View renewal timer
systemctl status certbot.timer
```

### Secrets Management

**Environment Variables:**
- Never commit `.env.production` to git
- Use strong, random secrets
- Rotate secrets periodically
- Restrict file permissions: `chmod 600 .env.production`

**Generate Secrets:**
```bash
# Rails secret key
rails secret

# Random password
openssl rand -base64 32

# Random string
LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
```

---

## Monitoring & Health Checks

### Container Health

**Health Check Endpoints:**
- Rails: `GET /up` (returns HTTP 200)
- Next.js: `GET /` (returns HTTP 200)

**Automated Health Checks:**
```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=40s \
  CMD curl -f http://localhost:${PORT}/up || exit 1
```

**Manual Health Checks:**
```bash
# Check all app containers
~/DevOps/apps/status.sh

# Verify all domains
~/DevOps/verify-domains.sh

# Test specific endpoint
curl -I https://api-public.cheaperfordrug.com/up

# Check container health
docker inspect app_web_1 | grep -A 10 Health
```

### Log Monitoring

**Container Logs:**
```bash
# Follow logs
docker logs -f app_web_1

# Last 100 lines
docker logs --tail 100 app_web_1

# With timestamps
docker logs -f --timestamps app_web_1
```

**Nginx Logs:**
```bash
# Access logs
sudo tail -f /var/log/nginx/access.log

# Error logs
sudo tail -f /var/log/nginx/error.log

# Application-specific
sudo tail -f /var/log/nginx/{app-name}-access.log
```

**Application Logs (Rails):**
```bash
# Production logs (mounted volume)
tail -f ~/apps/{app-name}/logs/production.log

# Inside container
docker exec app_web_1 tail -f /app/log/production.log

# Sidekiq logs (filtered)
tail -f ~/apps/{app-name}/logs/production.log | grep Sidekiq
```

**System Logs:**
```bash
# Nginx service
sudo journalctl -u nginx -f

# Docker service
sudo journalctl -u docker -f

# PostgreSQL
sudo journalctl -u postgresql -f

# Redis
sudo journalctl -u redis-server -f
```

### Performance Monitoring

**Resource Usage:**
```bash
# Container stats
docker stats

# Disk usage
df -h

# Memory usage
free -h

# CPU usage
top

# Network connections
sudo netstat -tlnp
```

**Database Performance:**
```bash
# Active connections
sudo -u postgres psql -c "SELECT COUNT(*) FROM pg_stat_activity;"

# Database sizes
sudo -u postgres psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datname LIKE '%production';"

# Slow queries (if pg_stat_statements enabled)
sudo -u postgres psql -d app_production -c "SELECT query, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"
```

**Redis Performance:**
```bash
# Stats
redis-cli info stats

# Memory usage
redis-cli info memory

# Slow log
redis-cli slowlog get 10
```

---

## Troubleshooting

### Common Issues

#### 1. Container Won't Start

**Symptoms:** Container exits immediately or fails to start

**Diagnosis:**
```bash
# Check container status
docker ps -a | grep app-name

# View logs
docker logs app_web_1

# Check if port is in use
sudo lsof -i :3020

# Check environment file
cat ~/apps/{app-name}/.env.production

# Verify image exists
docker images app-name
```

**Common Causes:**
- Port already in use (another container or process)
- Missing or incorrect environment variables
- Database connection failed
- Image not built or corrupted

**Solutions:**
```bash
# Free port
docker rm -f container-using-port

# Rebuild image
cd ~/DevOps/apps/{app-name}
./deploy.sh deploy

# Check database
sudo systemctl status postgresql
psql -h localhost -U app_user -d app_production
```

#### 2. Database Connection Errors

**Symptoms:** HTTP 500 errors, "Connection refused" in logs

**Diagnosis:**
```bash
# Verify DATABASE_URL uses localhost
docker exec app_web_1 env | grep DATABASE_URL
# Should show: postgresql://...@localhost/...

# Test connection from container
docker exec app_web_1 bash -c "cd /app && bundle exec rails runner 'puts ActiveRecord::Base.connection.active?'"

# Check PostgreSQL is running
sudo systemctl status postgresql

# Check PostgreSQL is listening
sudo netstat -tlnp | grep 5432
# Should show: 0.0.0.0:5432
```

**Solutions:**
```bash
# Fix postgresql.conf
sudo nano /etc/postgresql/14/main/postgresql.conf
# Set: listen_addresses = '*'

# Fix pg_hba.conf
sudo nano /etc/postgresql/14/main/pg_hba.conf
# Add: host    all    all    172.17.0.0/16    md5

# Restart PostgreSQL
sudo systemctl restart postgresql

# Update .env.production if needed
nano ~/apps/{app-name}/.env.production
# Fix DATABASE_URL

# Restart containers
cd ~/DevOps/apps/{app-name}
./deploy.sh restart
```

#### 3. Nginx Configuration Errors

**Symptoms:** 502 Bad Gateway, nginx fails to reload

**Diagnosis:**
```bash
# Test nginx configuration
sudo nginx -t

# Check nginx error logs
sudo tail -50 /var/log/nginx/error.log

# Check upstream servers
sudo netstat -tlnp | grep 3020

# Check container health
docker ps | grep app-name
curl http://localhost:3020/up
```

**Solutions:**
```bash
# Rebuild nginx configs
cd ~/DevOps
./rebuild-nginx-configs.sh

# If config is broken, restore from backup
sudo cp /tmp/nginx_backup_*/sites-available/* /etc/nginx/sites-available/

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

#### 4. SSL Certificate Issues

**Symptoms:** Certificate expired, SSL handshake failed

**Diagnosis:**
```bash
# Check certificate status
sudo certbot certificates

# Check DNS resolution
dig +short your-domain.com

# View certbot logs
sudo tail -50 /var/log/letsencrypt/letsencrypt.log
```

**Solutions:**
```bash
# Manual renewal
sudo certbot renew

# Force renewal
sudo certbot renew --force-renewal

# Obtain new certificate
sudo certbot --nginx -d your-domain.com

# Check renewal timer
systemctl status certbot.timer
```

#### 5. Out of Disk Space

**Symptoms:** Deployments fail, containers won't start

**Diagnosis:**
```bash
# Check disk usage
df -h

# Find large directories
du -sh /* | sort -h | tail -10

# Docker system usage
docker system df -v

# Overlay2 layers
sudo du -sh /var/lib/docker/overlay2
sudo find /var/lib/docker/overlay2 -maxdepth 1 -type d | wc -l
```

**Solutions:**
```bash
# Clean up Docker
docker system prune -a  # Remove all unused images
docker volume prune     # Remove unused volumes
docker builder prune -a # Remove build cache

# Clean up old backups
find ~/apps/*/backups -name "*.sql.gz" -mtime +30 -delete

# Clean up old Docker images
docker images | grep app-name | tail -n +21 | awk '{print $3}' | xargs docker rmi

# Run automated cleanup
cd ~/DevOps/scripts
./cleanup-all-apps.sh
```

#### 6. Application Performance Issues

**Symptoms:** Slow response times, high CPU/memory usage

**Diagnosis:**
```bash
# Check resource usage
docker stats

# Check database performance
sudo -u postgres psql -d app_production -c "SELECT * FROM pg_stat_activity WHERE state = 'active';"

# Check Redis queues
redis-cli -n 2 LLEN queue:default

# Check slow queries (if enabled)
sudo -u postgres psql -d app_production -c "SELECT query, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"
```

**Solutions:**
- Scale up web containers: `./deploy.sh scale 5`
- Add database indexes for slow queries
- Increase Sidekiq concurrency
- Add more worker containers
- Check for N+1 queries in logs
- Review and optimize slow endpoints

### Debug Commands

```bash
# Enter container shell
docker exec -it app_web_1 /bin/bash

# Check environment variables
docker exec app_web_1 env

# Check container processes
docker top app_web_1

# Check container network
docker inspect app_web_1 | grep -A 10 NetworkMode

# Test database from container
docker exec app_web_1 bash -c "cd /app && bundle exec rails runner 'puts ActiveRecord::Base.connection.active?'"

# Test Redis from container
docker exec app_web_1 bash -c "redis-cli -h localhost ping"

# Rails console
docker exec -it app_web_1 bash -c "cd /app && bundle exec rails console"
```

---

## Disaster Recovery

### Complete System Rebuild

**Purpose:** Rebuild entire server from scratch or restore to new server

**Script:** `scripts/disaster-recovery.sh`

**What It Does:**
1. Install basic dependencies (git, curl, wget)
2. Clone DevOps repository
3. Run ubuntu-init-setup.sh (system dependencies)
4. Setup each configured application
5. Deploy each application
6. Setup SSL certificates
7. Configure centralized cleanup
8. Verify deployment

**Recovery Time:** 30-60 minutes

**Configuration:**
```bash
# Copy and edit
cp scripts/disaster-recovery-config.example.sh scripts/disaster-recovery-config.sh
nano scripts/disaster-recovery-config.sh

# Configure:
RECOVERY_USER="andrzej"
RECOVERY_HOME="/home/andrzej"
DEVOPS_REPO_URL="git@github.com:username/DevOps.git"
APPS_TO_DEPLOY=(
    "cheaperfordrug-api"
    "cheaperfordrug-landing"
    "cheaperfordrug-web"
)
```

**Usage:**
```bash
cd ~/DevOps/scripts
./disaster-recovery.sh disaster-recovery-config.sh
```

### Backup Strategy

**What to Backup:**

1. **Environment Files** (critical)
   - All `.env.production` files
   - Contains secrets, API keys, passwords
   - Backup off-server securely

2. **PostgreSQL Databases**
   - Automated daily backups (before migrations)
   - Location: `~/apps/{app-name}/backups/`
   - Retention: 30 days
   - Format: compressed `.sql.gz`

3. **SSL Certificates**
   - Managed by certbot (auto-restored)
   - Can be backed up from `/etc/letsencrypt/`

4. **Git Repositories**
   - DevOps repository (GitHub)
   - Application repositories (GitHub)
   - Configuration in git

5. **Active Storage Files**
   - Location: `/var/storage/{app-name}/active_storage/`
   - Include in server backups

**Backup Commands:**
```bash
# Backup database
pg_dump -U app_user app_production | gzip > backup_$(date +%Y%m%d).sql.gz

# Backup all env files
tar -czf env-backup_$(date +%Y%m%d).tar.gz ~/apps/*/.env.production

# Backup nginx configs
sudo tar -czf nginx-backup_$(date +%Y%m%d).tar.gz /etc/nginx/sites-available /etc/nginx/sites-enabled

# Backup Active Storage files
tar -czf storage-backup_$(date +%Y%m%d).tar.gz /var/storage/
```

### Rollback Procedures

**Rollback to Previous Image:**
```bash
# List available images
docker images app-name

# Stop current containers
cd ~/DevOps/apps/{app-name}
./deploy.sh stop

# Start with previous image
docker run -d --name app_web_1 \
  --network host \
  --env-file .env.production \
  -e PORT=3020 \
  app-name:20251114_120000  # Previous timestamp

# Update nginx
./rebuild-nginx-configs.sh
```

**Rollback Database Migration:**
```bash
# Access Rails console
docker exec -it app_web_1 bash
cd /app
bundle exec rails console

# Rollback last migration
ActiveRecord::Base.connection.migration_context.down(1)

# Or use rake
bundle exec rake db:rollback STEP=1
```

**Restore Database from Backup:**
```bash
cd ~/apps/{app-name}/backups

# List backups
ls -lh

# Restore specific backup
gunzip -c backup_20251114_120000.sql.gz | psql -U app_user app_production
```

---

## Quick Reference

### Common Commands

```bash
# ═══════════════════════════════════════════════════════════
# DEPLOYMENT
# ═══════════════════════════════════════════════════════════

# Deploy application
cd ~/DevOps/apps/{app-name} && ./deploy.sh deploy

# Restart application
./deploy.sh restart

# Scale web containers
./deploy.sh scale 5

# Check status
./deploy.sh status

# View logs
./deploy.sh logs web_1

# Rails console (Rails apps only)
./deploy.sh console

# ═══════════════════════════════════════════════════════════
# NGINX
# ═══════════════════════════════════════════════════════════

# Rebuild all nginx configs
cd ~/DevOps && ./rebuild-nginx-configs.sh

# Test nginx configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# View nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# ═══════════════════════════════════════════════════════════
# SSL CERTIFICATES
# ═══════════════════════════════════════════════════════════

# Check certificate status
sudo certbot certificates

# Renew certificates
sudo certbot renew

# View renewal timer
systemctl status certbot.timer

# ═══════════════════════════════════════════════════════════
# DOCKER
# ═══════════════════════════════════════════════════════════

# List containers
docker ps --filter 'name=app-name'

# View logs
docker logs -f app_web_1

# Restart container
docker restart app_web_1

# Remove container
docker stop app_web_1 && docker rm app_web_1

# Clean up Docker
docker system prune -a
docker volume prune
docker builder prune -a

# ═══════════════════════════════════════════════════════════
# DATABASE
# ═══════════════════════════════════════════════════════════

# Connect to database
psql -h localhost -U app_user -d app_production

# Backup database
pg_dump -U app_user app_production | gzip > backup.sql.gz

# Restore database
gunzip -c backup.sql.gz | psql -U app_user app_production

# Check database size
sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('app_production'));"

# ═══════════════════════════════════════════════════════════
# REDIS
# ═══════════════════════════════════════════════════════════

# Check Redis status
redis-cli ping

# Check queue depth
redis-cli -n 2 LLEN queue:default

# Memory usage
redis-cli info memory

# Connected clients
redis-cli info clients

# ═══════════════════════════════════════════════════════════
# MONITORING
# ═══════════════════════════════════════════════════════════

# Check all apps status
~/DevOps/apps/status.sh

# Verify all domains
~/DevOps/verify-domains.sh

# Check disk usage
df -h

# Check memory usage
free -h

# Container stats
docker stats

# System logs
sudo journalctl -u nginx -f
sudo journalctl -u postgresql -f
sudo journalctl -u redis-server -f

# ═══════════════════════════════════════════════════════════
# SCRAPER SYSTEM
# ═══════════════════════════════════════════════════════════

# Restart scraper system
cd ~/apps/cheaperfordrug-scraper
docker-compose restart

# View scraper logs
docker-compose logs -f scraper-vpn-poland
docker-compose logs -f product-update-worker-poland-1

# Check scraper status
docker-compose ps
```

### Port Allocation

```
Application                 Port Range    Containers
──────────────────────────────────────────────────────
Brokik API                  3040-3041     2 web
Brokik Web                  3050-3052     3 web
CheaperForDrug Landing      3010-3011     2 web
CheaperForDrug Web          3030-3032     3 web
CheaperForDrug API          3020-3022     3 web
──────────────────────────────────────────────────────
Reserved                    3060-3099     Future
```

### Service URLs

```
Service                 Primary URL                        Alternative URLs
──────────────────────────────────────────────────────────────────────────────────
Brokik API              api-public.brokik.com              api-internal.brokik.com
Brokik Web              www.brokik.com                     -
CFD Landing             taniejpolek.pl                     presale.taniejpolek.pl, www.taniejpolek.pl
CFD Web                 premiera.taniejpolek.pl            www.premiera.taniejpolek.pl
CFD API                 api-public.cheaperfordrug.com      api-internal.cheaperfordrug.com
CDN                     cdn.webet.pl                       -
```

### Database Allocation

```
Database Name                          Application              Redis DB
──────────────────────────────────────────────────────────────────────────
brokik_production                      Brokik API               3
cheaperfordrug_landing_production      CFD Landing              1
cheaperfordrug_production              CFD API                  2
```

---

## Repository Structure

```
DevOps/
├── apps/                              # Application-specific configurations
│   ├── brokik-api/                    # Brokik API (Rails)
│   ├── brokik-web/                    # Brokik Web (Next.js)
│   ├── cheaperfordrug-api/            # CheaperForDrug API (Rails)
│   ├── cheaperfordrug-landing/        # CheaperForDrug Landing (Rails)
│   ├── cheaperfordrug-web/            # CheaperForDrug Web (Next.js)
│   └── status.sh                      # Multi-app status checker
│
├── common/                            # Shared utilities and modules
│   ├── app-types/                     # Application type modules
│   │   ├── nextjs.sh                  # Next.js deployment logic
│   │   └── rails.sh                   # Rails deployment logic
│   ├── nginx/                         # Nginx configurations
│   │   ├── cdn.conf                   # CDN configuration
│   │   └── default-server.conf        # Default catch-all server
│   ├── nextjs/                        # Next.js templates
│   ├── rails/                         # Rails templates
│   ├── templates/                     # Configuration templates
│   ├── deploy-app.sh                  # Generic deployment workflow
│   ├── docker-utils.sh                # Docker container management
│   ├── email-config.sh                # Email configuration
│   ├── email-notification.sh          # Email notification system
│   ├── email-templates.sh             # Email templates
│   ├── redis-setup.sh                 # Redis configuration utilities
│   ├── sendgrid-api.sh                # SendGrid API sender
│   ├── setup-app.sh                   # Generic application setup
│   └── utils.sh                       # Common utility functions
│
├── scripts/                           # System-wide utilities
│   ├── cleanup-all-apps.sh            # Centralized cleanup
│   ├── deploy-cdn.sh                  # CDN deployment
│   ├── disaster-recovery.sh           # Complete system rebuild
│   ├── docker-build-benchmark.sh      # Build performance testing
│   ├── docker-cleanup-optimization.sh # Docker cleanup
│   ├── migrate-scaleway-to-local-...  # Active Storage migration
│   ├── test-email-notification.sh     # Email system testing
│   ├── update-redis.sh                # Redis upgrade utility
│   └── upgrade-ruby.sh                # Ruby version upgrade
│
├── templates/                         # Application templates
│   ├── nextjs-app/                    # Next.js app template
│   └── rails-app/                     # Rails app template
│
├── rebuild-nginx-configs.sh           # Rebuild all nginx configs
├── ubuntu-init-setup.sh               # Complete Ubuntu server init
├── verify-domains.sh                  # Domain and SSL verification
└── README.md                          # This file
```

---

## Support & Maintenance

### Getting Help

**Log Files:**
- Server init: `/var/log/server-init-setup.log`
- Nginx errors: `/var/log/nginx/error.log`
- Container logs: `docker logs {container-name}`
- Deployment logs: `~/apps/{app-name}/logs/deployments.log`

**Useful Commands:**
```bash
# System status
sudo systemctl status

# Container status
docker ps -a

# Disk space
df -h

# Memory usage
free -h

# Network connections
sudo netstat -tlnp

# Recent system logs
sudo journalctl -n 100
```

### Regular Maintenance

**Daily:**
- Monitor container health: `~/DevOps/apps/status.sh`
- Check disk usage: `df -h`
- Review error logs: `sudo tail -100 /var/log/nginx/error.log`

**Weekly:**
- Clean up Docker: `docker system prune -f`
- Review database sizes
- Check SSL certificate expiry: `sudo certbot certificates`

**Monthly:**
- Update system packages: `sudo apt update && sudo apt upgrade`
- Review and rotate logs
- Test disaster recovery procedure
- Review and update documentation

**Quarterly:**
- Review security practices
- Update Docker base images
- Review and optimize database indexes
- Review application performance metrics

### Automated Maintenance

**Centralized Cleanup (Daily at 2 AM):**
```bash
# Configured in crontab
0 2 * * * /home/andrzej/DevOps/scripts/cleanup-all-apps.sh
```

**What It Cleans:**
- Old Docker images (keeps last 20)
- Old image backups (keeps last 20)
- Old database backups (keeps 30 days)
- Docker build cache (keeps last 24 hours)

---

## Best Practices

### Security
- Use custom SSH port (not 22)
- Disable password authentication (SSH keys only)
- Enable UFW firewall (only necessary ports open)
- Use strong, random secrets (rotate periodically)
- Keep system and dependencies updated
- Monitor logs for suspicious activity
- Use HTTPS only (HSTS enabled)

### Performance
- Scale web containers based on traffic
- Monitor and optimize database queries
- Use appropriate indexes
- Configure Redis maxmemory policy
- Enable nginx caching for static assets
- Use CDN for Active Storage files
- Monitor resource usage (CPU, memory, disk)

### Operational
- Regular status checks (`~/DevOps/apps/status.sh`)
- Monitor logs during deployments
- Test in staging before production
- Have rollback plan ready
- Document configuration changes
- Maintain backup strategy (test restores)
- Keep documentation current

### Development Workflow
- Use feature branches
- Pull request reviews
- Tag releases
- Test before deployment
- Use deployment notifications
- Keep DevOps repo in sync

---

## Summary

This DevOps repository provides a **comprehensive, production-ready infrastructure** for deploying and managing multiple Rails and Next.js applications on Ubuntu servers.

**Key Capabilities:**
- Automated server setup from scratch
- Multi-application deployment with zero downtime
- Fully automated SSL certificate management
- Container orchestration with health checks
- Load balancing with nginx
- Performance optimization (Docker builds, database queries)
- CDN integration for file serving
- VPN-enabled scraper system
- Email notifications for deployments
- Complete disaster recovery capability

**Infrastructure Highlights:**
- 24 active containers (13 web, 2 workers, 1 scheduler, 8 scrapers)
- 5 applications (3 Rails, 2 Next.js)
- PostgreSQL with 3 databases
- Redis with 4 database namespaces
- Nginx load balancing
- Let's Encrypt SSL (auto-renewal)
- SendGrid email notifications
- AWS Elasticsearch integration

**Production Stats:**
- **Uptime:** 99.9%+ with automated health checks
- **Build Performance:** 2000x improvement (10+ min → <5 sec)
- **Query Performance:** 120,000x improvement (60s → 0.5ms)
- **SSL:** Fully automated (no manual commands)
- **Deployments:** Zero-downtime rolling updates

The modular design allows easy addition of new applications and supports both fresh deployments and updates to existing infrastructure.

---

**Version:** 3.0.0
**Last Updated:** 2025-11-14
**Server:** hetzner-andrzej (65.109.22.232:2222)
**Maintained By:** DevOps Team

For production use, follow the best practices outlined in this README, maintain regular backups, monitor your applications continuously, and keep documentation up to date.
