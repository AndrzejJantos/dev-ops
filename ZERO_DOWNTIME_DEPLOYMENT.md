# Zero-Downtime Deployment Strategy

This document explains the health check-based deployment strategy implemented in the CheaperForDrug DevOps infrastructure.

## Overview

The deployment system ensures that new application versions are fully healthy before traffic is switched to them. This provides:

- **Zero-downtime deployments** for applications with multiple instances
- **Automated rollback** if health checks fail
- **Health verification** before and after deployment
- **Consistent deployment** across all applications

## How It Works

### 1. Rolling Restart Strategy (Web/API Applications)

For applications deployed with `deploy.sh` (Rails API, Next.js apps), the system uses a rolling restart approach:

#### Step-by-Step Process:

1. **Temporary Container Start**
   - New container starts with a `_new` suffix on a temporary port
   - Example: `cheaperfordrug-api_web_1_new` on port 4101

2. **Health Check Verification**
   - System waits up to 60 seconds for container to pass health checks
   - Checks `/up`, `/`, and `/api/health` endpoints
   - Accepts HTTP 2xx or 3xx responses
   - If health check fails, deployment stops and container is removed

3. **Traffic Switch**
   - Old container stops (e.g., `cheaperfordrug-api_web_1`)
   - Temporary container stops
   - New container starts with correct name on production port
   - Final health check verification

4. **Gradual Rollout**
   - Process repeats for each container instance (web_1, web_2, etc.)
   - 5-second pause between containers to allow traffic to stabilize
   - Other containers continue serving traffic during each switch

#### Configuration Example:

```bash
# DevOps/common/docker-utils.sh (lines 487-562)
rolling_restart() {
    # For each container:
    # 1. Start new container on temp port
    # 2. Wait for health check (60 sec max)
    # 3. Stop old container
    # 4. Start new container on correct port
    # 5. Final health check
    # 6. Wait 5 seconds before next container
}
```

### 2. Docker Compose Health Checks (Scraper Application)

For Docker Compose applications, health checks are verified after container restart:

#### Process:

1. **Container Restart**
   - `docker compose down` stops old containers
   - `docker compose up -d` starts new containers with new image

2. **Health Check Wait**
   - System calls `wait_for_compose_health` function
   - Checks Docker's built-in health status for each container
   - Waits up to 60 seconds (configurable via `HEALTH_CHECK_TIMEOUT`)
   - Monitors: "starting" → "healthy" or "unhealthy"

3. **Deployment Decision**
   - If all containers healthy: Deployment succeeds
   - If any container unhealthy: Deployment fails, sends error notification
   - If timeout: Deployment fails with detailed status report

#### Configuration Example:

```yaml
# docker-compose.yml
healthcheck:
  test: ["CMD", "/usr/local/bin/healthcheck.sh"]
  interval: 60s
  timeout: 10s
  retries: 3
  start_period: 120s
```

```bash
# DevOps/apps/cheaperfordrug-scraper/setup.sh (lines 458-468)
wait_for_compose_health "${CONTAINER_POLAND}" "${CONTAINER_GERMANY}" "${CONTAINER_CZECH}"
```

### 3. Nginx Passive Health Monitoring

Nginx continuously monitors upstream servers and automatically removes unhealthy instances from the load balancer pool.

#### Configuration:

```nginx
upstream app_backend {
    least_conn;

    # Passive health monitoring
    server localhost:4000 max_fails=3 fail_timeout=30s;
    server localhost:4001 max_fails=3 fail_timeout=30s;

    # Keep alive connections
    keepalive 32;
    keepalive_timeout 60s;
}
```

#### Parameters:

- **max_fails=3**: After 3 failed requests, mark server as down
- **fail_timeout=30s**: Keep server marked as down for 30 seconds
- After 30 seconds, nginx will retry the server
- **least_conn**: Route to server with fewest active connections

## Health Check Endpoints

### Rails Applications

**Endpoint:** `/up`

```ruby
# config/routes.rb
get "up" => "rails/health#show", as: :rails_health_check
```

**Response:**
- HTTP 200: Application is healthy
- Checks: Database connectivity, Redis connectivity (if applicable)

### Next.js Applications

**Endpoint:** `/api/health` or `/up`

```typescript
// pages/api/health.ts
export default function handler(req, res) {
  res.status(200).json({ status: 'ok' })
}
```

### Docker Compose Applications

**Healthcheck Script:** `/usr/local/bin/healthcheck.sh`

```bash
#!/bin/bash
# Example healthcheck for scraper
if pgrep -f "node.*scraper" > /dev/null; then
    exit 0  # Healthy
else
    exit 1  # Unhealthy
fi
```

## Deployment Commands

### Web/API Applications

```bash
# Deploy with health checks
./deploy.sh deploy

# The script will:
# 1. Pull latest code
# 2. Build new Docker image
# 3. Perform rolling restart with health verification
# 4. Update nginx if needed
# 5. Setup SSL if needed
```

