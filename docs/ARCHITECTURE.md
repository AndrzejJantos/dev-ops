# Rails Application Architecture Patterns

This DevOps infrastructure supports flexible container architectures for Rails applications. Configure your app based on its needs.

## Architecture Patterns

### 1. Simple Landing/Marketing Site

**Use case:** Static pages, forms, no background processing needed

**Configuration:**
```bash
export DEFAULT_SCALE=2         # 2 web containers
export WORKER_COUNT=0          # No workers (disabled)
export SCHEDULER_ENABLED=false # No scheduler (disabled)
```

**Containers deployed:**
- ✓ 2 web containers (Puma) - handles HTTP requests
- ✗ No worker containers
- ✗ No scheduler container

**Example apps:**
- Landing pages
- Marketing sites
- Simple brochure sites
- Pre-launch pages

---

### 2. Application with Background Jobs

**Use case:** User-facing app with async processing (emails, reports, notifications)

**Configuration:**
```bash
export DEFAULT_SCALE=2         # 2 web containers
export WORKER_COUNT=1          # 1 worker container
export SCHEDULER_ENABLED=false # No scheduler (one-off jobs only)
```

**Containers deployed:**
- ✓ 2 web containers (Puma) - handles HTTP requests
- ✓ 1 worker container (Sidekiq) - processes background jobs
- ✗ No scheduler container

**Example apps:**
- SaaS applications
- E-commerce sites
- User dashboards
- CMS platforms

**Typical background jobs:**
- Send welcome emails
- Generate reports
- Process payments
- Import/export data
- Image processing

---

### 3. Full Application with Scheduled Tasks

**Use case:** Complete app with recurring scheduled jobs

**Configuration:**
```bash
export DEFAULT_SCALE=2         # 2 web containers
export WORKER_COUNT=1          # 1 worker container
export SCHEDULER_ENABLED=true  # Enable scheduler
```

**Containers deployed:**
- ✓ 2 web containers (Puma) - handles HTTP requests
- ✓ 1 worker container (Sidekiq) - processes background jobs
- ✓ 1 scheduler container (Clockwork) - schedules recurring tasks

**Example apps:**
- Analytics platforms
- Subscription services
- Monitoring systems
- Newsletter platforms

**Typical scheduled tasks:**
- Send daily digests (every day at 9 AM)
- Generate weekly reports (Mondays at 8 AM)
- Cleanup old data (daily at 2 AM)
- Check subscription expirations (hourly)
- Send reminder emails (every 6 hours)

---

### 4. High-Traffic Application

**Use case:** Heavy traffic, many concurrent users, lots of background processing

**Configuration:**
```bash
export DEFAULT_SCALE=4         # 4 web containers
export WORKER_COUNT=2          # 2 worker containers
export SCHEDULER_ENABLED=true  # Enable scheduler
```

**Containers deployed:**
- ✓ 4 web containers (Puma) - handles HTTP requests
- ✓ 2 worker containers (Sidekiq) - processes background jobs
- ✓ 1 scheduler container (Clockwork) - schedules recurring tasks

**Example apps:**
- High-traffic SaaS
- Real-time applications
- API services
- Marketplace platforms

---

## Container Types Explained

### Web Containers (Puma)

**Command:** `bundle exec puma -C config/puma.rb` (default from Dockerfile)

**Purpose:** Handle HTTP requests from users

**Features:**
- Port exposed (3010, 3011, 3012, etc.)
- Behind nginx load balancer
- Zero-downtime deployments with rolling restarts
- Scalable (can run 1-10+ containers)

**When to scale up:**
- High traffic volume
- Slow response times
- CPU/memory maxing out
- Multiple concurrent users

### Worker Containers (Sidekiq)

**Command:** `bundle exec sidekiq`

**Purpose:** Process background jobs asynchronously

**Features:**
- No port exposure (internal only)
- Connects to Redis for job queue
- Processes jobs from web containers
- Can scale horizontally

**When to enable:**
- Sending emails
- Generating reports
- Processing uploads
- External API calls
- Long-running tasks

**When to scale up:**
- Job queue backing up
- Jobs taking too long
- High job volume
- Need better throughput

### Scheduler Container (Clockwork)

**Command:** `bundle exec clockwork config/clock.rb`

**Purpose:** Schedule recurring tasks at specific times

**Features:**
- No port exposure (internal only)
- Single container (no scaling needed)
- Enqueues jobs to Sidekiq at scheduled times
- Runs continuously checking schedule

**When to enable:**
- Daily/weekly/monthly tasks
- Time-based notifications
- Recurring reports
- Periodic cleanups
- Scheduled emails

**Note:** You need workers (Sidekiq) for scheduler to work, since Clockwork enqueues jobs to the job queue.

---

## Configuration Examples

### cheaperfordrug-landing (Landing Page)

```bash
# apps/cheaperfordrug-landing/config.sh
export DEFAULT_SCALE=2         # 2 web containers
export WORKER_COUNT=0          # No workers needed
export SCHEDULER_ENABLED=false # No scheduled tasks
```

