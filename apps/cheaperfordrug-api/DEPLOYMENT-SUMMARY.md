# Deployment Summary - Dedicated API Containers

## What Was Created

Successfully created 4 dedicated API containers for the CheaperForDrug scraper system in the DevOps repository.

**Location:** `/Users/andrzej/Development/CheaperForDrug/DevOps/apps/cheaperfordrug-api`

### Files Created

1. **docker-compose-dedicated-api.yml** (6.1 KB)
   - Docker Compose configuration for all 4 API containers + 2 workers
   - Uses host network mode (same as main API)
   - Configured for both Hetzner and local development

2. **deploy-dedicated-api.sh** (14 KB, executable)
   - Complete deployment and management script
   - Commands: start, stop, restart, status, logs, health
   - Health checking and validation

3. **verify-dedicated-api.sh** (5.9 KB, executable)
   - Pre-deployment verification script
   - Checks prerequisites, ports, database, Redis
   - Validates Docker image and configuration

4. **README-DEDICATED-API.md** (11 KB)
   - Complete technical documentation
   - Architecture details
   - Troubleshooting guide
   - Integration examples

5. **QUICKSTART-DEDICATED-API.md** (6.3 KB)
   - Quick reference guide
   - Common commands
   - Testing procedures

6. **Updated .env.production.template**
   - Added documentation for dedicated API ports

## Container Architecture

### 6 Total Containers (4 Web + 2 Workers)

#### 1. api-product-read (Port 4201)
- **Purpose:** High-frequency read operations for scraper workers
- **Endpoints:** GET /api/scraper/online_pharmacy_drugs/pending_updates
- **Worker:** No
- **Use Case:** Workers poll this endpoint to get batches of products needing updates

#### 2. api-product-write (Port 4202)
- **Purpose:** Handle product update operations
- **Endpoints:**
  - POST /api/scraper/online_pharmacy_drugs/batch_update
  - POST /api/scraper/online_pharmacy_drugs/release_lock
- **Worker:** Yes (api-product-write-sidekiq)
- **Use Case:** Workers send scraped data here for processing

#### 3. api-normalizer (Port 4203)
- **Purpose:** Drug name normalization
- **Endpoints:** POST /api/scraper/online_pharmacy_drugs/update_normalized_attributes
- **Worker:** No
- **Use Case:** Normalize product names to standardized values

#### 4. api-scraper (Port 4204)
- **Purpose:** Full scraping operations
- **Endpoints:** Full scraping API (create drugs, pharmacies, category scraping)
- **Worker:** Yes (api-scraper-sidekiq)
- **Use Case:** Orchestrate category scraping, create new entities

### Sidekiq Workers
- **api-product-write-sidekiq:** Background processing for product updates
- **api-scraper-sidekiq:** Background processing for scraping operations

## Technical Specifications

### Common Configuration
- **Base Image:** cheaperfordrug-api:latest (same as main API)
- **Network:** host mode (direct access to PostgreSQL and Redis)
- **Database:** PostgreSQL on localhost:5432
  - Database: cheaperfordrug_production
  - User: cheaperfordrug_user
- **Redis:** localhost:6379/2 (shared with main API)
- **Health Check:** /up endpoint on each web container
- **Logs:** Shared with main API in ${LOG_DIR}/logs

### Resource Settings
- **RAILS_MAX_THREADS:** 5
- **WEB_CONCURRENCY:** 2
- **SIDEKIQ_CONCURRENCY:** 10

### Deployment Pattern
- Uses existing Rails 8 application
- No new Dockerfiles needed
- Follows existing deployment conventions
- Works on both Hetzner (production) and macOS (development)

## How to Deploy

### On Hetzner Server (Production)

```bash
# SSH to server
ssh andrzej@your-hetzner-server

# Navigate to DevOps directory
cd /home/andrzej/DevOps/apps/cheaperfordrug-api

# Verify prerequisites
./verify-dedicated-api.sh

# Start containers
./deploy-dedicated-api.sh start

# Verify health
./deploy-dedicated-api.sh health
```

### On Local Development (macOS)