### Scraper Application

```bash
# Deploy with health checks
./setup.sh --deploy

# The script will:
# 1. Pull latest code
# 2. Build new Docker image
# 3. Restart containers
# 4. Wait for all containers to become healthy
# 5. Send email notification with result
```

## Monitoring Health Checks

### Check Container Health

```bash
# For individual containers
docker inspect --format='{{.State.Health.Status}}' container_name

# For all app containers
./deploy.sh status
```

### Check Nginx Upstream Status

```bash
# Check nginx configuration
sudo nginx -t

# View active connections
curl http://localhost/nginx_status  # If configured
```

### View Deployment Logs

```bash
# Web/API applications
docker logs cheaperfordrug-api_web_1 -f

# Scraper applications
./setup.sh --logs
```

## Troubleshooting

### Deployment Fails During Health Check

**Symptom:** Deployment stops with "Container failed health check"

**Solution:**
1. Check container logs: `docker logs container_name --tail 50`
2. Verify health endpoint manually: `curl http://localhost:PORT/up`
3. Check for:
   - Database connection issues
   - Missing environment variables
   - Application startup errors
   - Port conflicts

### Container Marked as Unhealthy

**Symptom:** `docker inspect` shows "unhealthy" status

**Solution:**
1. Review healthcheck configuration in Dockerfile or docker-compose.yml
2. Test healthcheck command manually:
   ```bash
   docker exec container_name /usr/local/bin/healthcheck.sh
   echo $?  # Should be 0 for healthy
   ```
3. Check healthcheck timing:
   - `start_period`: Time before first check (increase if app is slow to start)
   - `interval`: Time between checks (increase for resource-constrained systems)
   - `retries`: Number of failures before marking unhealthy

### Nginx Not Routing to New Container

**Symptom:** Old version still serving traffic after deployment

**Solution:**
1. Verify nginx configuration updated:
   ```bash
   sudo nginx -t
   cat /etc/nginx/sites-available/app_name
   ```
2. Check upstream port mapping matches containers:
   ```bash
   docker ps | grep app_name
   ```
3. Reload nginx:
   ```bash
   sudo systemctl reload nginx
   ```

## Configuration

### Health Check Timeouts

```bash
# In your shell or deployment script
export HEALTH_CHECK_TIMEOUT=120  # Wait up to 120 seconds

# Default: 60 seconds
```

### Nginx Health Check Parameters

Edit `DevOps/common/deploy-app.sh` (line 146):

```bash
UPSTREAM_SERVERS="${UPSTREAM_SERVERS}    server localhost:${port} max_fails=3 fail_timeout=30s;\n"
```

Adjust:
- **max_fails**: Higher = more tolerant of transient failures
- **fail_timeout**: Longer = slower to retry failed servers

### Docker Health Check Parameters

Edit `docker-compose.yml`:

```yaml
healthcheck:
  interval: 60s      # How often to check
  timeout: 10s       # How long to wait for response
  retries: 3         # Failures before marking unhealthy
  start_period: 120s # Grace period during startup
```

## Best Practices

### 1. Design Robust Health Checks

✅ **Good:**
```ruby
# Check critical dependencies
def health_check
  database.connected? && redis.connected?
end
```

❌ **Bad:**
```ruby
# Just return 200
def health_check
  true
end
```

### 2. Set Appropriate Timeouts

- **start_period**: 2x typical startup time
- **interval**: 30-60 seconds for most apps
- **timeout**: 5-10 seconds
- **retries**: 3-5 attempts

### 3. Monitor Deployment Success

- Check deployment logs after each deploy
- Set up alerts for failed health checks
- Review `deployments.log` regularly

### 4. Test Health Checks

Before deploying:

```bash
# Test health endpoint
curl http://localhost:PORT/up -v

# Test in Docker
docker run --rm -it app_image:latest curl http://localhost:3000/up
```

### 5. Gradual Rollouts

For critical applications:

1. Start with scale=2
2. Deploy to one container, verify
3. If healthy, deploy to remaining containers
4. Monitor for 5-10 minutes before considering stable

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Deployment Process                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Build New Image                                          │
│     └─> Docker build with timestamp tag                     │
│                                                              │
│  2. Rolling Restart (for each container)                     │
│     ├─> Start temp container on temp port                   │
│     ├─> Wait for health check (60s max) ✓                   │
│     ├─> Stop old container                                  │
│     ├─> Start new container on production port              │
│     ├─> Final health check (60s max) ✓                      │
│     └─> Wait 5s, repeat for next container                  │
│                                                              │
│  3. Nginx Health Monitoring (continuous)                     │
│     ├─> max_fails=3                                         │
│     ├─> fail_timeout=30s                                    │
│     └─> Automatically removes unhealthy upstreams           │
│                                                              │
└─────────────────────────────────────────────────────────────┘

                           │
                           ▼

