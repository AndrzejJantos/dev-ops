# Dedicated API Containers for CheaperForDrug Scraper

This directory contains configuration for 4 dedicated API containers that provide specialized endpoints for the CheaperForDrug scraper system.

## Architecture Overview

The scraper system uses specialized API containers to separate concerns and provide dedicated resources for different operations:

```
Main API Deployment (existing):
├── 3x Web Containers (ports 3020-3022) - Public API via nginx
└── 1x Sidekiq Worker - Background processing

Dedicated API Containers (new):
├── api-product-read (port 4201) - Read-only product queries
├── api-product-write (port 4202) + worker - Product updates
├── api-normalizer (port 4203) - Drug normalization
└── api-scraper (port 4204) + worker - Full scraping operations
```

## Container Specifications

### 1. API-Product-Read (Port 4201)
**Purpose:** High-frequency read operations for scraper workers

**Endpoints:**
- `GET /api/scraper/online_pharmacy_drugs/pending_updates`

**Characteristics:**
- No Sidekiq worker needed
- Optimized for high-frequency polling
- Read-only operations
- Direct database queries

**Use Case:** Worker containers poll this endpoint to get batches of products that need updating.

### 2. API-Product-Write (Port 4202)
**Purpose:** Handle product update operations with background processing

**Endpoints:**
- `POST /api/scraper/online_pharmacy_drugs/batch_update`
- `POST /api/scraper/online_pharmacy_drugs/release_lock`

**Characteristics:**
- Includes Sidekiq worker (api-product-write-sidekiq)
- Handles batch updates
- Lock management
- Background job processing

**Use Case:** Workers send scraped product data here for processing and database updates.

### 3. API-Normalizer (Port 4203)
**Purpose:** Drug name normalization operations

**Endpoints:**
- `POST /api/scraper/online_pharmacy_drugs/update_normalized_attributes`

**Characteristics:**
- No Sidekiq worker needed
- Synchronous processing
- Drug name standardization

**Use Case:** Normalize product names, dosages, and forms to standardized values.

### 4. API-Scraper (Port 4204)
**Purpose:** Full scraping operations with background processing

**Endpoints:**
- Full scraping API
- Create drugs
- Create pharmacies
- Category scraping
- Product creation

**Characteristics:**
- Includes Sidekiq worker (api-scraper-sidekiq)
- Complex operations
- External API calls
- Background processing

**Use Case:** Orchestrate full category scraping operations, create new entities.

## Infrastructure Details

### Network Configuration
- **Network Mode:** host (same as main API)
- **Direct Access:** Containers bind directly to localhost ports
- **No Nginx:** Direct container access (not proxied)

### Database & Redis
- **Database:** PostgreSQL on localhost:5432
  - Database: `cheaperfordrug_production`
  - User: `cheaperfordrug_user`
- **Redis:** localhost:6379/2
  - Same Redis DB as main API

### Health Checks
All web containers expose: `GET http://localhost:<PORT>/up`

### Logging
- **Location:** `${LOG_DIR}/logs` (shared with main API)
- **Format:** JSON with max 10MB per file
- **Rotation:** Keep 3 files

## Deployment Instructions

### Prerequisites

1. **Main API must be deployed first:**
   ```bash
   cd /Users/andrzej/Development/CheaperForDrug/DevOps/apps/cheaperfordrug-api
   ./deploy.sh deploy
   ```

2. **Verify main API image exists:**
   ```bash
   docker images cheaperfordrug-api:latest
   ```

3. **Environment file must exist:**
   ```bash
   ls -la .env.production
   ```

### Initial Deployment

1. **Start all dedicated containers:**
   ```bash
   ./deploy-dedicated-api.sh start
   ```

2. **Check status:**
   ```bash
   ./deploy-dedicated-api.sh status
   ```

3. **Verify health:**
   ```bash
   ./deploy-dedicated-api.sh health
   ```

### Deployment on Hetzner Server

```bash
# SSH to server
ssh andrzej@your-server

# Navigate to app directory
cd ~/apps/cheaperfordrug-api/repo

# Ensure main API is deployed
cd /home/andrzej/DevOps/apps/cheaperfordrug-api
./deploy.sh deploy

# Start dedicated containers
./deploy-dedicated-api.sh start

# Verify all containers are running
./deploy-dedicated-api.sh status
```

### Local Development (macOS)

```bash
# Navigate to DevOps directory
cd /Users/andrzej/Development/CheaperForDrug/DevOps/apps/cheaperfordrug-api

# Start containers
./deploy-dedicated-api.sh start

# Check status
./deploy-dedicated-api.sh status

# Test endpoints
curl http://localhost:4201/up
curl http://localhost:4202/up
curl http://localhost:4203/up
curl http://localhost:4204/up
```

## Management Commands

### Start/Stop Operations

```bash
# Start all containers
./deploy-dedicated-api.sh start

# Stop all containers
./deploy-dedicated-api.sh stop

# Restart all containers
./deploy-dedicated-api.sh restart
```

### Monitoring

```bash
# Show container status
./deploy-dedicated-api.sh status

# Check health of all containers
./deploy-dedicated-api.sh health

# View logs for all containers
./deploy-dedicated-api.sh logs

# View logs for specific container
./deploy-dedicated-api.sh logs product-read
./deploy-dedicated-api.sh logs product-write
./deploy-dedicated-api.sh logs product-write-sidekiq
./deploy-dedicated-api.sh logs normalizer
./deploy-dedicated-api.sh logs scraper
./deploy-dedicated-api.sh logs scraper-sidekiq
```

### Updates

```bash
# Deploy main API (which builds new image)
./deploy.sh deploy

# Restart dedicated containers to use new image
./deploy-dedicated-api.sh restart
```

## Container Naming Convention

