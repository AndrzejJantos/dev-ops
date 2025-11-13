# Global Container Management Patterns for Rails API Applications on Linux

## Overview

This document defines the standardized patterns for deploying and managing Rails API applications in Docker containers on **native Linux** (Ubuntu/Hetzner). These patterns are specifically designed to address the networking requirements on Linux servers where Docker Desktop networking features are not available.

**Last Updated**: November 13, 2025
**Applies To**: All Rails API applications on Ubuntu/Hetzner infrastructure

---

## Table of Contents

- [Critical Networking Requirements](#critical-networking-requirements)
- [Why Host Networking?](#why-host-networking)
- [Port Allocation Strategy](#port-allocation-strategy)
- [Container Naming Conventions](#container-naming-conventions)
- [Scaling Patterns](#scaling-patterns)
- [Database Connectivity Pattern](#database-connectivity-pattern)
- [Configuration Template](#configuration-template)
- [Deployment Workflow](#deployment-workflow)
- [Troubleshooting](#troubleshooting)
- [Adding New Applications](#adding-new-applications)

---

## Critical Networking Requirements

### The Linux Docker Networking Challenge

**Problem**: On native Linux, Docker containers in bridge mode **cannot access host services** via `host.docker.internal`. This hostname only works on Docker Desktop (macOS/Windows).

**Impact**: Rails applications need to connect to:
- PostgreSQL on `localhost:5432`
- Redis on `localhost:6379`
- Elasticsearch on `localhost:9200`

**Solution**: Use `--network host` mode, which allows containers to directly access `localhost` services.

### Required Database Connection Pattern

```bash
# ✅ CORRECT for host networking on Linux
DATABASE_URL=postgresql://user:password@localhost/database_name
REDIS_URL=redis://localhost:6379/0
ELASTICSEARCH_URL=http://localhost:9200

# ❌ WRONG - Does NOT work on native Linux
DATABASE_URL=postgresql://user:password@host.docker.internal/database_name
REDIS_URL=redis://host.docker.internal:6379/0
```

---

## Why Host Networking?

### Benefits

1. **Direct localhost Access**: Containers can connect to PostgreSQL, Redis, Elasticsearch on `localhost`
2. **No Network Translation**: Eliminates Docker network overhead
3. **Simplified Configuration**: No need for special gateway addresses
4. **Production Performance**: Native network stack performance

### Trade-offs

1. **Port Management Required**: Each web container needs a unique `PORT` environment variable
2. **No Port Mapping**: Container port IS the host port (no `-p 3020:3000`)
3. **Careful Planning**: Port conflicts will prevent containers from starting

---

## Port Allocation Strategy

### Port Range Allocation

Each application is allocated a port range based on its base port:

```
Application Base Port Pattern:
- {app-name}_web_1   = BASE_PORT + 0
- {app-name}_web_2   = BASE_PORT + 1
- {app-name}_web_3   = BASE_PORT + 2
- {app-name}_web_N   = BASE_PORT + (N-1)
```

### Current Port Allocations

| Application | Base Port | Range | Nginx Proxy Port |
|------------|-----------|-------|------------------|
| cheaperfordrug-api | 3020 | 3020-3029 | 443 (SSL) |
| brokik-api | 3000 | 3000-3009 | 443 (SSL) |
| **Reserved for Future** | 3030 | 3030-3039 | TBD |
| **Reserved for Future** | 3040 | 3040-3049 | TBD |
| **Reserved for Future** | 3050 | 3050-3059 | TBD |

### Port Allocation Rules

1. **Reserve 10 ports** per application (allows scaling to 10 web containers)
2. **Base ports** should be multiples of 10 for clarity
3. **Document allocations** in this file when adding new applications
4. **Avoid port conflicts** - check `netstat -tuln` before allocating

### Checking Available Ports

```bash
# Check if port is in use
nc -z localhost 3020 && echo "IN USE" || echo "AVAILABLE"

# List all used ports
netstat -tuln | grep LISTEN

# Check all app containers
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

---

## Container Naming Conventions

### Standard Container Names

```
{app-name}_web_{number}      # Web/API containers (e.g., cheaperfordrug-api_web_1)
{app-name}_worker_{number}   # Background job workers (e.g., cheaperfordrug-api_worker_1)
{app-name}_scheduler_{number} # Scheduled task containers (if using Clockwork)
```

### Examples

```
cheaperfordrug-api_web_1      # Primary API container
cheaperfordrug-api_web_2      # Secondary API container
cheaperfordrug-api_web_3      # Third API container
cheaperfordrug-api_worker_1   # Background job worker
```

### Naming Rules

1. Use underscores, not hyphens, to separate components
2. Container numbers start at 1 (not 0)
3. Keep names consistent with application name in config.sh
4. Workers and schedulers don't expose ports (no number conflicts)

---

## Scaling Patterns

### Web Container Scaling

**Pattern**: Each web container runs on a unique port with host networking

```bash
# config.sh settings
export BASE_PORT=3020
export DEFAULT_SCALE=3

# Resulting containers
docker run -d \
  --name ${APP_NAME}_web_1 \
  --network host \
  -e PORT=3020 \
  --env-file .env.production \
  ${APP_NAME}:latest

docker run -d \
  --name ${APP_NAME}_web_2 \
  --network host \
  -e PORT=3021 \
  --env-file .env.production \
  ${APP_NAME}:latest

docker run -d \
  --name ${APP_NAME}_web_3 \
  --network host \
  -e PORT=3022 \
  --env-file .env.production \
  ${APP_NAME}:latest
```

### Worker Container Scaling

**Pattern**: Workers don't expose ports, can scale independently

```bash
# config.sh settings
export WORKER_COUNT=2

# Resulting containers (no port configuration needed)
docker run -d \
  --name ${APP_NAME}_worker_1 \
  --network host \
  --env-file .env.production \
  ${APP_NAME}:latest \
  bundle exec sidekiq

docker run -d \
  --name ${APP_NAME}_worker_2 \
  --network host \
  --env-file .env.production \
  ${APP_NAME}:latest \
  bundle exec sidekiq
```

### Nginx Load Balancer Configuration

**Pattern**: Upstream block with all web container ports

```nginx
upstream cheaperfordrug_api_backend {
    server localhost:3020;  # web_1
    server localhost:3021;  # web_2
    server localhost:3022;  # web_3
}

server {
    listen 443 ssl http2;
    server_name api-public.cheaperfordrug.com;

    location / {
        proxy_pass http://cheaperfordrug_api_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Scaling Commands

```bash
# Scale to 3 web containers
cd /home/andrzej/DevOps/apps/{app-name}
./deploy.sh scale 3

# Scale to 5 web containers
./deploy.sh scale 5

# Check current scale
docker ps --filter "name={app-name}_web" --format "table {{.Names}}\t{{.Ports}}"
```

---

## Database Connectivity Pattern

### Environment Configuration

**File**: `/home/andrzej/DevOps/apps/{app-name}/.env.production`

```bash
# Database Configuration - MUST use localhost with host networking
DATABASE_URL=postgresql://user:password@localhost/database_name
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_NAME=app_production
DATABASE_USER=app_user
DATABASE_PASSWORD=secure_random_password

# Redis Configuration - MUST use localhost
REDIS_URL=redis://localhost:6379/0
REDIS_DB_NUMBER=0

# Elasticsearch Configuration - MUST use localhost (if enabled)
ELASTICSEARCH_URL=http://localhost:9200
ENABLE_ELASTICSEARCH=true

# Rails Configuration
RAILS_ENV=production
RAILS_MAX_THREADS=2
RAILS_SERVE_STATIC_FILES=false
RAILS_LOG_TO_STDOUT=true
```

### Container Creation Pattern

```bash
docker run -d \
  --name ${APP_NAME}_web_1 \
  --network host \
  --env-file /home/andrzej/DevOps/apps/${APP_NAME}/.env.production \
  -e PORT=3020 \
  --restart unless-stopped \
  ${APP_NAME}:latest
```

### Connection Testing

```bash
# Test from inside container
docker exec ${APP_NAME}_web_1 bash -c "cd /app && bundle exec rails runner 'puts ActiveRecord::Base.connection.execute(\"SELECT 1\").first'"

# Test Redis connection
docker exec ${APP_NAME}_web_1 bash -c "redis-cli -h localhost ping"

# Test via API endpoint
curl http://localhost:3020/up
```

---

## Configuration Template

### config.sh Template for New Rails API

```bash
#!/bin/bash

# Application Configuration for {App Name}
# This is a Rails API backend

# ============================================================================
# APPLICATION IDENTITY
# ============================================================================
export APP_TYPE="rails"
export APP_NAME="{app-name}"              # e.g., "myapp-api"
export APP_DISPLAY_NAME="{App Display Name}"  # e.g., "MyApp API"
export DOMAIN="{domain.com}"               # e.g., "api.example.com"

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================
export REPO_URL="git@github.com:{org}/{repo}.git"
export REPO_BRANCH="master"

# ============================================================================
# CONTAINER ARCHITECTURE
# ============================================================================
export DEFAULT_SCALE=2              # Number of web containers
export WORKER_COUNT=1               # Number of worker containers
export SCHEDULER_ENABLED=false      # Set true if using Clockwork
export WORKER_SHUTDOWN_TIMEOUT=90

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================
export DOCKER_IMAGE_NAME="$APP_NAME"
export BASE_PORT={BASE_PORT}        # e.g., 3030 (allocate unique base port)
export CONTAINER_PORT=3000          # Rails default - don't change

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================
export DB_NAME="{app}_production"
export DB_USER="{app}_user"
export DB_HOST="localhost"          # CRITICAL: Must be localhost for host networking
export DB_PORT="5432"

# ============================================================================
# REDIS CONFIGURATION
# ============================================================================
export REDIS_DB_NUMBER={N}          # Allocate unique Redis DB number (0-15)
export REDIS_URL="redis://localhost:6379/${REDIS_DB_NUMBER}"

# ============================================================================
# DEPLOYMENT CONFIGURATION
# ============================================================================
export ZERO_DOWNTIME_ENABLED=true
export HEALTH_CHECK_PATH="/up"
export HEALTH_CHECK_TIMEOUT=60

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================
export BACKUP_ENABLED=true
export MIGRATION_BACKUP_ENABLED=true
export BACKUP_RETENTION_DAYS=30

# ============================================================================
# IMAGE BACKUP CONFIGURATION
# ============================================================================
export SAVE_IMAGE_BACKUPS=true
export MAX_IMAGE_BACKUPS=20

# ============================================================================
# AUTO CLEANUP
# ============================================================================
export AUTO_CLEANUP_ENABLED=true
export MAX_IMAGE_VERSIONS=20

# ============================================================================
# NGINX CONFIGURATION
# ============================================================================
export NGINX_UPSTREAM_NAME="${APP_NAME}_backend"

# ============================================================================
# PATHS (Auto-configured - Do not modify)
# ============================================================================
export APP_DIR="$HOME/apps/$APP_NAME"
export REPO_DIR="$APP_DIR/repo"
export ENV_FILE="$APP_DIR/.env.production"
export BACKUP_DIR="$APP_DIR/backups"
export LOG_DIR="$APP_DIR/logs"
export IMAGE_BACKUP_DIR="$APP_DIR/docker-images"
```

---

## Deployment Workflow

### 1. Initial Setup

```bash
# Create app directory in DevOps
cd /home/andrzej/DevOps/apps
cp -r ../templates/rails-app {new-app-name}
cd {new-app-name}

# Edit config.sh with app-specific settings
nano config.sh

# Run setup (creates database, generates configs, builds first image)
./setup.sh
```

### 2. Deploy Application

```bash
# Deploy latest code
./deploy.sh deploy

# Check container status
./deploy.sh status

# View logs
./deploy.sh logs web_1
```

### 3. Scale Application

```bash
# Scale to 3 web containers
./deploy.sh scale 3

# Verify all containers running
docker ps --filter "name={app-name}"
```

---

## Troubleshooting

### Container Won't Start - "Address already in use"

**Cause**: Another container is using the port with host networking

**Solution**:
```bash
# Check which ports are in use
docker ps --filter 'name={app-name}' --format "table {{.Names}}\t{{.Ports}}"

# Find process using the port
lsof -i :3020

# Stop conflicting container
docker rm -f {container-name}
```

### Database Connection Refused

**Symptoms**: HTTP 500 errors, "Connection refused" in logs

**Check**:
```bash
# Verify DATABASE_URL uses localhost (NOT host.docker.internal)
docker exec {app-name}_web_1 env | grep DATABASE_URL
# Should show: postgresql://...@localhost/...

# Test PostgreSQL is listening
psql -h localhost -U {db_user} -d {db_name} -c "SELECT 1"
```

**Fix**:
```bash
# Update .env.production
nano /home/andrzej/DevOps/apps/{app-name}/.env.production
# Change @host.docker.internal to @localhost

# Restart containers
./deploy.sh restart
```

### API Requests Timing Out

**Possible Causes**:
1. Database connection pool exhaustion
2. Slow queries without indexes
3. Network connectivity issues

**Diagnosis**:
```bash
# Check container logs
docker logs {app-name}_web_1 --tail 100

# Check database query performance
docker exec {app-name}_web_1 bash -c "cd /app && bundle exec rails runner '
puts Benchmark.measure {
  ActiveRecord::Base.connection.execute(\"SELECT COUNT(*) FROM your_table\")
}'"

# Check connection pool
docker exec {app-name}_web_1 bash -c "cd /app && bundle exec rails runner '
puts ActiveRecord::Base.connection_pool.stat
'"
```

### Nginx Shows No Upstream Servers Available

**Cause**: Nginx configuration not updated after scaling

**Fix**:
```bash
# Rebuild nginx configurations
cd /home/andrzej/DevOps
./rebuild-nginx-configs.sh

# Or update manually
cd /home/andrzej/DevOps/apps/{app-name}
./deploy.sh deploy  # This updates nginx config automatically
```

---

## Adding New Applications

### Port Allocation Checklist

1. **Choose base port**: Find next available port range (check table above)
2. **Reserve 10 ports**: BASE_PORT to BASE_PORT+9
3. **Update port table**: Add entry to "Current Port Allocations" section
4. **Document in DevOps**: Update this file with the allocation

### Redis DB Number Allocation

Redis supports 16 databases (0-15). Allocate one per application:

| Application | Redis DB |
|------------|----------|
| cheaperfordrug-api | 2 |
| brokik-api | 0 |
| **Available** | 1, 3-15 |

### Setup Steps

1. Copy rails-app template
2. Edit config.sh with unique:
   - APP_NAME
   - BASE_PORT (from allocation table)
   - REDIS_DB_NUMBER (from allocation table)
   - DOMAIN
3. Run `./setup.sh`
4. Run `./deploy.sh deploy`
5. Update this document with allocations

---

## Best Practices

### 1. Always Use Host Networking for Rails APIs

```bash
# ✅ CORRECT
docker run -d --network host --env-file .env.production ...

# ❌ WRONG - Will not work on Linux
docker run -d --network bridge -p 3020:3000 ...
```

### 2. Always Use localhost in Database URLs

```bash
# ✅ CORRECT
DATABASE_URL=postgresql://user:pass@localhost/db

# ❌ WRONG - Does not work on native Linux
DATABASE_URL=postgresql://user:pass@host.docker.internal/db
```

### 3. Set Unique PORT for Each Web Container

```bash
# ✅ CORRECT - Each container has unique PORT
docker run -d --name app_web_1 -e PORT=3020 ...
docker run -d --name app_web_2 -e PORT=3021 ...

# ❌ WRONG - Port conflict
docker run -d --name app_web_1 -e PORT=3020 ...
docker run -d --name app_web_2 -e PORT=3020 ...  # Will fail!
```

### 4. Update Nginx After Scaling

```bash
# After scaling containers
./deploy.sh scale 3

# Nginx is automatically updated by deploy.sh
# But if needed manually:
cd /home/andrzej/DevOps
./rebuild-nginx-configs.sh
```

### 5. Monitor Container Health

```bash
# Regular health checks
docker ps --filter "name={app-name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check health endpoint
curl http://localhost:3020/up

# View recent logs
docker logs {app-name}_web_1 --tail 50 --follow
```

---

## Performance Optimization

### Database Indexes

For DISTINCT ON queries on large tables, always add appropriate indexes:

```ruby
# migration
add_index :table_name, :column_name
add_index :table_name, [:fk_id, :column_name]
```

**Example** (from cheaperfordrug-api):
```sql
CREATE INDEX CONCURRENTLY index_online_pharmacy_drugs_on_name
  ON online_pharmacy_drugs(name);

CREATE INDEX CONCURRENTLY index_online_pharmacy_drugs_on_pharmacy_and_name
  ON online_pharmacy_drugs(online_pharmacy_id, name);
```

Result: Query time reduced from 60+ seconds to 0.5ms

### Connection Pooling

Configure Rails database pool based on container count and traffic:

```ruby
# config/database.yml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
```

```bash
# .env.production
RAILS_MAX_THREADS=2  # 2 threads per container × 3 containers = 6 total connections
```

### Redis Configuration

Optimize Redis for your workload:

```bash
# For Streams workloads
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly yes
```

---

## Quick Reference

### Common Commands

```bash
# Deploy latest code
cd /home/andrzej/DevOps/apps/{app-name} && ./deploy.sh deploy

# Scale to N containers
./deploy.sh scale N

# Restart all containers
./deploy.sh restart

# View logs
./deploy.sh logs web_1

# Check status
./deploy.sh status

# Rails console
./deploy.sh console

# Check all apps status
cd /home/andrzej/DevOps/apps && ./status.sh

# Rebuild all nginx configs
cd /home/andrzej/DevOps && ./rebuild-nginx-configs.sh
```

### Container Management

```bash
# List all app containers
docker ps -a --filter 'name={app-name}'

# View logs
docker logs -f {app-name}_web_1

# Execute command in container
docker exec {app-name}_web_1 bash -c "cd /app && bundle exec rails runner 'puts User.count'"

# Stop and remove container
docker stop {app-name}_web_1 && docker rm {app-name}_web_1

# Check network mode
docker inspect {app-name}_web_1 --format='NetworkMode={{.HostConfig.NetworkMode}}'
```

---

## Summary

**Key Principles**:

1. ✅ **Always use `--network host`** for Rails APIs on Linux
2. ✅ **Always use `localhost`** in DATABASE_URL, REDIS_URL, ELASTICSEARCH_URL
3. ✅ **Assign unique PORT** environment variable for each web container
4. ✅ **Allocate port ranges** (10 ports per app) to avoid conflicts
5. ✅ **Update nginx** configuration when scaling containers
6. ✅ **Document allocations** in this file when adding new applications

**Never**:
- ❌ Don't use `host.docker.internal` on Linux (Docker Desktop only)
- ❌ Don't use bridge networking for Rails APIs needing host service access
- ❌ Don't reuse ports across different web containers
- ❌ Don't forget to update nginx after scaling

---

**Maintained By**: DevOps Team
**Questions**: Refer to `/home/andrzej/DevOps/README.md` for detailed deployment workflows
