# CheaperForDrug API Infrastructure

## Table of Contents
1. [Complete System Architecture](#complete-system-architecture)
2. [All CheaperForDrug Services](#all-cheaperfordrug-services)
3. [Port Allocation Reference](#port-allocation-reference)
4. [Nginx Routing Configuration](#nginx-routing-configuration)
5. [Public vs Internal Access](#public-vs-internal-access)
6. [API Container Deployment](#api-container-deployment)
7. [Scraper System Architecture](#scraper-system-architecture)
8. [Network Configuration](#network-configuration)
9. [Load Balancing](#load-balancing)
10. [Traffic Analysis](#traffic-analysis)
11. [Management Commands](#management-commands)

---

## Complete System Architecture

```
                    CHEAPERFORDRUG COMPLETE INFRASTRUCTURE
============================================================================

                              INTERNET
                                 |
                                 v
                    +------------------------+
                    |    NGINX (Port 443)    |
                    |    SSL Termination     |
                    +------------------------+
                    /           |            \
                   v            v             v
        +----------------+ +----------+ +------------------+
        | api-public     | | admin    | | api-internal     |
        | .cheaperfordrug| | .cheaper | | .cheaperfordrug  |
        | .com           | | fordrug  | | .com             |
        |                | | .com     | |                  |
        | (No Auth)      | | (Basic   | | (JWT Auth)       |
        |                | |  Auth)   | |                  |
        +----------------+ +----------+ +------------------+
                    \          |           /
                     v         v          v
              +-----------------------------+
              |  MAIN API CONTAINERS        |
              |  (docker-compose.yml)       |
              |                             |
              |  api-1 (3020)  api-2 (3021) |
              |       sidekiq  scheduler    |
              +-----------------------------+
                             |
         +-------------------+-------------------+
         v                   v                   v
    +----------+      +------------+      +-------------+
    | PostgreSQL|     |   Redis    |      | Elasticsearch|
    | (5432)   |      | (6379/2)   |      | (9200)      |
    +----------+      +------------+      +-------------+
                             ^
         +-------------------+-------------------+
         |                   |                   |
         v                   v                   v
    +----------------------------------------------------+
    |     DEDICATED API CONTAINERS                        |
    |     (docker-compose-dedicated-api.yml)              |
    |                                                     |
    |  api-product-read-1 (4201)  api-product-read-2 (4211)|
    |  api-product-write-1 (4202) + sidekiq                |
    |  api-normalizer-1 (4203)    api-normalizer-2 (4213) |
    |  api-scraper-1 (4204)       api-scraper-2 (4214)    |
    |                        + sidekiq                    |
    +----------------------------------------------------+
                             ^
                             |
                    +----------------+
                    | Nginx (4200)   |
                    | Scraper Entry  |
                    +----------------+
                             ^
                             |
    +----------------------------------------------------+
    |     SCRAPER CONTAINERS                              |
    |     (cheaperfordrug-scraper)                        |
    |                                                     |
    |  scraper-vpn-poland      product-update-worker-1    |
    |                          product-update-worker-2    |
    |                          ...                        |
    |                          product-update-worker-10   |
    +----------------------------------------------------+


                     OTHER CHEAPERFORDRUG SERVICES
    +----------------------------------------------------+
    |  cheaperfordrug-web (Next.js)     Ports: 3055-3057 |
    |  cheaperfordrug-landing           Port: 3040       |
    +----------------------------------------------------+
```

---

## All CheaperForDrug Services

### 1. cheaperfordrug-api (Rails API)
**Purpose:** Core backend API serving admin panel, public API, internal API, and scraper endpoints

| Component | Port(s) | Description |
|-----------|---------|-------------|
| Main API | 3020-3021 | Internet-facing containers |
| Dedicated API | 4201-4214 | Scraper-specific endpoints |
| Sidekiq Workers | N/A | Background job processing |
| Scheduler | N/A | Clockwork recurring tasks |

### 2. cheaperfordrug-web (Next.js Frontend)
**Purpose:** Main user-facing web application

| Component | Port(s) | Description |
|-----------|---------|-------------|
| Web Containers | 3055-3057 | Next.js SSR containers |
| Domain | cheaperfordrug.com | Main website |

### 3. cheaperfordrug-landing (Landing Page)
**Purpose:** Marketing landing page

| Component | Port(s) | Description |
|-----------|---------|-------------|
| Landing | 3040 | Static/marketing pages |

### 4. cheaperfordrug-scraper (Node.js Scrapers)
**Purpose:** Pharmacy data scraping and updates

| Component | Port(s) | Description |
|-----------|---------|-------------|
| Scraper VPN | N/A | VPN-based scrapers |
| Product Workers | N/A | Product update workers |
| Entry Point | 4200 | Nginx load balancer |

### 5. Infrastructure Services

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL | 5432 | Primary database |
| Redis | 6379/2 | Cache, sessions, job queue |
| Elasticsearch | 9200 | Drug/pharmacy search |

---

## Port Allocation Reference

```
PORT ALLOCATION MAP
============================================================================

MAIN API (Internet Traffic)
------------------------------------
3020    api-1               Main API container 1
3021    api-2               Main API container 2

DEDICATED SCRAPER API (Internal Only)
------------------------------------
4200    nginx               Scraper load balancer entry point
4201    api-product-read-1  High-frequency read operations
4202    api-product-write-1 Product updates with sidekiq
4203    api-normalizer-1    Drug name normalization
4204    api-scraper-1       Full scraping operations
4211    api-product-read-2  Replica for read operations
4213    api-normalizer-2    Replica for normalization
4214    api-scraper-2       Replica for scraping

WEB FRONTEND
------------------------------------
3055    web-1               Next.js container 1
3056    web-2               Next.js container 2
3057    web-3               Next.js container 3

OTHER SERVICES
------------------------------------
3040    landing             Landing page
5432    postgresql          Database
6379    redis               Cache and queue (DB 2 for API)
9200    elasticsearch       Search engine
```

---

## Nginx Routing Configuration

### Domain to Backend Mapping

```
NGINX ROUTING
============================================================================

HTTPS (Port 443) - SSL Termination
------------------------------------

api-public.cheaperfordrug.com
    |
    +---> upstream cheaperfordrug_api_backend
          - 127.0.0.1:3020
          - 127.0.0.1:3021
          - least_conn algorithm
          - No authentication required

api-internal.cheaperfordrug.com
    |
    +---> upstream cheaperfordrug_api_backend (same pool)
          - 127.0.0.1:3020
          - 127.0.0.1:3021
          - JWT authentication required

admin.cheaperfordrug.com
    |
    +---> upstream cheaperfordrug_api_backend (same pool)
          - 127.0.0.1:3020
          - 127.0.0.1:3021
          - HTTP Basic Auth required

HTTP (Port 4200) - Internal Only
------------------------------------

localhost:4200 / api-scraper.localtest.me:4200
    |
    +---> upstream api_scraper_local_backend
          - 127.0.0.1:3020
          - Bearer token authentication
          - No SSL (internal traffic)
```

### SSL Certificate Configuration

All three public domains use a shared multi-domain certificate:
- Primary: `/etc/letsencrypt/live/api-public.cheaperfordrug.com/fullchain.pem`
- Includes: api-public, api-internal, admin subdomains

---

## Public vs Internal Access

### Internet-Exposed Services

| Domain | Auth Method | Purpose |
|--------|-------------|---------|
| api-public.cheaperfordrug.com | None (CORS protected) | Public API endpoints |
| api-internal.cheaperfordrug.com | JWT Token | Internal service API |
| admin.cheaperfordrug.com | HTTP Basic Auth | Admin panel |
| cheaperfordrug.com | None | Main website |

### Internal-Only Services

| Service | Port | Access | Auth |
|---------|------|--------|------|
| Scraper API | 4200 | localhost only | Bearer token |
| PostgreSQL | 5432 | localhost only | Database credentials |
| Redis | 6379 | localhost only | None |
| Elasticsearch | 9200 | localhost only | None |

### Authentication Requirements

```
AUTHENTICATION MATRIX
============================================================================

Public Endpoints (api-public.cheaperfordrug.com):
- /api/v1/drugs/**         - No auth, public drug data
- /api/v1/pharmacies/**    - No auth, public pharmacy data
- /api/v1/search/**        - No auth, search functionality
- /up                      - No auth, health check

Internal Endpoints (api-internal.cheaperfordrug.com):
- /api/internal/**         - JWT required (Authorization: Bearer <token>)

Admin Panel (admin.cheaperfordrug.com):
- /admin/**                - HTTP Basic Auth (Rails controller level)

Scraper Endpoints (localhost:4200):
- /api/scraper/**          - Bearer token (SCRAPER_AUTH_TOKEN)
```

---

## API Container Deployment

### Main API (Internet Traffic)

**Purpose:** Serve public API, internal API, and admin panel

**Configuration (docker-compose.yml):**
- **Containers:** 2 web containers
- **Ports:** 3020, 3021 (host network mode)
- **Workers:** 1 Sidekiq worker
- **Scheduler:** 1 Clockwork scheduler
- **Domains:**
  - api-public.cheaperfordrug.com
  - api-internal.cheaperfordrug.com
  - admin.cheaperfordrug.com
- **SSL:** Handled by Nginx (port 443)
- **Load Balancing:** Nginx upstream with `least_conn` algorithm
- **Management:** `./deploy.sh deploy|restart|stop|status`

**Nginx Configuration:**
```nginx
upstream cheaperfordrug_api_backend {
    least_conn;
    server 127.0.0.1:3020 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:3021 max_fails=3 fail_timeout=30s;
}
```

### Scraper API (Internal Traffic)

**Purpose:** Handle scraper requests with high concurrency

**ACTUAL DEPLOYMENT (as of 2025-11-15):**
- **Containers:** 1 web container
- **Backend Port:** 3020 (host network mode)
- **Entry Point:** http://localhost:4200 (nginx)
- **Access:** Internal only - no internet exposure
- **Load Balancing:** Nginx with 1 upstream server using `least_conn`
- **Traffic Source:** Scraper containers on same host

**Nginx Configuration (Port 4200):**
```nginx
upstream api_scraper_local_backend {
    least_conn;
    server 127.0.0.1:3020;
}

server {
    listen 4200;
    listen [::]:4200;
    server_name localhost api-scraper.localtest.me;

    location / {
        proxy_pass http://api_scraper_local_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;

        # Timeouts for scraper operations
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

**IMPORTANT:** The `ARCHITECTURE-DIAGRAM.txt` documents a design with 4 dedicated containers on ports 4201-4204, but the **actual production deployment** uses 1 container load-balanced through nginx on port 4200.

---

## API Container Deployment

### Main API (Internet Traffic)

**Purpose:** Serve public API, internal API, and admin panel

**Configuration:**
- **Containers:** 1 web container
- **Port:** 3020 (host network mode)
- **Domains:**
  - api-public.cheaperfordrug.com
  - api-internal.cheaperfordrug.com
  - admin.cheaperfordrug.com
- **SSL:** Handled by Nginx (port 443)
- **Load Balancing:** Nginx upstream with `least_conn` algorithm
- **Management:** `./deploy.sh deploy|restart|stop|status`

**Nginx Configuration:**
```nginx
upstream cheaperfordrug_api_backend {
    least_conn;
    server 127.0.0.1:3020;
}
```

### Scraper API (Internal Traffic)

**Purpose:** Handle scraper requests with high concurrency

**ACTUAL DEPLOYMENT (as of 2025-11-15):**
- **Containers:** 1 web container
- **Backend Port:** 3020 (host network mode)
- **Entry Point:** http://localhost:4200 (nginx)
- **Access:** Internal only - no internet exposure
- **Load Balancing:** Nginx with 1 upstream server using `least_conn`
- **Traffic Source:** Scraper containers on same host

**Nginx Configuration (Port 4200):**
```nginx
upstream api_scraper_local_backend {
    least_conn;
    server 127.0.0.1:3020;
}

server {
    listen 4200;
    listen [::]:4200;
    server_name localhost api-scraper.localtest.me;

    location / {
        proxy_pass http://api_scraper_local_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;

        # Timeouts for scraper operations
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

**IMPORTANT:** The `ARCHITECTURE-DIAGRAM.txt` documents a design with 4 dedicated containers on ports 4201-4204, but the **actual production deployment** uses 1 container load-balanced through nginx on port 4200.

---

## Scraper System Architecture

### Scraper Containers

**Active Scrapers (11 containers):**
- scraper-vpn-poland
- product-update-worker-poland-1 through product-update-worker-poland-10

**Scheduler:**
- cheaperfordrug-api-scheduler (Clockwork)
  - Runs scheduled tasks every 15 minutes
  - Releases stale locks to prevent deadlocks
  - Prevents CATCH-22 where locked drugs never appear in pending updates
  - Command: `bundle exec clockwork lib/clock.rb`
  - Job: `ReleaseStaleLocksJob` (releases locks held >10 minutes)

### How Scrapers Connect to API

**Configuration (.env):**
```bash
API_ENDPOINT=http://api-scraper.localtest.me:4200/api/scraper/online_pharmacy_drugs
API_TOKEN=Andrzej12345
SCRAPER_AUTH_TOKEN=Andrzej12345
```

**Worker Configuration:**
```javascript
const CONFIG = {
  API_ENDPOINT: process.env.API_ENDPOINT || 'http://api-scraper.localtest.me:4200',
  API_TOKEN: process.env.API_TOKEN || process.env.SCRAPER_AUTH_TOKEN,
  MAX_CONCURRENT_SCRAPERS: parseInt(process.env.MAX_CONCURRENT_SCRAPERS) || 20,
  POLL_INTERVAL_MS: parseInt(process.env.POLL_INTERVAL_MS) || 1000,
};
```

### Request Flow

```
┌──────────────────────────────────┐
│  Scraper Containers              │
│  (Docker bridge network)         │
│  - 172.17.0.0/16                 │
└────────────┬─────────────────────┘
             │
             │ HTTP requests to:
             │ http://api-scraper.localtest.me:4200
             │ (resolved to 172.17.0.1 via extra_hosts)
             ▼
┌──────────────────────────────────┐
│  Nginx Load Balancer             │
│  - Port: 4200                    │
│  - Algorithm: least_conn         │
│  - Upstream: 1 server            │
└────────────┬─────────────────────┘
             │
             │ Proxy to 127.0.0.1:3020
             ▼
┌──────────────────────────────────┐
│  1 API Container                 │
│  - Port: 3020                    │
│  - Network: host mode            │
│  - Rails/Puma application        │
└────────────┬─────────────────────┘
             │
             ▼
┌──────────────────────────────────┐
│  Shared Infrastructure           │
│  - PostgreSQL (5432)             │
│  - Redis (6379/2)                │
│  - Elasticsearch (9200)          │
└──────────────────────────────────┘
```

---

## Network Configuration

### Docker Networking

**API Containers:**
- Network mode: `host`
- Direct access to host ports
- No Docker NAT overhead
- Share host network namespace

**Scraper Containers:**
- Network mode: `bridge` (172.17.0.0/16)
- Extra hosts configuration:
  ```yaml
  extra_hosts:
    - "host.docker.internal:host-gateway"
    - "api-scraper.localtest.me:host-gateway"
  ```
- Resolves `api-scraper.localtest.me` to `172.17.0.1` (host gateway)

### Port Allocation

| Port Range | Service | Container Count | Purpose |
|------------|---------|-----------------|---------|
| 3020 | Main API | 1 | Internet traffic (public/internal/admin) |
| 3020 | Scraper API | 1 | Internal scraper traffic |
| 4200 | Nginx | 1 | Scraper entry point (load balancer) |
| N/A | Scheduler | 1 | Clockwork job scheduler |
| N/A | Sidekiq Workers | 2 | Background job processors |
| 5432 | PostgreSQL | 1 | Database |
| 6379 | Redis | 1 | Cache & background jobs |
| 9200 | Elasticsearch | 1 | Search engine |

**Note:** Port 3020 serves BOTH internet traffic (via SSL nginx) AND scraper traffic (via port 4200 nginx).

---

## Load Balancing

### Algorithm: Least Connections (`least_conn`)

**How it works:**
- Nginx tracks active connections to each backend
- New requests sent to server with fewest active connections
- Ideal for long-running scraper requests
- Prevents overloading single containers

### Traffic Distribution

**Historical Data (Nov 15, 2025):**
- Total requests: Varies by day
- All from: 127.0.0.1 (nginx → API container)
- Single container handles all scraper traffic
- Average: All requests to single container

**Top Endpoints:**
- `/api/scraper/online_pharmacy_drugs` - 34,900 requests (96.7%)
- `/api/scraper/online_pharmacies` - 583 requests (1.6%)
- `/api/scraper/countries` - 583 requests (1.6%)

---

## Traffic Analysis

### Request Characteristics

**Source:**
- All traffic from `127.0.0.1` (internal only)
- No external internet exposure

**User-Agent:**
```
node-fetch/1.0 (+https://github.com/bitinn/node-fetch)
```

**HTTP Methods:**
- Primarily POST requests
- Some GET requests for polling

**Response Codes:**
- 201 (Created) - successful scraping operations
- 401 (Unauthorized) - authentication failures
- 502 (Bad Gateway) - backend unavailable (rare)

### Scraper Behavior

**Polling Pattern:**
- Workers poll `/api/scraper/online_pharmacy_drugs/pending_updates` every 1-5 seconds
- Lock mechanism prevents concurrent processing of same drug
- Batch processing: 17-29 products per batch
- Random delays: 1-3 seconds between requests

**Rate Limiting:**
- Scraper-level rate limiting (not nginx)
- Break duration: 4-8 minutes between batches
- VPN rotation: Every 5 minutes

---

## Management Commands

### Main API

```bash
# Deploy or update
./deploy.sh deploy

# Restart containers
./deploy.sh restart

# Stop containers
./deploy.sh stop

# Check status
./deploy.sh status
```

### Scraper API (1 Container)

**Note:** Managed through main deployment script (`./deploy.sh`).

### Docker Status Monitoring

```bash
# View all running containers
/Users/andrzej/Development/CheaperForDrug/DevOps/scripts/docker-status.sh

# View all containers (including stopped)
/Users/andrzej/Development/CheaperForDrug/DevOps/scripts/docker-status.sh --all
```

The docker-status script provides:
- Container health status
- CPU and memory usage
- Uptime information
- System resource summary
- Interactive management menu

### Checking Scraper API Health

```bash
# Test nginx load balancer
curl http://localhost:4200/up

# Check backend container directly
curl http://localhost:3020/up

# View nginx logs
tail -f /var/log/nginx/api-scraper-local-access.log

# Check active connections to API ports
ss -tnp | grep -E ':(30[2-5][0-9])'

# View listening ports
ss -tlnp | grep -E ':(30[2-5][0-9])'
```

### Monitoring Scheduler (Clockwork)

```bash
# Check if scheduler container is running
docker ps | grep scheduler

# View scheduler logs
docker logs -f cheaperfordrug-api-scheduler

# Verify scheduler is triggering jobs (should see log every 15 minutes)
docker logs --tail 100 cheaperfordrug-api-scheduler | grep "release_stale_locks"

# Check Sidekiq for queued ReleaseStaleLocksJob
# Visit: http://localhost:3020/sidekiq or check Redis
```

---

## Shared Infrastructure

### Docker Image
- **Name:** cheaperfordrug-api:latest
- **Base:** Ruby 3.4.5, Rails 8
- **Build:** `./deploy.sh deploy`

### Database
- **Service:** PostgreSQL
- **Port:** 5432
- **Database:** cheaperfordrug_production
- **User:** cheaperfordrug_user
- **Access:** All API containers share same database

### Redis
- **Port:** 6379/2
- **Purpose:** Cache, session storage, Sidekiq job queue
- **Access:** All containers

### Elasticsearch
- **Port:** 9200
- **Purpose:** Drug and pharmacy search
- **Access:** All containers

---

## Important Notes

### Architecture Documentation vs Reality

**Documented Design (ARCHITECTURE-DIAGRAM.txt):**
- 4 dedicated containers (ports 4201-4204)
- Direct access (no nginx)
- Functional separation by operation type

**Actual Deployment:**
- 1 container (port 3020)
- Nginx load balancer on port 4200
- Single upstream server

**Why the difference?**
- The documented architecture represents an aspirational design with dedicated containers
- The actual deployment uses a simpler single-container approach
- Can be scaled up using `./deploy.sh scale <N>` if traffic increases

### Security

**Scraper API Access:**
- Internal only - no internet exposure
- Localhost binding only
- Bearer token authentication required
- No SSL (internal traffic)

**Main API Access:**
- Internet-facing with SSL/TLS
- Domain-based access control
- Rate limiting (if configured in Rails)

### Performance Considerations

**Scaling for scraper traffic:**
- Can scale up using: `./deploy.sh scale <N>` if needed
- Current single container handles moderate traffic
- Long-running requests: Product updates take 1-2 seconds (optimized)
- Database locking: Prevents race conditions
- Monitor performance and scale up if experiencing slowdowns

**Container Resource Usage:**
- CPU: Varies by request type (normalization is CPU-intensive)
- Memory: ~200-500MB per container
- Total system memory: Monitor with docker-status.sh

---

## Troubleshooting

### Scrapers Not Getting Data

1. Check nginx is running on port 4200:
   ```bash
   netstat -tlnp | grep :4200
   ```

2. Verify API containers are healthy:
   ```bash
   /Users/andrzej/Development/CheaperForDrug/DevOps/scripts/docker-status.sh
   ```

3. Check nginx logs for errors:
   ```bash
   tail -f /var/log/nginx/api-scraper-local-error.log
   ```

### High CPU Usage

1. Check which containers are consuming CPU:
   ```bash
   docker stats
   ```

2. Look for normalization operations (CPU-intensive)
3. Consider scaling if needed

### 502 Bad Gateway Errors

1. Check if backend containers are running
2. Restart unhealthy containers:
   ```bash
   /Users/andrzej/Development/CheaperForDrug/DevOps/scripts/docker-status.sh
   # Use interactive menu: option 3 (Kill unhealthy containers)
   ```

3. Check database connectivity
4. Review container logs:
   ```bash
   docker logs cheaperfordrug-api_web_1
   ```

---

## Monitoring

### Key Metrics to Track

1. **Request Rate:** nginx access logs
2. **Response Times:** Application logs
3. **Error Rates:** nginx error logs + application logs
4. **Container Health:** docker-status.sh
5. **Database Connections:** PostgreSQL stats
6. **Queue Depth:** Sidekiq web UI
7. **System Resources:** Memory and disk usage

### Log Locations

- **Nginx Access:** `/var/log/nginx/api-scraper-local-access.log`
- **Nginx Error:** `/var/log/nginx/api-scraper-local-error.log`
- **Application Logs:** Inside containers at `/app/log/production.log`
- **Docker Logs:** `docker logs <container_name>`

---

## Additional Resources

- **Architecture Diagram:** `ARCHITECTURE-DIAGRAM.txt`
- **Deployment Script:** `deploy.sh`
- **Nginx Config:** `nginx.conf.template` (internet), `nginx-local-scraper.conf` (scrapers)
- **Configuration:** `config.sh`
- **Scraper Documentation:** `../cheaperfordrug-scraper/README.md`
