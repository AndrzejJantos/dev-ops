# Multi-Platform Database Connectivity Guide

## Overview

Rails applications in this project need to connect to PostgreSQL databases running on the host machine. We use a **universal solution** with `host.docker.internal` that works identically on all platforms.

## The Problem

When running Rails in Docker containers:

- **Linux (Production)**: Uses `--network host` mode
  - Container shares host network namespace
  - `localhost` in container = `localhost` on host ✅
  - BUT: Different configuration than dev ❌

- **macOS/Windows (Development)**: Docker runs in a VM
  - `--network host` doesn't work the same way
  - `localhost` in container ≠ `localhost` on host ❌
  - Need special hostname: `host.docker.internal` ✅

**Problem**: Different configurations for dev vs production = complexity and bugs.

## The Universal Solution ✨

We use **`host.docker.internal` everywhere** with Docker's `--add-host` flag:

### All Platforms (Production & Development)

```bash
# .env.production and .env.development
DB_HOST=host.docker.internal
DATABASE_URL=postgresql://user:password@${DB_HOST}:5432/db_name
REDIS_URL=redis://host.docker.internal:6379/3
```

### Docker Run Configuration

All containers are started with `--add-host`:

```bash
docker run -d \
    --add-host=host.docker.internal:host-gateway \
    --env-file .env.production \
    ...
```

**How it works:**
- `host-gateway` is Docker's special value that resolves to the host's IP
- On **Linux**: maps to host's IP (e.g., 172.17.0.1)
- On **macOS/Windows**: uses Docker Desktop's built-in `host.docker.internal`
- **Result**: Same configuration works everywhere! 🎉

## Configuration Files

### 1. Production Templates (.env.production.template)

Templates are pre-configured with `host.docker.internal`:

```bash
# DevOps/apps/brokik-api/.env.production.template
# DevOps/apps/cheaperfordrug-api/.env.production.template

DB_HOST=host.docker.internal
DATABASE_URL=postgresql://user:password@${DB_HOST}:5432/db_name
REDIS_URL=redis://host.docker.internal:6379/3
```

**Universal configuration - works on all platforms!**

### 2. Development Configuration (.env.development)

Uses the same configuration:

```bash
# brokik-api/.env.development

DB_HOST=host.docker.internal
REDIS_URL=redis://host.docker.internal:6379/0
```

### 3. Database Configuration (config/database.yml)

Rails configuration uses `DB_HOST` with sensible defaults:

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch("DB_HOST", "localhost") %>
  port: <%= ENV.fetch("POSTGRES_PORT", "5432") %>
  username: <%= ENV.fetch("POSTGRES_USER", "postgres") %>
  password: <%= ENV.fetch("POSTGRES_PASSWORD", "") %>

development:
  <<: *default
  database: brokik_api_development

production:
  <<: *default
  url: <%= ENV["DATABASE_URL"] %>  # Uses DB_HOST from env
```

## Platform-Specific Setup

### All Platforms (Universal Setup)

#### 1. PostgreSQL Configuration

PostgreSQL must listen on all interfaces to accept connections from Docker containers:

**Edit `postgresql.conf`:**
```ini
listen_addresses = '*'
```

**Edit `pg_hba.conf`:**
```
# Allow Docker containers
host    all    all    172.17.0.0/16    md5
host    all    all    192.168.65.0/24  md5  # Docker Desktop network
```

**Restart PostgreSQL:**
```bash
# macOS
brew services restart postgresql@14