```bash
# Navigate to DevOps directory
cd /Users/andrzej/Development/CheaperForDrug/DevOps/apps/cheaperfordrug-api

# Ensure main API is deployed first
./deploy.sh deploy

# Start dedicated containers
./deploy-dedicated-api.sh start

# Check status
./deploy-dedicated-api.sh status
```

## Deployment Workflow

### First-Time Setup

1. **Deploy main API** (builds the Docker image)
   ```bash
   ./deploy.sh deploy
   ```

2. **Verify image exists**
   ```bash
   docker images cheaperfordrug-api:latest
   ```

3. **Start dedicated containers**
   ```bash
   ./deploy-dedicated-api.sh start
   ```

4. **Verify all healthy**
   ```bash
   ./deploy-dedicated-api.sh health
   ```

### Updating

When you update the main API:

```bash
# 1. Deploy new main API version
./deploy.sh deploy

# 2. Restart dedicated containers
./deploy-dedicated-api.sh restart

# 3. Verify
./deploy-dedicated-api.sh health
```

## Management Commands

### Basic Operations
```bash
./deploy-dedicated-api.sh start      # Start all containers
./deploy-dedicated-api.sh stop       # Stop all containers
./deploy-dedicated-api.sh restart    # Restart all containers
./deploy-dedicated-api.sh status     # Show container status
./deploy-dedicated-api.sh health     # Check health of all containers
```

### Monitoring
```bash
./deploy-dedicated-api.sh logs                    # All logs
./deploy-dedicated-api.sh logs product-read       # Specific container
./deploy-dedicated-api.sh logs product-write-sidekiq  # Worker logs
```

### Verification
```bash
./verify-dedicated-api.sh  # Check prerequisites and status
```

## Testing Endpoints

### Health Checks
```bash
curl http://localhost:4201/up  # Product Read
curl http://localhost:4202/up  # Product Write
curl http://localhost:4203/up  # Normalizer
curl http://localhost:4204/up  # Scraper
```

### API Endpoints
```bash
# Get pending products (Product Read)
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

## Integration with Scraper

Configure your scraper workers to use these dedicated endpoints:

### Python Example
```python
API_CONFIG = {
    'base_urls': {
        'product_read': 'http://localhost:4201',
        'product_write': 'http://localhost:4202',
        'normalizer': 'http://localhost:4203',
        'scraper': 'http://localhost:4204',
    }
}
```

### Worker Configuration
Each worker should:
1. Poll api-product-read (4201) for pending products
2. Scrape pharmacy websites
3. Send updates to api-product-write (4202)
4. Use api-normalizer (4203) for standardization
5. Use api-scraper (4204) for category operations

## Separation from Main API

### Main API Deployment (Unchanged)
- **Location:** Same directory
- **Ports:** 3020-3022 (behind nginx)
- **Access:** Public via api-public.cheaperfordrug.com, api-internal.cheaperfordrug.com
- **Workers:** 1 Sidekiq worker for general background jobs
- **Management:** ./deploy.sh

### Dedicated API Containers (New)
- **Location:** Same directory, separate docker-compose file
- **Ports:** 4201-4204 (direct access, no nginx)
- **Access:** Internal/localhost only
- **Workers:** 2 Sidekiq workers (product-write, scraper)
- **Management:** ./deploy-dedicated-api.sh

### Shared Resources
Both deployments share:
- Docker image (cheaperfordrug-api:latest)
- Database (PostgreSQL on localhost:5432)
- Redis (localhost:6379/2)
- Environment configuration (.env.production)
- Logs directory

## Container Naming

| Service | Container Name | Port | Type |
|---------|---------------|------|------|
| Product Read | cheaperfordrug-api-product-read | 4201 | Web |
| Product Write | cheaperfordrug-api-product-write | 4202 | Web |
| Product Write Worker | cheaperfordrug-api-product-write-sidekiq | - | Worker |
| Normalizer | cheaperfordrug-api-normalizer | 4203 | Web |
| Scraper | cheaperfordrug-api-scraper | 4204 | Web |
| Scraper Worker | cheaperfordrug-api-scraper-sidekiq | - | Worker |

## Monitoring & Health

### Status Check
```bash
./deploy-dedicated-api.sh status
```

Shows:
- Container name
- Running status
- Port
- Uptime

### Health Check
```bash
./deploy-dedicated-api.sh health
```

Tests:
- Web container health endpoints (/up)
- Worker container status
- Overall system health

### Logs
```bash
# All containers
./deploy-dedicated-api.sh logs

