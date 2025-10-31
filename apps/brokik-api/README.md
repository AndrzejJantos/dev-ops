# Brokik API Infrastructure

This directory contains the infrastructure configuration for the Brokik API backend application.

## Overview

- **Application Type**: Rails API with background processing
- **Domain**: api-public.brokik.com, api-internal.brokik.com
- **Container Architecture**: 2 web containers + 1 worker + 1 scheduler
- **Ports**: 3040-3042 (host side)
- **Redis Database**: 3
- **PostgreSQL Database**: brokik_production

## Architecture

The Brokik API uses a dual-subdomain architecture:

1. **api-public.brokik.com** - Public API endpoints (no authentication)
   - Open endpoints accessible to any client
   - Rate limiting applied
   - CORS configured for frontend domains

2. **api-internal.brokik.com** - Protected API endpoints (JWT authentication)
   - Requires valid JWT token
   - User-specific data and operations
   - Same backend containers (routing handled by Rails)

Both subdomains point to the same Docker containers - the routing logic is handled within the Rails application based on the requested path (`/api/public/*` vs `/api/internal/*`).

## Container Setup

- **Web Containers**: 2 instances (ports 3040, 3041)
  - Handle HTTP requests via Puma
  - Load balanced by nginx
  - Health check endpoint: `/up`

- **Worker Container**: 1 instance
  - Processes background jobs via Sidekiq
  - Handles emails, data processing, external API calls
  - 90 second graceful shutdown timeout

- **Scheduler Container**: 1 instance
  - Clockwork-based task scheduler
  - Enqueues recurring jobs (cleanup, reports, notifications)

## Files

- **config.sh** - Application configuration (ports, domains, scaling)
- **.env.production.template** - Environment variables template
- **nginx.conf.template** - Nginx configuration for both API subdomains
- **setup.sh** - Initial application setup script
- **deploy.sh** - Deployment script

## Initial Setup (First Time Only)

1. **SSH into the server**:
   ```bash
   ssh -p 2222 andrzej@your-server-ip
   ```

2. **Clone the DevOps repository** (if not already done):
   ```bash
   cd ~
   git clone git@github.com:YourOrg/DevOps.git
   ```

3. **Run the setup script**:
   ```bash
   cd ~/DevOps/apps/brokik-api
   ./setup.sh
   ```

   The setup script will:
   - Create application directory structure
   - Clone the application repository
   - Copy environment template
   - Prompt you to edit `.env.production` with production secrets
   - Set up PostgreSQL database and user
   - Configure Redis
   - Build Docker image
   - Set up nginx configuration
   - Obtain SSL certificates via Let's Encrypt
   - Start containers

4. **Edit production environment variables**:
   ```bash
   nano ~/apps/brokik-api/.env.production
   ```

   Update these critical values:
   - `SECRET_KEY_BASE` - Generate with `rails secret`
   - `DATABASE_URL` - Set database password
   - `POSTGRES_PASSWORD` - Match DATABASE_URL password
   - `JWT_SECRET_KEY` - Generate secure random key
   - `SMTP_PASSWORD` - Mailgun SMTP password
   - Add any required API keys

5. **Verify setup**:
   ```bash
   # Check containers are running
   docker ps | grep brokik-api

   # Check application health
   curl https://api-public.brokik.com/up
   curl https://api-internal.brokik.com/up

   # Check logs
   docker logs brokik-api_web_1
   ```

## Deployment

To deploy updates:

```bash
cd ~/DevOps/apps/brokik-api
./deploy.sh
```

The deployment process:
1. Pulls latest code from GitHub
2. Creates database backup (if migrations exist)
3. Builds new Docker image
4. Runs database migrations
5. Performs zero-downtime rolling restart
6. Validates container health
7. Updates nginx configuration
8. Saves Docker image backup

### Deployment Options