# Linux
sudo systemctl restart postgresql
```

#### 2. Redis Configuration (Optional)

Same as PostgreSQL - ensure Redis accepts connections from Docker:

**Edit `redis.conf`:**
```ini
bind 0.0.0.0
```

#### 3. Docker Deployment

**DevOps scripts automatically add `--add-host`** - no manual configuration needed!

All containers are started via `DevOps/common/docker-utils.sh` which includes:
```bash
--add-host=host.docker.internal:host-gateway
```

### Platform Notes

#### macOS (Docker Desktop)
- ✅ Works out of the box
- `host.docker.internal` is natively supported
- `--add-host` ensures compatibility

#### Linux (Production)
- ✅ Works with `--add-host=host.docker.internal:host-gateway`
- Docker maps `host.docker.internal` to the Docker bridge gateway IP
- Same configuration as dev - no special handling needed!

#### Windows (Docker Desktop)
- ✅ Same as macOS
- `host.docker.internal` is natively supported

## Testing Database Connectivity

### From Host Machine
```bash
psql -h localhost -U postgres -d brokik_api_development
```

### From Docker Container
```bash
# All platforms - same command!
docker run --rm -it --add-host=host.docker.internal:host-gateway postgres:14 \
  psql -h host.docker.internal -U postgres -d brokik_api_development
```

### From Rails Console
```bash
docker exec -it brokik-api_web_1 rails console

# In console:
ActiveRecord::Base.connection.execute("SELECT version();")
```

## Troubleshooting

### Connection Refused

**Problem:** Rails can't connect to PostgreSQL

**Solutions:**

1. **Verify PostgreSQL is running:**
   ```bash
   # macOS
   brew services list

   # Linux
   sudo systemctl status postgresql
   ```

2. **Check `listen_addresses` in postgresql.conf:**
   ```bash
   # macOS
   cat /opt/homebrew/var/postgresql@14/postgresql.conf | grep listen_addresses

   # Linux
   cat /etc/postgresql/14/main/postgresql.conf | grep listen_addresses
   ```
   Should show: `listen_addresses = '*'`

3. **Verify Docker can reach host:**
   ```bash
   docker run --rm --add-host=host.docker.internal:host-gateway alpine ping -c 3 host.docker.internal
   ```

4. **Check DB_HOST is set correctly:**
   ```bash
   docker exec brokik-api_web_1 env | grep DB_HOST
   ```
   Should show: `DB_HOST=host.docker.internal`

5. **Test from inside container:**
   ```bash
   docker exec -it brokik-api_web_1 /bin/bash
   curl -v telnet://host.docker.internal:5432
   ```

### Container can't resolve host.docker.internal

**Problem:** `getaddrinfo: Name or service not known`

**Solution:** Ensure `--add-host=host.docker.internal:host-gateway` is in docker run command.

**Check DevOps scripts:**
```bash
grep -r "add-host" /Users/andrzej/Development/Brokik/DevOps/common/docker-utils.sh
```

Should show the flag in all `docker run` commands.

### DATABASE_URL Not Interpolating

**Problem:** `${DB_HOST}` appears literally in logs

**Solution:** Ensure shell environment properly expands variables:

```bash
# WRONG (single quotes prevent expansion)
DATABASE_URL='postgresql://user:pass@${DB_HOST}:5432/db'

# RIGHT (double quotes allow expansion)
DATABASE_URL="postgresql://user:pass@${DB_HOST}:5432/db"

# BEST (let .env file handle it, no quotes)
DATABASE_URL=postgresql://user:pass@${DB_HOST}:5432/db
```

## Summary

| Platform | Network Mode | DB_HOST Value | --add-host Flag | Works? |
|----------|-------------|---------------|-----------------|--------|
| Linux Production | `--network host` | `host.docker.internal` | ✅ Required | ✅ |
| macOS Development | `bridge` | `host.docker.internal` | ✅ Required | ✅ |
| Windows Development | `bridge` | `host.docker.internal` | ✅ Required | ✅ |

**Key Principles:**
1. **One configuration everywhere**: `DB_HOST=host.docker.internal`
2. **Docker flag required**: `--add-host=host.docker.internal:host-gateway`
3. **No platform-specific logic**: Same .env file works on all platforms
4. **Automatically configured**: DevOps scripts handle `--add-host` automatically

## Benefits of This Approach

✅ **Universal**: Works on Linux, macOS, and Windows
✅ **Simple**: One configuration for all environments
✅ **Reliable**: No conditional logic or environment detection
✅ **Maintainable**: Developers and production use identical setup
✅ **Future-proof**: Works with any Docker networking mode