**Result:**
- 2 web containers handling page views
- No background processing
- Minimal resource usage
- Perfect for static content with forms

### cheaperfordrug-api (Full SaaS)

```bash
# apps/cheaperfordrug-api/config.sh (example)
export DEFAULT_SCALE=3         # 3 web containers
export WORKER_COUNT=2          # 2 workers for jobs
export SCHEDULER_ENABLED=true  # Enable scheduled tasks
```

**Result:**
- 3 web containers (ports 3020-3022)
- 2 worker containers processing jobs
- 1 scheduler for recurring tasks
- Complete architecture for production SaaS

---

## How Containers Work Together

```
┌──────────────────────────────────────────────────┐
│            Nginx (Reverse Proxy)                 │
│              Port 80/443 (HTTPS)                 │
└────────────────┬─────────────────────────────────┘
                 │
        ┌────────┴────────┐
        ▼                 ▼
┌──────────────┐  ┌──────────────┐
│ Web 1 (3010) │  │ Web 2 (3011) │  ← User requests
└──────┬───────┘  └──────┬───────┘
       │                 │
       │  Enqueue jobs   │
       └────────┬────────┘
                ▼
        ┌────────────────┐
        │ Redis (Queue)  │  ← Job queue + cache
        └────────┬───────┘
                 │
        ┌────────┴────────┐
        ▼                 ▼
┌──────────────┐  ┌──────────────┐
│  Worker 1    │  │  Worker 2    │  ← Process jobs
└──────────────┘  └──────────────┘
        ▲
        │ Enqueue scheduled jobs
        │
┌──────────────┐
│  Scheduler   │  ← Check schedule, enqueue jobs
└──────────────┘
        │
        ▼
┌──────────────┐
│  PostgreSQL  │  ← Shared database
└──────────────┘
```

---

## Deployment Behavior

All enabled containers are managed together:

```bash
./deploy.sh deploy    # Deploy all configured containers
./deploy.sh restart   # Restart all containers
./deploy.sh stop      # Stop all containers
./deploy.sh rollback  # Rollback all containers
```

**What happens during deployment:**

1. Pull latest code
2. Build Docker image (same for all container types)
3. Deploy web containers (zero-downtime rolling restart)
4. Run migrations (if needed)
5. Deploy worker containers (if `WORKER_COUNT > 0`)
6. Deploy scheduler container (if `SCHEDULER_ENABLED = true`)
7. Cleanup old images

**All containers:**
- Use the same Docker image
- Override CMD with different commands
- Share environment variables from `.env.production`
- Access the same database and Redis
- Auto-restart on failure

---

## Changing Architecture

To change your app's architecture, simply update `config.sh`:

### Enable workers for existing landing page:

```bash
# Edit config.sh
export WORKER_COUNT=1  # Change from 0 to 1

# Deploy
./deploy.sh deploy
```

### Disable scheduler:

```bash
# Edit config.sh
export SCHEDULER_ENABLED=false  # Change from true to false

# Deploy (scheduler will be removed)
./deploy.sh deploy
```

### Scale up web containers:

```bash
# Option 1: Temporary scale
./deploy.sh scale 4

# Option 2: Permanent change in config.sh
export DEFAULT_SCALE=4
./deploy.sh deploy
```

---

## Monitoring

### View logs by container type:

```bash
# Web containers
docker logs cheaperfordrug-landing_web_1 -f
docker logs cheaperfordrug-landing_web_2 -f

# Worker containers (if enabled)
docker logs cheaperfordrug-landing_worker_1 -f

# Scheduler container (if enabled)
docker logs cheaperfordrug-landing_scheduler -f
```

### Check all running containers:

```bash
docker ps --filter "name=cheaperfordrug-landing"
```

---

## Best Practices

### Start Simple
- Begin with just web containers
- Add workers when you need background processing
- Add scheduler when you have recurring tasks
- Scale up as traffic grows

### Monitor Resource Usage
- Watch CPU/memory per container type
- Scale the bottleneck (web vs worker)
- Don't over-provision unnecessarily

### Separate Concerns
- Web: Fast responses, delegate heavy work
- Workers: Process async jobs
- Scheduler: Enqueue jobs at specific times

### Testing
- Test each architecture locally first
- Verify workers pick up jobs
- Check scheduler creates jobs correctly
- Monitor job queue depth

---

## Examples in This Repository

| App | Web | Workers | Scheduler | Use Case |
|-----|-----|---------|-----------|----------|
| cheaperfordrug-landing | 2 | 0 | No | Landing page (no jobs) |
| cheaperfordrug-api (example) | 3 | 2 | Yes | Full SaaS with jobs |
| future-analytics-app (example) | 4 | 3 | Yes | High-traffic analytics |

---

## Need Help?

See deployment configuration in each app:
- `apps/<app-name>/config.sh` - Container architecture settings
- `apps/<app-name>/deployment-info.txt` - Generated after setup, shows current config

Check logs:
- `~/apps/<app-name>/logs/deployments.log` - Deployment history
- `docker logs <container-name>` - Container output
