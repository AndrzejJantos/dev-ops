# CheaperForDrug API - Container Management & Python Scripts Access

## Overview

The CheaperForDrug API runs in Docker containers with **host networking** to enable direct access to PostgreSQL, Redis, and Elasticsearch running on the host machine.

## Current Setup (November 2025)

### Active Containers
- `cheaperfordrug-api_web_1` - Puma web server on port 3000
- `cheaperfordrug-api_web_2` - Puma web server on port 3001  
- `cheaperfordrug-api_web_3` - Puma web server on port 3002
- `cheaperfordrug-api_worker_1` - Sidekiq background worker

### Container Configuration
```yaml
Network Mode: host
Restart Policy: unless-stopped
DATABASE_URL: postgresql://user:pass@localhost/db_name
REDIS_URL: redis://localhost:6379/2
ELASTICSEARCH_URL: http://localhost:9200
```

## Why Host Networking?

**Problem**: On native Linux (Ubuntu/Hetzner), Docker bridge networking cannot access host services via `host.docker.internal` (this only works on Docker Desktop/macOS).

**Solution**: Use `--network host` which allows containers to access `localhost` directly, bypassing Docker's network isolation.

**Trade-off**: With host networking, each web container must listen on a **different port** to avoid conflicts.

## Adding New API Web Containers

### Step 1: Choose a unique port
- web_1 uses port 3000
- web_2 uses port 3001  
- web_3 uses port 3002
- **New container**: use port 3003, 3004, etc.

### Step 2: Create the container

```bash
# For web container on port 3004:
docker run -d \
  --name cheaperfordrug-api_web_4 \
  --network host \
  --env-file /home/andrzej/DevOps/apps/cheaperfordrug-api/.env.production \
  -e PORT=3004 \
  --restart unless-stopped \
  cheaperfordrug-api:latest
```

### Step 3: Verify it's running

```bash
# Check container status
docker ps --filter 'name=cheaperfordrug-api_web'

# Check the container is listening on correct port
docker logs --tail 5 cheaperfordrug-api_web_4 | grep Listening

# Test the endpoint
curl http://localhost:3004/up
```

### Step 4: Update nginx load balancer (if needed)

If using nginx for load balancing, add the new port to the upstream configuration:

```nginx
upstream cheaperfordrug_api {
    server localhost:3000;
    server localhost:3001;
    server localhost:3002;
    server localhost:3004;  # Add new port
}
```

Then reload nginx:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Adding Worker Containers

Workers don't bind to ports, so you can add multiple workers without port conflicts:

```bash
docker run -d \
  --name cheaperfordrug-api_worker_2 \
  --network host \
  --env-file /home/andrzej/DevOps/apps/cheaperfordrug-api/.env.production \
  --restart unless-stopped \
  cheaperfordrug-api:latest \
  bundle exec sidekiq
```

## Running Python Drug Normalizer Scripts

### Quick Start

```bash
cd /home/andrzej/apps/cheaperfordrug-scraper
./run-python-script.sh python_scripts/poland/drug_name_normalizer.py --keywords apap --max-pages 1
```

### Configuration

The helper script `/home/andrzej/apps/cheaperfordrug-scraper/run-python-script.sh` automatically sets:

```bash
export API_BASE_URL="http://localhost:3000"
export SCRAPER_AUTH_TOKEN="Andrzej12345"
```

### Available Python Scripts

- `python_scripts/poland/drug_name_normalizer.py` - Polish drug name normalizer
- `python_scripts/germany/drug_name_normalizer.py` - German drug name normalizer  
- `python_scripts/czech/drug_name_normalizer.py` - Czech drug name normalizer

### Manual Execution

```bash
cd /home/andrzej/apps/cheaperfordrug-scraper

# Set environment variables
export API_BASE_URL="http://localhost:3000"
export SCRAPER_AUTH_TOKEN="Andrzej12345"

# Run the script
python3 python_scripts/poland/drug_name_normalizer.py --keywords apap --max-pages 1
```

## API Authentication

All scraper API endpoints require Bearer token authentication:

```bash
curl -H "Authorization: Bearer Andrzej12345" \
  "http://localhost:3000/api/scraper/online_pharmacy_drugs?country_code=PL&page=1&per_page=3"
```

## Troubleshooting

### Container won't start - "Address already in use"

**Cause**: Another container is already using that port with host networking.

**Solution**: 
1. Check which ports are in use: `docker ps --filter 'name=cheaperfordrug-api'`
2. Choose a different PORT environment variable
3. Remove conflicting container: `docker rm -f cheaperfordrug-api_web_X`

### Database connection errors

**Symptoms**: HTTP 500 errors, "Connection refused" in logs

**Check**:
```bash
# Verify DATABASE_URL uses localhost (not host.docker.internal)
docker exec cheaperfordrug-api_web_1 env | grep DATABASE_URL

# Should show: postgresql://...@localhost/...
# NOT: postgresql://...@host.docker.internal/...
```

**Fix**: Update `/home/andrzej/DevOps/apps/cheaperfordrug-api/.env.production` and restart containers.

### Python scripts getting 401 Unauthorized

**Check**: Verify SCRAPER_AUTH_TOKEN in the .env.production file:
```bash
grep SCRAPER_AUTH_TOKEN /home/andrzej/DevOps/apps/cheaperfordrug-api/.env.production
```

**Fix**: Add or update `SCRAPER_AUTH_TOKEN=Andrzej12345` and restart API containers.

## Container Management Commands

```bash
# View all API containers
docker ps -a --filter 'name=cheaperfordrug-api'

# View container logs
docker logs -f cheaperfordrug-api_web_1

# Restart a container
docker restart cheaperfordrug-api_web_1

# Stop and remove a container
docker stop cheaperfordrug-api_web_1 && docker rm cheaperfordrug-api_web_1

# Check container network configuration
docker inspect cheaperfordrug-api_web_1 --format='NetworkMode={{.HostConfig.NetworkMode}}'
```

## Performance Optimizations Applied

### Database Indexes (November 2025)

Added indexes for DISTINCT ON queries used by drug normalizers:

```sql
CREATE INDEX CONCURRENTLY index_online_pharmacy_drugs_on_name 
  ON online_pharmacy_drugs(name);
  
CREATE INDEX CONCURRENTLY index_online_pharmacy_drugs_on_normalized_name 
  ON online_pharmacy_drugs(normalized_name);
  
CREATE INDEX CONCURRENTLY index_online_pharmacy_drugs_on_pharmacy_and_name 
  ON online_pharmacy_drugs(online_pharmacy_id, name);
  
CREATE INDEX CONCURRENTLY index_online_pharmacies_on_country_id 
  ON online_pharmacies(country_id);
```

**Result**: Query performance improved from 60+ seconds to ~0.5ms

## Environment Files

- **API Configuration**: `/home/andrzej/DevOps/apps/cheaperfordrug-api/.env.production`
- **Scraper Configuration**: `/home/andrzej/apps/cheaperfordrug-scraper/.env`
- **Helper Script**: `/home/andrzej/apps/cheaperfordrug-scraper/run-python-script.sh`

---

**Last Updated**: November 13, 2025
**Maintained by**: DevOps Team