| Service | Container Name | Port | Worker |
|---------|---------------|------|--------|
| Product Read | `cheaperfordrug-api-product-read` | 4201 | No |
| Product Write | `cheaperfordrug-api-product-write` | 4202 | Yes |
| Product Write Worker | `cheaperfordrug-api-product-write-sidekiq` | - | - |
| Normalizer | `cheaperfordrug-api-normalizer` | 4203 | No |
| Scraper | `cheaperfordrug-api-scraper` | 4204 | Yes |
| Scraper Worker | `cheaperfordrug-api-scraper-sidekiq` | - | - |

## Testing Endpoints

### Health Checks

```bash
# Test all health endpoints
for port in 4201 4202 4203 4204; do
  echo "Testing port $port..."
  curl -s http://localhost:$port/up && echo " - OK" || echo " - FAILED"
done
```

### Sample API Calls

```bash
# Get pending updates (Product Read)
curl http://localhost:4201/api/scraper/online_pharmacy_drugs/pending_updates?batch_size=10

# Batch update (Product Write)
curl -X POST http://localhost:4202/api/scraper/online_pharmacy_drugs/batch_update \
  -H "Content-Type: application/json" \
  -d '{"updates": [...]}'

# Normalize attributes (Normalizer)
curl -X POST http://localhost:4203/api/scraper/online_pharmacy_drugs/update_normalized_attributes \
  -H "Content-Type: application/json" \
  -d '{"id": 123, "name": "..."}'
```

## Troubleshooting

### Container won't start

1. **Check if main API image exists:**
   ```bash
   docker images cheaperfordrug-api:latest
   ```

2. **Check if ports are already in use:**
   ```bash
   lsof -i :4201
   lsof -i :4202
   lsof -i :4203
   lsof -i :4204
   ```

3. **Check environment file:**
   ```bash
   cat .env.production
   ```

4. **View container logs:**
   ```bash
   docker logs cheaperfordrug-api-product-read
   docker logs cheaperfordrug-api-product-write
   ```

### Health check failing

1. **Check container is running:**
   ```bash
   docker ps | grep cheaperfordrug-api
   ```

2. **Check container logs for errors:**
   ```bash
   ./deploy-dedicated-api.sh logs product-read
   ```

3. **Test database connection:**
   ```bash
   docker exec cheaperfordrug-api-product-read \
     /bin/bash -c "cd /app && bundle exec rails runner 'puts ActiveRecord::Base.connection.active?'"
   ```

4. **Test Redis connection:**
   ```bash
   docker exec cheaperfordrug-api-product-read \
     /bin/bash -c "cd /app && bundle exec rails runner 'puts Redis.new(url: ENV[\"REDIS_URL\"]).ping'"
   ```

### Worker not processing jobs

1. **Check worker is running:**
   ```bash
   docker ps | grep sidekiq
   ```

2. **View worker logs:**
   ```bash
   ./deploy-dedicated-api.sh logs product-write-sidekiq
   ./deploy-dedicated-api.sh logs scraper-sidekiq
   ```

3. **Check Redis connection:**
   ```bash
   docker exec cheaperfordrug-api-product-write-sidekiq \
     /bin/bash -c "cd /app && bundle exec rails runner 'puts Sidekiq.redis { |c| c.ping }'"
   ```

### Port conflicts

If ports 4201-4204 are already in use:

1. **Find what's using the port:**
   ```bash
   lsof -i :4201
   ```

2. **Stop the conflicting service or change ports in docker-compose-dedicated-api.yml**

## Files

- `docker-compose-dedicated-api.yml` - Docker Compose configuration for all 4 containers
- `deploy-dedicated-api.sh` - Deployment and management script
- `.env.production` - Shared environment configuration (from main API)
- `README-DEDICATED-API.md` - This documentation

## Integration with Scraper

The scraper workers should be configured to use these dedicated endpoints:

```python
# Scraper configuration
API_ENDPOINTS = {
    'product_read': 'http://localhost:4201',
    'product_write': 'http://localhost:4202',
    'normalizer': 'http://localhost:4203',
    'scraper': 'http://localhost:4204',
}
```

## Maintenance

### Regular Operations

1. **Monitor logs:**
   ```bash
   ./deploy-dedicated-api.sh logs
   ```

2. **Check health daily:**
   ```bash
   ./deploy-dedicated-api.sh health
   ```

3. **Restart if needed:**
   ```bash
   ./deploy-dedicated-api.sh restart
   ```

### Updates

When updating the main API:

```bash
# Update main API
./deploy.sh deploy

# Restart dedicated containers
./deploy-dedicated-api.sh restart
```

## Performance Considerations

### Resource Allocation

Each container uses Rails default settings:
- **Max Threads:** 5 (from `RAILS_MAX_THREADS`)
- **Web Concurrency:** 2 (from `WEB_CONCURRENCY`)
- **Sidekiq Concurrency:** 10 (from `SIDEKIQ_CONCURRENCY`)

### Scaling

To increase capacity for a specific service:

1. **Duplicate the service in docker-compose-dedicated-api.yml**
2. **Change container name and port**
3. **Load balance at application level**

Example:
```yaml
api-product-read-2:
  image: cheaperfordrug-api:latest
  container_name: cheaperfordrug-api-product-read-2
  environment:
    - PORT=4211
  # ... rest of config
```

## Security Notes

- These containers run in host network mode
- No external exposure (not behind nginx)
- Access restricted to localhost
- Shared database credentials with main API
- Same Redis instance as main API

## Support

For issues or questions:
1. Check logs: `./deploy-dedicated-api.sh logs`
2. Check status: `./deploy-dedicated-api.sh status`
3. Review main API deployment: `./deploy.sh status`
4. Check database connectivity
5. Verify Redis is running