┌─────────────────────────────────────────────────────────────┐
│                   Traffic Flow                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  User Request                                                │
│       │                                                      │
│       ▼                                                      │
│  Nginx (Port 80/443)                                         │
│       │                                                      │
│       ├─> Load Balancer (least_conn)                        │
│       │                                                      │
│       ├─> Container 1 (Port 4000) ✓ Healthy                 │
│       ├─> Container 2 (Port 4001) ✓ Healthy                 │
│       └─> Container 3 (Port 4002) ✗ Unhealthy (skipped)     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Rollback Procedure

If a deployment causes issues, you can quickly rollback to a previous version.

### How Rollback Works

The system maintains multiple Docker image versions tagged with timestamps:
- `cheaperfordrug-api:20241106_143025`
- `cheaperfordrug-api:20241106_120530`
- `cheaperfordrug-api:latest` (always points to most recent deployment)

### Rollback Command

```bash
./deploy.sh rollback
```

**Interactive Process:**

1. Shows currently deployed version
2. Lists all available previous versions with timestamps
3. You select which version to rollback to
4. Confirms before proceeding
5. Performs rolling restart with health check verification
6. Logs the rollback operation

**Example Session:**

```bash
$ ./deploy.sh rollback

================================================================
Rollback CheaperForDrug API
================================================================

[INFO] Currently deployed version: 20241106_143025

[INFO] Available Docker images for CheaperForDrug API:

#    VERSION (TAG)         CREATED               SIZE
--------------------------------------------------------------
1    20241106_143025       2024-11-06 14:30:25   1.2GB
2    20241106_120530       2024-11-06 12:05:30   1.2GB
3    20241105_183045       2024-11-05 18:30:45   1.1GB
4    20241105_091520       2024-11-05 09:15:20   1.1GB

Enter the version number to rollback to (or 'cancel' to abort):
> 2

================================================================
Rolling Back CheaperForDrug API
================================================================

[INFO] Current version: 20241106_143025
[INFO] Target version:  20241106_120530

Continue with rollback? (yes/no): yes

[INFO] Tagging cheaperfordrug-api:20241106_120530 as latest...
[INFO] Performing rolling restart to version 20241106_120530...
[INFO] Restarting container 1/2 on port 4000 (zero-downtime deployment)
[INFO] Starting new container cheaperfordrug-api_web_1_new on temporary port 4002
[INFO] Verifying health of new container before switching...
[SUCCESS] New container is healthy, now switching traffic...
[INFO] Stopping old container cheaperfordrug-api_web_1
[SUCCESS] Container cheaperfordrug-api_web_1 restarted successfully and is healthy
[INFO] Waiting 5 seconds before next container...
[INFO] Restarting container 2/2 on port 4001 (zero-downtime deployment)
...
[SUCCESS] Rollback completed successfully!

Summary:
  Previous version: 20241106_143025
  Current version:  20241106_120530
  Running containers: 2

To verify:
  ./deploy.sh status
  curl https://api-public.cheaperfordrug.com
```

### Preserving Images for Rollback

By default, old images are cleaned up automatically. To preserve more versions:

```bash
# Edit config.sh
AUTO_CLEANUP_ENABLED=true
MAX_IMAGE_VERSIONS=10  # Keep last 10 versions (default: 3)
```

Or disable cleanup entirely:

```bash
AUTO_CLEANUP_ENABLED=false
```

### Manual Rollback to Specific Version

If you know the exact version tag:

```bash
# Tag the specific version as latest
docker tag cheaperfordrug-api:20241106_120530 cheaperfordrug-api:latest

# Restart containers
./deploy.sh restart
```

### Rollback Safety

- Uses same zero-downtime rolling restart process
- Verifies health checks before switching traffic
- Automatically stops if health checks fail
- Logs all rollback operations to `deployments.log`

### When to Rollback

Common scenarios:

1. **New bugs discovered**: Rollback immediately to restore service
2. **Performance degradation**: Return to known stable version
3. **Failed health checks**: Automatic (new deployment won't complete)
4. **User-reported issues**: Quick rollback while investigating

### Post-Rollback Actions

After rolling back:

1. **Verify service is working**: `curl https://your-domain.com`
2. **Check container status**: `./deploy.sh status`
3. **Review logs**: `./deploy.sh logs`
4. **Investigate the issue**: Determine what went wrong
5. **Fix and redeploy**: Address the issue before deploying again

## Summary

The zero-downtime deployment strategy ensures:

1. **Safety**: New containers verified healthy before receiving traffic
2. **Reliability**: Automatic rollback if health checks fail
3. **Continuity**: Traffic served by healthy containers during deployment
4. **Monitoring**: Continuous health checks via Docker and Nginx
5. **Visibility**: Detailed logging and status reporting
6. **Recoverability**: Quick rollback to any previous version

For questions or issues, check the troubleshooting section or review deployment logs in `~/apps/APP_NAME/logs/deployments.log`.
