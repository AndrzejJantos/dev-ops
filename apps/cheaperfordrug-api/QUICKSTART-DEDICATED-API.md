# Quick Start Guide - Dedicated API Containers

## Prerequisites Check

```bash
# 1. Verify main API is deployed
docker images cheaperfordrug-api:latest

# 2. Check environment file exists
ls -la .env.production

# 3. Verify PostgreSQL and Redis are running
sudo systemctl status postgresql
sudo systemctl status redis
```

## Deploy in 3 Steps

### Step 1: Deploy Main API (if not already done)

```bash
cd /Users/andrzej/Development/CheaperForDrug/DevOps/apps/cheaperfordrug-api
./deploy.sh deploy
```

### Step 2: Start Dedicated Containers

```bash
./deploy-dedicated-api.sh start
```

### Step 3: Verify Everything Works

```bash
./deploy-dedicated-api.sh health
```

## Container Ports

| Service | Port | Worker | Endpoint |
|---------|------|--------|----------|
| Product Read | 4201 | No | `http://localhost:4201/up` |
| Product Write | 4202 | Yes | `http://localhost:4202/up` |
| Normalizer | 4203 | No | `http://localhost:4203/up` |
| Scraper | 4204 | Yes | `http://localhost:4204/up` |

## Common Commands

```bash
# Start all containers
./deploy-dedicated-api.sh start

# Stop all containers
./deploy-dedicated-api.sh stop

# Restart all containers
./deploy-dedicated-api.sh restart

# Show status
./deploy-dedicated-api.sh status

# Check health
./deploy-dedicated-api.sh health

# View all logs
./deploy-dedicated-api.sh logs

# View specific logs
./deploy-dedicated-api.sh logs product-read
./deploy-dedicated-api.sh logs product-write
./deploy-dedicated-api.sh logs product-write-sidekiq
./deploy-dedicated-api.sh logs normalizer
./deploy-dedicated-api.sh logs scraper
./deploy-dedicated-api.sh logs scraper-sidekiq
```

## Testing Endpoints

```bash
# Quick health check all ports
for port in 4201 4202 4203 4204; do
  curl -s http://localhost:$port/up && echo "Port $port: OK" || echo "Port $port: FAILED"
done

# Test specific endpoint
curl http://localhost:4201/api/scraper/online_pharmacy_drugs/pending_updates?batch_size=10
```

## Troubleshooting

### Containers won't start?

```bash
# Check prerequisites
./verify-dedicated-api.sh

# Check logs
./deploy-dedicated-api.sh logs

# Rebuild main API
./deploy.sh deploy
./deploy-dedicated-api.sh restart
```

### Port already in use?

```bash
# Find what's using the port
lsof -i :4201

# Stop the conflicting service or change ports in docker-compose-dedicated-api.yml
```

### Health check failing?

```bash
# Check container is running
docker ps | grep cheaperfordrug-api

# Check logs for errors
./deploy-dedicated-api.sh logs product-read

# Test database connection
docker exec cheaperfordrug-api-product-read \
  /bin/bash -c "cd /app && bundle exec rails runner 'puts ActiveRecord::Base.connection.active?'"
```

## Update Process

When updating the main API:

```bash
# 1. Deploy new main API version
./deploy.sh deploy

# 2. Restart dedicated containers
./deploy-dedicated-api.sh restart

# 3. Verify
./deploy-dedicated-api.sh health
```

## Files

- `docker-compose-dedicated-api.yml` - Container configuration
- `deploy-dedicated-api.sh` - Deployment script
- `verify-dedicated-api.sh` - Verification script
- `README-DEDICATED-API.md` - Full documentation
- `.env.production` - Environment variables (shared with main API)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Main API Deployment                   │
│                                                          │
│  Nginx (443) → 3x Web (3020-3022) + 1x Sidekiq Worker  │
│                                                          │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│              Dedicated API Containers                    │
│                                                          │
│  ┌─────────────────┬─────────────────┬─────────────┐   │
│  │ Product Read    │ Product Write   │ Normalizer  │   │
│  │ Port: 4201      │ Port: 4202      │ Port: 4203  │   │
│  │ No worker       │ + Worker        │ No worker   │   │
│  └─────────────────┴─────────────────┴─────────────┘   │
│                                                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │ Scraper                                         │   │
│  │ Port: 4204                                      │   │
│  │ + Worker                                        │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘

Both share: PostgreSQL (localhost:5432) + Redis (localhost:6379/2)
```

## API Usage in Scraper

Configure your scraper to use these endpoints:

```python
# Python example
API_CONFIG = {
    'base_urls': {
        'product_read': 'http://localhost:4201',
        'product_write': 'http://localhost:4202',
        'normalizer': 'http://localhost:4203',
        'scraper': 'http://localhost:4204',
    }
}

# Get pending products
response = requests.get(
    f"{API_CONFIG['base_urls']['product_read']}/api/scraper/online_pharmacy_drugs/pending_updates",
    params={'batch_size': 100}
)

# Update products
response = requests.post(
    f"{API_CONFIG['base_urls']['product_write']}/api/scraper/online_pharmacy_drugs/batch_update",
    json={'updates': [...]}
)
```

## Support

For detailed documentation, see: `README-DEDICATED-API.md`

For issues:
1. Run verification: `./verify-dedicated-api.sh`
2. Check logs: `./deploy-dedicated-api.sh logs`
3. Review status: `./deploy-dedicated-api.sh status`
