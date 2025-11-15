# CheaperForDrug API Infrastructure

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [API Container Deployment](#api-container-deployment)
3. [Scraper System Architecture](#scraper-system-architecture)
4. [Network Configuration](#network-configuration)
5. [Load Balancing](#load-balancing)
6. [Traffic Analysis](#traffic-analysis)
7. [Management Commands](#management-commands)

---

## Architecture Overview

The CheaperForDrug API infrastructure consists of two main deployment types:

1. **Main API Deployment** (Internet-facing)
   - 1 API container serving public and internal APIs
   - Nginx reverse proxy with SSL/TLS
   - Port: 3020

2. **Scraper API Deployment** (Internal traffic only)
   - **1 API container** load-balanced by Nginx
   - Localhost-only access for scraper containers
   - Port: 4200 (nginx entry point)
   - Backend port: 3020

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

**Active Scrapers (8 containers):**
- scraper-vpn-poland
- scraper-vpn-germany
- scraper-vpn-czech
- product-update-worker-poland-1
- product-update-worker-poland-2
- product-update-worker-poland-3
- product-update-worker-poland-4
- product-update-worker-poland-5

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