# Specific container
./deploy-dedicated-api.sh logs product-read
./deploy-dedicated-api.sh logs scraper-sidekiq
```

## Troubleshooting

### Common Issues

1. **Image not found**
   - Deploy main API first: `./deploy.sh deploy`

2. **Ports in use**
   - Check: `lsof -i :4201`
   - Stop conflicting service or change ports

3. **Database connection failed**
   - Verify PostgreSQL: `sudo systemctl status postgresql`
   - Check credentials in .env.production

4. **Redis connection failed**
   - Verify Redis: `sudo systemctl status redis`
   - Check REDIS_URL in .env.production

5. **Health check failing**
   - Check logs: `./deploy-dedicated-api.sh logs <container>`
   - Verify database and Redis connectivity
   - Check container is running: `docker ps`

### Debug Steps

1. Run verification script:
   ```bash
   ./verify-dedicated-api.sh
   ```

2. Check container logs:
   ```bash
   ./deploy-dedicated-api.sh logs
   ```

3. Test individual services:
   ```bash
   curl -v http://localhost:4201/up
   ```

4. Check database connectivity:
   ```bash
   docker exec cheaperfordrug-api-product-read \
     /bin/bash -c "cd /app && bundle exec rails runner 'puts ActiveRecord::Base.connection.active?'"
   ```

## Production Checklist

Before deploying to production:

- [ ] Main API deployed and running
- [ ] .env.production configured with production credentials
- [ ] PostgreSQL running and accessible
- [ ] Redis running and accessible
- [ ] Ports 4201-4204 available
- [ ] Firewall rules configured (if needed)
- [ ] Log directory has proper permissions
- [ ] Run verification script: `./verify-dedicated-api.sh`

## Security Notes

- Containers use host network mode
- No external exposure (not behind nginx)
- Access restricted to localhost
- Same security context as main API
- Shared database credentials
- No additional firewall rules needed

## Performance Considerations

### Scaling
Each container can be scaled independently by:
1. Duplicating service in docker-compose-dedicated-api.yml
2. Changing container name and port
3. Load balancing at application level

### Resource Usage
- Each web container: ~200-500 MB RAM
- Each worker: ~300-600 MB RAM
- Total: ~2-3 GB RAM for all 6 containers

### Optimization Tips
- Monitor Sidekiq queue sizes
- Adjust SIDEKIQ_CONCURRENCY if needed
- Scale read operations independently
- Use connection pooling

## Next Steps

1. **Deploy to Production**
   ```bash
   ssh andrzej@hetzner
   cd /home/andrzej/DevOps/apps/cheaperfordrug-api
   ./deploy-dedicated-api.sh start
   ```

2. **Configure Scraper**
   - Update scraper configuration to use new endpoints
   - Test with small batch first
   - Monitor logs and performance

3. **Monitor & Optimize**
   - Watch container logs
   - Monitor Sidekiq queues
   - Adjust concurrency if needed
   - Scale individual services as required

## Support Documentation

- **Full Documentation:** README-DEDICATED-API.md
- **Quick Reference:** QUICKSTART-DEDICATED-API.md
- **This Summary:** DEPLOYMENT-SUMMARY.md

## Summary

Successfully created a complete deployment system for 4 dedicated API containers:

✓ Docker Compose configuration
✓ Deployment scripts with health checks
✓ Verification and testing tools
✓ Comprehensive documentation
✓ Integration guides
✓ Troubleshooting procedures

The system is ready to deploy on both Hetzner (production) and local macOS (development) environments.

All containers use the existing Rails application image and follow the established deployment patterns from the main API.
