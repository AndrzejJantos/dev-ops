# Services Documentation - Production Environment

**Server:** hetzner-andrzej (65.109.22.232)
**Last Updated:** 2025-11-14
**Total Containers:** 24 (13 web, 2 workers, 1 scheduler, 8 scrapers)

---

## Table of Contents

1. [Infrastructure Overview](#infrastructure-overview)
2. [Application Services](#application-services)
3. [Scraper System](#scraper-system)
4. [Network Architecture](#network-architecture)
5. [Service Dependencies](#service-dependencies)
6. [Monitoring & Health Checks](#monitoring--health-checks)
7. [Deployment Procedures](#deployment-procedures)
8. [Troubleshooting](#troubleshooting)

---

## Infrastructure Overview

### Server Specifications
- **Provider:** Hetzner
- **IP Address:** 65.109.22.232
- **OS:** Ubuntu (with Docker)
- **Storage:** RAID md2 (436GB, 25% usage after optimization)
- **Docker Version:** Latest with overlay2 storage driver
- **Networking:** Host network mode for all containers

### Docker Optimization
- **Overlay layers:** Reduced from 435 to 332 (after cleanup)
- **Build performance:** Optimized from 10+ minutes to <5 seconds
- **Disk usage:** 25GB (freed 29GB through cleanup)
- **Build cache:** Properly managed with 24-hour retention

---

## Application Services

### 1. Brokik API (Rails API)

**Service Type:** Rails 3.4.5 API Backend
**Git Repository:** github.com:AndrzejJantos/brokik-api.git
**Current Commit:** 8c86ae0
**Image Tag:** brokik-api:20251114_155031

#### Container Architecture
```
brokik-api_web_1      [Port 3040 -> 3000]  - Web container #1
brokik-api_web_2      [Port 3041 -> 3000]  - Web container #2
brokik-api_worker_1   [No exposed port]     - Sidekiq worker
brokik-api_scheduler  [No exposed port]     - Clockwork scheduler
```

#### Configuration
- **Location:** ~/DevOps/apps/brokik-api
- **Deployed App:** ~/apps/brokik-api
- **Web Containers:** 2 instances
- **Worker Containers:** 1 instance (Sidekiq)
- **Scheduler:** Enabled (Clockwork)
- **Database:** brokik_production (PostgreSQL)
- **Redis DB:** 3

#### Domains & SSL
- **Primary:** https://api-public.brokik.com
- **Internal:** https://api-internal.brokik.com
- **SSL Certificate:** Valid for 75 days
- **Health Endpoint:** /up (returns HTTP 301 - redirect configured)

#### Deployment Info
- **Deployment Time:** ~2 minutes
- **Build Time:** <5 seconds (optimized)
- **Zero Downtime:** Enabled
- **Image Backups:** 6 available
- **Database Backups:** Available

#### Key Features
- Background job processing (Sidekiq)
- Scheduled tasks (Clockwork)
- Multi-tenant support
- Active Storage integration

---

### 2. Brokik Web (Next.js Frontend)

**Service Type:** Next.js Frontend (Pages Router)
**Git Repository:** github.com:AndrzejJantos/brokik-web.git
**Current Commit:** deb8a9f
**Image Tag:** brokik-web:20251114_155251

#### Container Architecture
```
brokik-web_web_1  [Port 3050 -> 3000]  - Next.js instance #1
brokik-web_web_2  [Port 3051 -> 3000]  - Next.js instance #2
brokik-web_web_3  [Port 3052 -> 3000]  - Next.js instance #3
```

#### Configuration
- **Location:** ~/DevOps/apps/brokik-web
- **Deployed App:** ~/apps/brokik-web
- **Web Containers:** 3 instances
- **Worker Containers:** None
- **Node Version:** Latest LTS

#### Domains & SSL
- **Primary:** https://www.brokik.com
- **SSL Certificate:** Valid for 75 days
- **Health Endpoint:** /up (returns HTTP 307 - redirect configured)

#### Deployment Info
- **Deployment Time:** ~1.5 minutes
- **Build Time:** <5 seconds (optimized)
- **Image Backups:** 5 available

#### API Integration
- **Backend:** Brokik API (api-public.brokik.com)
- **Authentication:** JWT (devise-jwt)
- **API Client:** Axios with service layer pattern

---

### 3. CheaperForDrug Landing (Rails)

**Service Type:** Rails 3.4.5 Marketing/Landing Page
**Git Repository:** github.com:AndrzejJantos/cheaperfordrug-landing.git
**Current Commit:** d17f6dc
**Image Tag:** cheaperfordrug-landing:20251114_155424

#### Container Architecture
```
cheaperfordrug-landing_web_1  [Port 3010 -> 3000]  - Web container #1
cheaperfordrug-landing_web_2  [Port 3011 -> 3000]  - Web container #2
```

#### Configuration
- **Location:** ~/DevOps/apps/cheaperfordrug-landing
- **Deployed App:** ~/apps/cheaperfordrug-landing
- **Web Containers:** 2 instances
- **Worker Containers:** 0 (no background jobs)
- **Scheduler:** Disabled
- **Database:** cheaperfordrug_landing_production
- **Redis DB:** 1

#### Domains & SSL
- **Primary:** https://taniejpolek.pl
- **Internal:** https://presale.taniejpolek.pl
- **Alternative:** https://www.taniejpolek.pl
- **SSL Certificate:** Valid for 74 days
- **Health Endpoint:** /up (returns HTTP 301 - redirect configured)

#### Deployment Info
- **Deployment Time:** ~2 minutes
- **Build Time:** ~13 seconds (asset precompilation)
- **Image Backups:** 4 available
- **Database Backups:** 0 (landing page, minimal data)

#### Key Features
- Marketing landing page
- Lead capture forms
- SendGrid email integration
- Google Analytics & Tag Manager
- Facebook Pixel tracking

---

### 4. CheaperForDrug Web (Next.js Frontend)

**Service Type:** Next.js Frontend Application
**Git Repository:** github.com:AndrzejJantos/cheaperfordrug-web.git
**Current Commit:** 848e6c1
**Image Tag:** cheaperfordrug-web:20251114_155624

#### Container Architecture
```
cheaperfordrug-web_web_1  [Port 3030 -> 3000]  - Next.js instance #1
cheaperfordrug-web_web_2  [Port 3031 -> 3000]  - Next.js instance #2
cheaperfordrug-web_web_3  [Port 3032 -> 3000]  - Next.js instance #3
```

#### Configuration
- **Location:** ~/DevOps/apps/cheaperfordrug-web
- **Deployed App:** ~/apps/cheaperfordrug-web
- **Web Containers:** 3 instances
- **Worker Containers:** None

#### Domains & SSL
- **Primary:** https://premiera.taniejpolek.pl
- **Alternative:** https://www.premiera.taniejpolek.pl
- **SSL Certificate:** Valid
- **Health Endpoint:** / (returns HTTP 200 - healthy)

#### Deployment Info
- **Deployment Time:** ~2.5 minutes
- **Build Time:** ~35 seconds (Next.js build)
- **Image Backups:** 4 available

#### API Integration
- **Backend:** CheaperForDrug API (api-public.cheaperfordrug.com)
- **Authentication:** JWT
- **Search:** Elasticsearch integration
- **UI Framework:** Material-UI with custom theming

---

### 5. CheaperForDrug API (Rails API)

**Service Type:** Rails 3.4.5 API Backend with Elasticsearch
**Git Repository:** github.com:AndrzejJantos/cheaperfordrug-api.git
**Current Commit:** 3aeeb02
**Image Tag:** cheaperfordrug-api:20251114_155908

#### Container Architecture
```
cheaperfordrug-api_web_1     [Port 3020 -> 3000]  - Web container #1
cheaperfordrug-api_web_2     [Port 3021 -> 3000]  - Web container #2
cheaperfordrug-api_web_3     [Port 3022 -> 3000]  - Web container #3
cheaperfordrug-api_worker_1  [No exposed port]    - Sidekiq worker
```

**Note:** Scheduler is DISABLED (no recurring tasks configured)
**Note:** Read/write containers REMOVED as requested

#### Configuration
- **Location:** ~/DevOps/apps/cheaperfordrug-api
- **Deployed App:** ~/apps/cheaperfordrug-api
- **Web Containers:** 3 instances (as requested)
- **Worker Containers:** 1 instance (Sidekiq)
- **Scheduler:** Disabled (SCHEDULER_ENABLED=false)
- **Database:** cheaperfordrug_production
- **Redis DB:** 2
- **Elasticsearch:** Enabled (AWS provider)

#### Domains & SSL
- **Primary:** https://api-public.cheaperfordrug.com
- **Internal:** https://api-internal.cheaperfordrug.com
- **SSL Certificate:** Valid for 71 days
- **Health Endpoint:** /up (returns HTTP 200 - healthy)

#### Deployment Info
- **Deployment Time:** ~2 minutes
- **Build Time:** ~7 seconds (optimized)
- **Image Backups:** 7 available
- **Database Backups:** 232 available

#### Key Features
- Drug database with Searchkick/Elasticsearch
- Pharmacy price comparison
- Background job processing for:
  - Email notifications
  - Data processing
  - External API calls
- Multi-country support (Poland, Germany, Czech)
- Active Storage for file uploads

#### Scraper Integration

**API Endpoint for Scrapers:**
- **Port:** 4200 (HTTP, internal only)
- **Access:** Via Nginx reverse proxy (api-scraper-local)
- **Backend:** Load balanced across all 3 web containers (ports 3020-3022)
- **URL:** http://api-scraper.localtest.me:4200 (resolves to localhost)

**Configuration:**
- All 3 web containers serve BOTH public API (via HTTPS) AND scraper API (via port 4200)
- Nginx load balances scraper requests using `least_conn` algorithm
- No dedicated scraper containers within API - web containers handle all requests

**Nginx Upstream Configuration:**
```nginx
upstream api_scraper_local_backend {
    least_conn;
    server 127.0.0.1:3020;  # cheaperfordrug-api_web_1
    server 127.0.0.1:3021;  # cheaperfordrug-api_web_2
    server 127.0.0.1:3022;  # cheaperfordrug-api_web_3
}
```

**Data Processing:**
- Receives scraped pharmacy product data from worker containers
- Processes and validates drug information
- Maintains drug name groupings and variants
- Handles multi-country drug information
- Updates Elasticsearch indexes

---

## Scraper System

**Location:** ~/apps/cheaperfordrug-scraper
**Docker Compose:** docker-compose.yml
**Image:** scraper-vpn:latest (2.19GB)
**Total Containers:** 8 (3 VPN + 5 workers)

### Architecture Overview

The scraper system consists of two types of containers:
1. **VPN Scrapers (3)** - Scrape pharmacy websites with NordVPN rotation
2. **Product Update Workers (5)** - Call the CheaperForDrug API to update product data

**Connection Flow:**
```
VPN Scrapers → Scrape pharmacy websites → Store data locally
                                               ↓
Product Update Workers → Read local data → HTTP POST to api-scraper.localtest.me:4200
                                               ↓
                              Nginx (port 4200) → Load balance
                                               ↓
                    CheaperForDrug API (3 web containers: 3020, 3021, 3022)
                                               ↓
                         PostgreSQL + Elasticsearch
```

---

### VPN Scraper Containers (3 total)

All VPN scrapers use **NordVPN** with automatic rotation.

#### 1. Poland VPN Scraper
```
Container Name: scraper-vpn-poland
Status: Running (healthy)
Country: Poland
VPN Provider: NordVPN
VPN Rotation: Every 5 minutes
Timezone: Europe/Warsaw
Resources: 2 CPU cores, 6GB RAM
Health Check: nordvpn status (every 60s)
```

**Startup Sequence:**
1. Container starts (immediate)
2. Connects to NordVPN Poland endpoint (~30s)
3. Verifies VPN connection
4. Begins scraping Polish pharmacies

**Scraping Schedule:**
- **Continuous operation** with 5-minute VPN rotation
- No cron schedule - runs persistently
- Scrapes Polish pharmacies:
  - Gemini
  - DOZ
  - WaptekaPL
  - i-Apteka
  - ZikoApteka
  - SuperPharm
  - Melissa

**Data Flow:**
1. Connect to NordVPN (Poland endpoint)
2. Scrape pharmacy websites via VPN
3. Store raw scraped data in `/app/scraper/outputs/`
4. Rotate VPN connection every 5 minutes
5. Repeat continuously

#### 2. Germany VPN Scraper
```
Container Name: scraper-vpn-germany
Status: Running (healthy)
Country: Germany
VPN Provider: NordVPN
VPN Rotation: Every 5 minutes
Timezone: Europe/Berlin
Resources: 2 CPU cores, 6GB RAM
Health Check: nordvpn status (every 60s)
```

**Startup Sequence:**
1. Container starts (immediate)
2. Connects to NordVPN Germany endpoint (~30s)
3. Verifies VPN connection
4. Ready for German pharmacy scraping (when configured)

**Scraping Schedule:**
- **Continuous operation** with 5-minute VPN rotation
- Currently standby (German pharmacies not yet configured)

#### 3. Czech Republic VPN Scraper
```
Container Name: scraper-vpn-czech
Status: Running (healthy)
Country: Czech Republic
VPN Provider: NordVPN
VPN Rotation: Every 5 minutes
Timezone: Europe/Prague
Resources: 2 CPU cores, 6GB RAM
Health Check: nordvpn status (every 60s)
```

**Startup Sequence:**
1. Container starts (immediate)
2. Connects to NordVPN Czech endpoint (~30s)
3. Verifies VPN connection
4. Ready for Czech pharmacy scraping (when configured)

**Scraping Schedule:**
- **Continuous operation** with 5-minute VPN rotation
- Currently standby (Czech pharmacies not yet configured)

---

### Product Update Workers (5 total)

All workers connect to **Poland VPN** and call the CheaperForDrug API.

**Common Configuration:**
- **VPN Country:** Poland
- **VPN Rotation:** Every 15 minutes (longer interval than scrapers)
- **API Endpoint:** http://api-scraper.localtest.me:4200
- **API Authentication:** Token-based (SCRAPER_AUTH_TOKEN)
- **Timezone:** Europe/Warsaw
- **Resources:** 2 CPU cores, 6GB RAM each
- **Concurrency:** 20 concurrent scrapers per worker
- **Poll Interval:** 1000ms (1 second)
- **Batch Size:** 20 items per batch

#### Startup Timing & Offset Schedule

Workers start with **staggered delays** to prevent API overload:

```
Worker 1 (product-update-worker-poland-1):
  ├─ VPN Connection Wait: 30 seconds
  ├─ Additional Offset: 0ms
  └─ Total Startup Time: 30.0 seconds

Worker 2 (product-update-worker-poland-2):
  ├─ VPN Connection Wait: 30 seconds
  ├─ Additional Offset: 200ms
  └─ Total Startup Time: 30.2 seconds

Worker 3 (product-update-worker-poland-3):
  ├─ VPN Connection Wait: 30 seconds
  ├─ Additional Offset: 400ms
  └─ Total Startup Time: 30.4 seconds

Worker 4 (product-update-worker-poland-4):
  ├─ VPN Connection Wait: 30 seconds
  ├─ Additional Offset: 600ms
  └─ Total Startup Time: 30.6 seconds

Worker 5 (product-update-worker-poland-5):
  ├─ VPN Connection Wait: 30 seconds
  ├─ Additional Offset: 800ms
  └─ Total Startup Time: 30.8 seconds
```

**Startup Command Example (Worker 2):**
```bash
sh -c "
  echo 'Waiting for VPN connection...'
  sleep 30
  echo 'Waiting 200ms offset...'
  sleep 0.2
  echo 'Starting Product Update Worker 2...'
  cd /app/scraper
  exec node workers/poland/product_update_worker.js
"
```

**Worker Runtime Process:**
```javascript
// workers/poland/product_update_worker.js
1. Connect to Poland VPN
2. Poll API every 1 second for new jobs
3. Fetch batch of 20 products to update
4. Process each product (max 20 concurrent)
5. POST updates to api-scraper.localtest.me:4200
6. Repeat continuously
```

**Data Processing Flow:**
1. VPN scrapers write data to `/app/scraper/outputs/`
2. Product update workers read from shared volume
3. Workers poll for pending updates (1-second interval)
4. Batch processing (20 items at a time)
5. HTTP POST to CheaperForDrug API (port 4200)
6. API validates and stores in PostgreSQL
7. Elasticsearch indexes updated
8. Process repeats

---

### Scraper Orchestration & Scheduling

**No Cron Jobs - All containers run continuously**

#### VPN Scraper Schedule
- **Operation Mode:** Continuous/perpetual
- **VPN Rotation:** Automatic every 5 minutes
- **Restart Policy:** `unless-stopped`
- **No scheduled tasks** - scrapers run 24/7

#### Product Update Worker Schedule
- **Operation Mode:** Continuous polling (1-second interval)
- **VPN Rotation:** Automatic every 15 minutes
- **Startup:** Staggered with 200ms offsets
- **Restart Policy:** `unless-stopped`
- **No scheduled tasks** - workers poll API continuously

**Health Monitoring:**
- **VPN Health Checks:** `nordvpn status` every 60 seconds
- **Health Check Timeout:** 10 seconds
- **Health Check Retries:** 3 attempts
- **Startup Grace Period:** 60s (scrapers), 90s (workers)

**Container Restart Behavior:**
```
If container fails → Docker automatically restarts
If VPN disconnects → Health check fails → Container restarts
If health check fails 3 times → Container marked unhealthy → Restart triggered
```

**Deployment Method:**
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
```

**Volume Mounts (Shared Data):**
```
./outputs:/app/scraper/outputs     # Scraped data
./logs:/app/scraper/logs           # Application logs
./state:/app/scraper/state         # Worker state/checkpoints
.:/app/scraper:ro                  # Scraper code (read-only)
```

**Log Locations:**
- **Docker logs:** `~/apps/cheaperfordrug-scraper/docker-logs/[container-name]/`
- **Application logs:** `~/apps/cheaperfordrug-scraper/logs/`
- **VPN connection logs:** Inside Docker logs (stdout)
- **Worker processing logs:** `~/apps/cheaperfordrug-scraper/logs/workers/`

---

## Network Architecture

### Port Allocation

#### Web Services (Nginx Reverse Proxy)
```
Brokik API:               3040-3041  (2 containers)
Brokik Web:               3050-3052  (3 containers)
CheaperForDrug Landing:   3010-3011  (2 containers)
CheaperForDrug Web:       3030-3032  (3 containers)
CheaperForDrug API:       3020-3022  (3 containers)
```

#### Internal Services (No External Ports)
```
Brokik API Worker:              Sidekiq (Redis DB 3)
Brokik API Scheduler:           Clockwork
CheaperForDrug API Worker:      Sidekiq (Redis DB 2)
VPN Scrapers (3):               VPN connections only
Product Update Workers (5):     API calls to internal endpoint
```

### Nginx Configuration

All web traffic routes through Nginx reverse proxy:

```
HTTP (80) -> HTTPS redirect (301/307)
HTTPS (443) -> SSL termination -> Upstream containers
```

**Upstream Load Balancing:**
- Round-robin across container instances
- Health checks via /up endpoint
- Automatic failover on container failure

### SSL/TLS Configuration

**Certificate Provider:** Let's Encrypt
**Auto-renewal:** Enabled
**Certificate Locations:** /etc/letsencrypt/live/[domain]/

**Active Certificates:**
- api-public.brokik.com (expires 2026-01-29, 75 days remaining)
- www.brokik.com (expires 2026-01-29, 75 days remaining)
- taniejpolek.pl (expires 2026-01-28, 74 days remaining)
- premiera.taniejpolek.pl (valid)
- api-public.cheaperfordrug.com (expires 2026-01-25, 71 days remaining)

---

## Service Dependencies

### Database Dependencies

```
PostgreSQL Server (localhost:5432)
├── brokik_production                      -> Brokik API
├── cheaperfordrug_landing_production      -> CheaperForDrug Landing
└── cheaperfordrug_production              -> CheaperForDrug API
```

### Redis Dependencies

```
Redis Server (localhost:6379)
├── DB 1: CheaperForDrug Landing           -> Session storage
├── DB 2: CheaperForDrug API               -> Sidekiq jobs, cache
└── DB 3: Brokik API                       -> Sidekiq jobs, cache, scheduler
```

### Elasticsearch Dependencies

```
AWS Elasticsearch Cluster
└── CheaperForDrug API                     -> Drug search index
```

### Service Communication

```
Brokik Web (Next.js)
    ↓ JWT Auth + API Calls
Brokik API (Rails)
    ↓ Database queries
PostgreSQL

CheaperForDrug Web (Next.js)
    ↓ JWT Auth + API Calls
CheaperForDrug API (Rails)
    ↓ Database + Elasticsearch queries
PostgreSQL + AWS Elasticsearch

Scraper VPN Containers
    ↓ Scraped data
Product Update Workers
    ↓ API calls (Internal endpoint)
CheaperForDrug API
    ↓ Store data
PostgreSQL + Elasticsearch
```

### External Dependencies

- **SendGrid:** Email delivery for all applications
- **AWS Elasticsearch:** Search infrastructure
- **Let's Encrypt:** SSL certificate provisioning
- **VPN Provider:** For scraper VPN connections
- **GitHub:** Source code repositories

---

## Monitoring & Health Checks

### Container Health Status

All containers implement health checks:

**Web Containers:**
```bash
# Health check command (example)
curl -f http://localhost:3000/up || exit 1
```

**Expected Responses:**
- Brokik API: HTTP 301 (redirect configured, service operational)
- Brokik Web: HTTP 307 (redirect configured, service operational)
- CheaperForDrug Landing: HTTP 301 (redirect configured, service operational)
- CheaperForDrug Web: HTTP 200 (healthy)
- CheaperForDrug API: HTTP 200 (healthy)

**Note:** Some containers show "unhealthy" status in Docker due to redirect responses (301/307). These are operational and correctly routing through Nginx.

### Health Check Commands

```bash
# Check all containers
ssh hetzner-andrzej "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E '(brokik|cheaperfordrug|scraper)'"

# Check specific service health
curl -I https://api-public.brokik.com/up
curl -I https://www.brokik.com/up
curl -I https://taniejpolek.pl/up
curl -I https://premiera.taniejpolek.pl
curl -I https://api-public.cheaperfordrug.com/up

# Check scraper status
ssh hetzner-andrzej "cd ~/apps/cheaperfordrug-scraper && docker-compose ps"
```

### Application Logs

**Rails Applications:**
```bash
# Brokik API logs
tail -f /home/andrzej/apps/brokik-api/logs/production.log

# CheaperForDrug Landing logs
tail -f /home/andrzej/apps/cheaperfordrug-landing/logs/production.log

# CheaperForDrug API logs
tail -f /home/andrzej/apps/cheaperfordrug-api/logs/production.log

# Sidekiq worker logs (filtered)
tail -f /home/andrzej/apps/brokik-api/logs/production.log | grep Sidekiq
tail -f /home/andrzej/apps/cheaperfordrug-api/logs/production.log | grep Sidekiq
```

**Next.js Applications:**
```bash
# Brokik Web logs
docker logs brokik-web_web_1 -f
docker logs brokik-web_web_2 -f
docker logs brokik-web_web_3 -f

# CheaperForDrug Web logs
docker logs cheaperfordrug-web_web_1 -f
docker logs cheaperfordrug-web_web_2 -f
docker logs cheaperfordrug-web_web_3 -f
```

**Scraper Logs:**
```bash
# VPN scraper logs
docker logs scraper-vpn-poland -f
docker logs scraper-vpn-germany -f
docker logs scraper-vpn-czech -f

# Product update worker logs
docker logs product-update-worker-poland-1 -f
# ... (similar for workers 2-5)
```

### Database Monitoring

```bash
# Check database connections
ssh hetzner-andrzej "sudo -u postgres psql -c \"SELECT datname, numbackends FROM pg_stat_database WHERE datname LIKE '%production';\""

# Check database sizes
ssh hetzner-andrzej "sudo -u postgres psql -c \"SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datname LIKE '%production';\""
```

### Redis Monitoring

```bash
# Check Redis connections by database
ssh hetzner-andrzej "redis-cli INFO clients"
ssh hetzner-andrzej "redis-cli INFO stats"

# Check Sidekiq queue depth
ssh hetzner-andrzej "redis-cli -n 2 LLEN queue:default"  # CheaperForDrug API
ssh hetzner-andrzej "redis-cli -n 3 LLEN queue:default"  # Brokik API
```

---

## Deployment Procedures

### Standard Deployment

Each service has a deployment script in `~/DevOps/apps/[service-name]/deploy.sh`

```bash
# Deploy specific service
ssh hetzner-andrzej "cd ~/DevOps/apps/brokik-api && ./deploy.sh"
ssh hetzner-andrzej "cd ~/DevOps/apps/brokik-web && ./deploy.sh"
ssh hetzner-andrzej "cd ~/DevOps/apps/cheaperfordrug-landing && ./deploy.sh"
ssh hetzner-andrzej "cd ~/DevOps/apps/cheaperfordrug-web && ./deploy.sh"
ssh hetzner-andrzej "cd ~/DevOps/apps/cheaperfordrug-api && ./deploy.sh"
```

### Deployment Features

**Zero-Downtime Deployment (Rails apps):**
1. Build new Docker image
2. Start new containers
3. Wait for health check to pass
4. Stop old containers
5. Clean up old images

**Rolling Restart (Next.js apps):**
1. Build new Docker image
2. Restart containers one by one
3. Verify each container before proceeding

**Database Migrations:**
- Automatic backup before migrations
- Applied on first healthy container
- Rollback available if migration fails

### Deployment Commands

```bash
# Scale web containers
cd ~/DevOps/apps/[service-name] && ./deploy.sh scale N

# Restart containers
cd ~/DevOps/apps/[service-name] && ./deploy.sh restart

# Rollback to previous image
cd ~/DevOps/apps/[service-name] && ./deploy.sh rollback

# Stop service
cd ~/DevOps/apps/[service-name] && ./deploy.sh stop
```

### Email Notifications

All deployments send email notifications via SendGrid:

**Configuration:**
- From: biuro@webet.pl
- To: andrzej@webet.pl
- API Key: Configured in ~/DevOps/common/email-config.sh

**Notification Types:**
- Deployment start (with git commit)
- Deployment success (with container details)
- Deployment failure (with error details)

### Performance Optimization

**Docker Build Times:**
- Optimized Dockerfile removes recursive chown/chmod
- Layer caching maximized
- Build context minimized
- Multi-stage builds used

**Recent Performance Improvements:**
- Build step #24 (permissions): 10+ minutes → 0.3 seconds (2000x faster)
- Total deployment time: 1.5-2.5 minutes per service
- Docker cleanup freed 29GB disk space

---

## Troubleshooting

### Common Issues

#### 1. Container Shows "Unhealthy" but Service Works

**Cause:** Health check expects HTTP 200 but receives 301/307 redirect

**Solution:** This is expected behavior for services with redirect-only endpoints. Verify Nginx is routing correctly:

```bash
curl -I https://api-public.brokik.com/up  # Should return 200 through Nginx
```

#### 2. Deployment Takes 10+ Minutes

**Cause:** Old Dockerfile with recursive chown/chmod operations

**Solution:** Already fixed! Ensure DevOps repo is up to date:

```bash
ssh hetzner-andrzej "cd ~/DevOps && git pull origin master"
```

#### 3. Email Notifications Not Sent

**Cause:** email-config.sh not loaded or SENDGRID_API_KEY missing

**Solution:** Verify configuration:

```bash
ssh hetzner-andrzej "cd ~/DevOps/common && source email-config.sh && echo \$SENDGRID_API_KEY"
```

#### 4. Scraper Containers Not Running

**Cause:** VPN connection failed or docker-compose not started

**Solution:** Restart scraper system:

```bash
ssh hetzner-andrzej "cd ~/apps/cheaperfordrug-scraper && docker-compose restart"
```

#### 5. Database Connection Errors

**Cause:** Container network configuration or PostgreSQL not running

**Solution:** Check PostgreSQL and container network mode:

```bash
ssh hetzner-andrzej "sudo systemctl status postgresql"
ssh hetzner-andrzej "docker inspect [container-name] | grep NetworkMode"  # Should be "host"
```

### Debug Commands

```bash
# Enter container shell
ssh hetzner-andrzej "docker exec -it [container-name] /bin/bash"

# Check container logs with tail
ssh hetzner-andrzej "docker logs [container-name] --tail 100 -f"

# Check container environment variables
ssh hetzner-andrzej "docker exec [container-name] env"

# Check container processes
ssh hetzner-andrzej "docker top [container-name]"

# Check Docker system resources
ssh hetzner-andrzej "docker system df -v"
```

### Performance Debugging

```bash
# Check I/O statistics
ssh hetzner-andrzej "iostat -x 2 5"

# Check overlay2 layers
ssh hetzner-andrzej "du -sh /var/lib/docker/overlay2"
ssh hetzner-andrzej "ls /var/lib/docker/overlay2 | wc -l"

# Monitor Docker build in real-time
ssh hetzner-andrzej "cd ~/DevOps/apps/[service] && docker build --progress=plain ..."
```

---

## Backup & Recovery

### Image Backups

All services maintain Docker image backups:

**Location:** ~/apps/[service-name]/docker-images/
**Retention:** Last 20 images
**Format:** tar.gz compressed images

```bash
# List available image backups
ssh hetzner-andrzej "ls -lh ~/apps/brokik-api/docker-images/"

# Restore from image backup
ssh hetzner-andrzej "docker load -i ~/apps/brokik-api/docker-images/brokik-api_YYYYMMDD_HHMMSS.tar.gz"
```

### Database Backups

**Location:** ~/apps/[service-name]/backups/
**Retention:** 30 days
**Schedule:** Automated backups before migrations

**Available Backups:**
- Brokik API: Database backups available
- CheaperForDrug Landing: 0 backups (minimal data)
- CheaperForDrug API: 232 backups

```bash
# List database backups
ssh hetzner-andrzej "ls -lh ~/apps/cheaperfordrug-api/backups/"

# Restore database backup
ssh hetzner-andrzej "cd ~/apps/cheaperfordrug-api && ./restore-db.sh backups/cheaperfordrug_production_YYYYMMDD_HHMMSS.sql.gz"
```

---

## Quick Reference

### Service URLs

| Service | Primary URL | Alternative URLs |
|---------|-------------|------------------|
| Brokik API | https://api-public.brokik.com | https://api-internal.brokik.com |
| Brokik Web | https://www.brokik.com | - |
| CheaperForDrug Landing | https://taniejpolek.pl | https://presale.taniejpolek.pl, https://www.taniejpolek.pl |
| CheaperForDrug Web | https://premiera.taniejpolek.pl | https://www.premiera.taniejpolek.pl |
| CheaperForDrug API | https://api-public.cheaperfordrug.com | https://api-internal.cheaperfordrug.com |

### Container Counts

| Service | Web | Worker | Scheduler | Total |
|---------|-----|--------|-----------|-------|
| Brokik API | 2 | 1 | 1 | 4 |
| Brokik Web | 3 | - | - | 3 |
| CheaperForDrug Landing | 2 | - | - | 2 |
| CheaperForDrug Web | 3 | - | - | 3 |
| CheaperForDrug API | 3 | 1 | - | 4 |
| Scraper System | - | - | - | 8 |
| **TOTAL** | **13** | **2** | **1** | **24** |

### Port Allocation

| Port Range | Service | Container Count |
|------------|---------|-----------------|
| 3010-3011 | CheaperForDrug Landing | 2 |
| 3020-3022 | CheaperForDrug API | 3 |
| 3030-3032 | CheaperForDrug Web | 3 |
| 3040-3041 | Brokik API | 2 |
| 3050-3052 | Brokik Web | 3 |

### Database Allocation

| Database Name | Service | Redis DB |
|---------------|---------|----------|
| brokik_production | Brokik API | 3 |
| cheaperfordrug_landing_production | CheaperForDrug Landing | 1 |
| cheaperfordrug_production | CheaperForDrug API | 2 |

---

**Document Version:** 1.0
**Last Deployment:** 2025-11-14
**Maintained By:** DevOps Team
