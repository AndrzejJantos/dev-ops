# Dedicated API Containers - Cheat Sheet

## Quick Deploy

```bash
# First time
./deploy.sh deploy                    # Build main API image
./deploy-dedicated-api.sh start       # Start dedicated containers
./deploy-dedicated-api.sh health      # Verify all healthy

# Updates
./deploy.sh deploy                    # Update & build new image
./deploy-dedicated-api.sh restart     # Restart with new image
```

## Container Ports

| Port | Service | Worker | Purpose |
|------|---------|--------|---------|
| 4201 | Product Read | No | Poll for pending products |
| 4202 | Product Write | Yes | Batch updates, lock management |
| 4203 | Normalizer | No | Drug name normalization |
| 4204 | Scraper | Yes | Full scraping operations |

## Common Commands

```bash
# Management
./deploy-dedicated-api.sh start      # Start all
./deploy-dedicated-api.sh stop       # Stop all
./deploy-dedicated-api.sh restart    # Restart all
./deploy-dedicated-api.sh status     # Show status
./deploy-dedicated-api.sh health     # Health check

# Logs
./deploy-dedicated-api.sh logs                   # All containers
./deploy-dedicated-api.sh logs product-read      # Specific container
./deploy-dedicated-api.sh logs scraper-sidekiq   # Worker logs

# Verification
./verify-dedicated-api.sh            # Check prerequisites
```

## Test Endpoints

```bash
# Health checks
curl http://localhost:4201/up
curl http://localhost:4202/up
curl http://localhost:4203/up
curl http://localhost:4204/up

# API calls
curl http://localhost:4201/api/scraper/online_pharmacy_drugs/pending_updates?batch_size=10
```

## Container Names

```
cheaperfordrug-api-product-read
cheaperfordrug-api-product-write
cheaperfordrug-api-product-write-sidekiq
cheaperfordrug-api-normalizer
cheaperfordrug-api-scraper
cheaperfordrug-api-scraper-sidekiq
```

## Scraper Integration

```python
API_ENDPOINTS = {
    'product_read': 'http://localhost:4201',
    'product_write': 'http://localhost:4202',
    'normalizer': 'http://localhost:4203',
    'scraper': 'http://localhost:4204',
}
```

## Troubleshooting

```bash
# Check if running
docker ps | grep cheaperfordrug-api

# Check logs
./deploy-dedicated-api.sh logs product-read

# Test database
docker exec cheaperfordrug-api-product-read \
  /bin/bash -c "cd /app && bundle exec rails runner 'puts ActiveRecord::Base.connection.active?'"

# Check ports
lsof -i :4201
```

## Files

- `docker-compose-dedicated-api.yml` - Container config
- `deploy-dedicated-api.sh` - Management script
- `verify-dedicated-api.sh` - Verification
- `README-DEDICATED-API.md` - Full docs
- `QUICKSTART-DEDICATED-API.md` - Quick guide
- `DEPLOYMENT-SUMMARY.md` - Complete summary
- `ARCHITECTURE-DIAGRAM.txt` - Architecture
- `CHEATSHEET.md` - This file

## Architecture

```
Main API (ports 3020-3022) → Nginx → Public access
  + 1 Sidekiq worker

Dedicated API (ports 4201-4204) → Direct localhost access
  + 2 Sidekiq workers (product-write, scraper)

Shared: PostgreSQL, Redis, Docker image, logs
```

## Production Deploy

```bash
ssh andrzej@hetzner
cd /home/andrzej/DevOps/apps/cheaperfordrug-api
./deploy-dedicated-api.sh start
./deploy-dedicated-api.sh health
```

## Local Development

```bash
cd /Users/andrzej/Development/CheaperForDrug/DevOps/apps/cheaperfordrug-api
./deploy-dedicated-api.sh start
./deploy-dedicated-api.sh status
```

## Help

```bash
./deploy-dedicated-api.sh help
```
