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
- Receives data from scraper system
- Processes pharmacy product updates
- Maintains drug name groupings and variants
- Handles multi-country drug information

---

## Scraper System

**Location:** ~/apps/cheaperfordrug-scraper
**Docker Compose:** docker-compose.yml
**Image:** scraper-vpn:latest (2.19GB)
**Total Containers:** 8

### Architecture Overview

The scraper system consists of two types of containers:
1. **VPN Scrapers** - Scrape pharmacy websites with VPN rotation
2. **Product Update Workers** - Call the API to update product data

### VPN Scraper Containers (3 total)

#### 1. Poland VPN Scraper
```
Container: scraper-vpn-poland
Status: Running (healthy)
Country: Poland
VPN Rotation: Every 5 minutes
Target: Polish pharmacy websites
```

**Scraping Schedule:**
- Runs continuously with 5-minute VPN rotation
- Scrapes Polish pharmacies:
  - Gemini
  - DOZ
  - WaptekaPL
  - i-Apteka
  - ZikoApteka
  - SuperPharm
  - Melissa

**Data Flow:**
1. Connect to VPN (Poland endpoint)
2. Scrape pharmacy websites
3. Store raw data locally
4. Rotate VPN connection after 5 minutes
5. Repeat

#### 2. Germany VPN Scraper
```
Container: scraper-vpn-germany
Status: Running (healthy)
Country: Germany
VPN Rotation: Every 5 minutes
Target: German pharmacy websites
```

**Scraping Schedule:**
- Runs continuously with 5-minute VPN rotation
- Scrapes German pharmacies (when configured)

#### 3. Czech VPN Scraper
```
Container: scraper-vpn-czech
Status: Running (healthy)
Country: Czech Republic
VPN Rotation: Every 5 minutes
Target: Czech pharmacy websites
```

**Scraping Schedule:**
- Runs continuously with 5-minute VPN rotation
- Scrapes Czech pharmacies (when configured)

### Product Update Workers (5 total)

These workers call the CheaperForDrug API to update product data.

```
Container: product-update-worker-poland-1  [Running]
Container: product-update-worker-poland-2  [Running]
Container: product-update-worker-poland-3  [Running]
Container: product-update-worker-poland-4  [Running]
Container: product-update-worker-poland-5  [Running]
```

**Worker Configuration:**
- **API Endpoint:** https://api-internal.cheaperfordrug.com
- **Authentication:** Internal API key
- **Concurrency:** 5 workers running in parallel
- **Job Queue:** Redis-backed queue

**Data Processing Flow:**
1. VPN scrapers collect raw pharmacy data
2. Data is queued for processing
3. Product update workers pick up jobs from queue
4. Workers call API endpoints to:
   - Create/update drugs
   - Update prices
   - Link products to pharmacies
   - Group drug variants
5. API processes and stores in database
6. Elasticsearch indexes updated

### Scraper Orchestration

**Startup Sequence:**
1. VPN scrapers start first (connect to VPN)
2. Wait for VPN connection to establish
3. Product update workers start
4. Workers wait for scraper data to be available
5. Processing begins

**Health Monitoring:**
- All containers have health checks
- VPN connection verified every 5 minutes
- Worker queue depth monitored
- API endpoint availability checked

**Deployment Method:**
```bash
cd ~/apps/cheaperfordrug-scraper
docker-compose restart  # Restart all scraper containers
```

**Logs:**
- Location: ~/apps/cheaperfordrug-scraper/logs/
- VPN logs: Shows connection status and rotations
- Worker logs: Shows API calls and processing results

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