```bash
# Standard deployment
./deploy.sh

# Skip database backup
./deploy.sh --skip-backup

# Force rebuild (ignore cache)
./deploy.sh --force-rebuild

# Rollback to previous version
./deploy.sh --rollback
```

## DNS Configuration

Before deployment, ensure these DNS A records point to your server:

- `api-public.brokik.com` → Server IP
- `api-internal.brokik.com` → Server IP

## SSL Certificates

SSL certificates are automatically obtained and renewed via Let's Encrypt during:
- Initial setup
- Each deployment (if needed)

Certificates are stored in:
- `/etc/letsencrypt/live/api-public.brokik.com/`
- `/etc/letsencrypt/live/api-internal.brokik.com/`

## Database Management

### Create Database User (Manual - if not done by setup)

```bash
sudo -u postgres psql
CREATE USER brokik_user WITH PASSWORD 'your_secure_password';
CREATE DATABASE brokik_production OWNER brokik_user;
GRANT ALL PRIVILEGES ON DATABASE brokik_production TO brokik_user;
\q
```

### Backup Database

```bash
# Manual backup
pg_dump -U brokik_user brokik_production | gzip > backup.sql.gz

# Automatic backups are created before deployments with migrations
```

### Restore Database

```bash
# Restore from backup
gunzip -c backup.sql.gz | psql -U brokik_user brokik_production
```

## Monitoring

### Check Application Status

```bash
# Comprehensive status for all apps
~/DevOps/apps/status.sh

# Verify all domains
~/DevOps/verify-domains.sh

# Container logs
docker logs -f brokik-api_web_1
docker logs -f brokik-api_worker_1
docker logs -f brokik-api_scheduler_1

# Nginx logs
sudo tail -f /var/log/nginx/brokik-api-access.log
sudo tail -f /var/log/nginx/brokik-api-error.log
```

### Check Background Jobs

```bash
# SSH into web container
docker exec -it brokik-api_web_1 bash

# Open Rails console
rails console

# Check Sidekiq stats
Sidekiq::Stats.new
```

## Troubleshooting

### Containers Not Starting

```bash
# Check container status
docker ps -a | grep brokik-api

# View container logs
docker logs brokik-api_web_1

# Check if port is in use
sudo lsof -i :3040
```

### SSL Certificate Issues

```bash
# Verify certificate
sudo certbot certificates

# Manually renew
sudo certbot renew

# Test nginx configuration
sudo nginx -t

# Rebuild nginx configs
~/DevOps/rebuild-nginx-configs.sh
```

### Database Connection Issues

```bash
# Test database connection
psql -U brokik_user -d brokik_production -h localhost

# Check PostgreSQL service
sudo systemctl status postgresql

# View PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-*.log
```

### Worker/Scheduler Not Processing Jobs

```bash
# Check if containers are running
docker ps | grep brokik-api

# Check worker logs
docker logs -f brokik-api_worker_1

# Check Redis connection
redis-cli -n 3 ping

# Restart worker/scheduler
docker restart brokik-api_worker_1
docker restart brokik-api_scheduler_1
```

## Directory Structure

```
~/apps/brokik-api/
├── repo/                    # Git repository
├── .env.production          # Environment variables (never commit!)
├── backups/                 # Database backups
├── logs/                    # Application logs
└── docker-images/           # Docker image backups (.tar files)
```

## Environment Variables

See `.env.production.template` for complete list. Critical variables:

- **Database**: `DATABASE_URL`, `POSTGRES_*`
- **Redis**: `REDIS_URL`, `REDIS_CACHE_URL`
- **Security**: `SECRET_KEY_BASE`, `JWT_SECRET_KEY`
- **Email**: `SMTP_*` settings
- **CORS**: `ALLOWED_ORIGINS`, `FRONTEND_URL`

## Related Documentation

- Main DevOps README: `~/DevOps/README.md`
- Nginx configuration: `/etc/nginx/sites-available/brokik-api`
- Common utilities: `~/DevOps/common/`
