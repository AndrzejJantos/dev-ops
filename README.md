# CheaperForDrug DevOps Infrastructure

Comprehensive DevOps automation repository for managing the complete CheaperForDrug infrastructure on Ubuntu servers. This repository provides a production-ready, scalable deployment framework for both Rails APIs and Next.js applications with automated SSL management, nginx configuration, Docker containerization, and Redis Streams support.

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Core Scripts](#core-scripts)
- [Infrastructure Components](#infrastructure-components)
- [Application Management](#application-management)
- [Common Utilities](#common-utilities)
- [Templates](#templates)
- [Deployment Workflows](#deployment-workflows)
- [SSL Certificate Management](#ssl-certificate-management)
- [Database and Redis Setup](#database-and-redis-setup)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
- [Disaster Recovery](#disaster-recovery)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Best Practices](#best-practices)

---

## Overview

This DevOps repository is the central infrastructure management system for the CheaperForDrug platform. It provides:

- **Automated Server Initialization**: Complete Ubuntu server setup from scratch
- **Multi-Application Deployment**: Support for Rails APIs and Next.js frontends
- **Fully Automated SSL Management**: Let's Encrypt certificates are automatically checked, obtained, and renewed during every deployment - completely hands-off, no manual commands needed
- **Nginx Configuration**: Template-based, dynamic nginx configuration generation
- **Docker Orchestration**: Containerized applications with rolling updates
- **Redis Streams**: Optimized Redis configuration for streaming workloads
- **Database Management**: PostgreSQL setup, migrations, and backup automation
- **Zero-Downtime Deployments**: Rolling restarts with health checks
- **Disaster Recovery**: Complete system rebuild capability

### Technology Stack

- **OS**: Ubuntu (18.04, 20.04, 22.04, 24.04)
- **Web Server**: Nginx with SSL (Let's Encrypt)
- **Containerization**: Docker with Docker Compose
- **Backend**: Ruby on Rails, Node.js
- **Frontend**: Next.js (standalone mode)
- **Database**: PostgreSQL
- **Cache/Streams**: Redis 8+
- **SSL**: Certbot (Let's Encrypt)
- **Process Management**: Docker with health checks

---

## Repository Structure

```
DevOps/
├── apps/                           # Application-specific configurations
│   ├── cheaperfordrug-api/         # Rails API application
│   ├── cheaperfordrug-landing/     # Next.js landing pages
│   ├── cheaperfordrug-scraper/     # Scraper service
│   ├── cheaperfordrug-web/         # Next.js web application
│   └── status.sh                   # Multi-app status checker
├── common/                         # Shared utilities and modules
│   ├── app-types/                  # Application type modules
│   │   ├── nextjs.sh               # Next.js deployment logic
│   │   └── rails.sh                # Rails deployment logic
│   ├── nginx/                      # Nginx configurations
│   │   └── default-server.conf     # Default catch-all server
│   ├── nextjs/                     # Next.js templates
│   │   ├── .dockerignore.template  # Docker ignore for Next.js
│   │   └── Dockerfile.template     # Multi-stage Next.js build
│   ├── rails/                      # Rails templates
│   │   ├── .dockerignore.template  # Docker ignore for Rails
│   │   └── Dockerfile.template     # Multi-stage Rails build
│   ├── templates/                  # Configuration templates
│   │   └── redis.conf              # Redis Streams configuration
│   ├── deploy-app.sh               # Generic deployment workflow
│   ├── docker-utils.sh             # Docker container management
│   ├── redis-setup.sh              # Redis configuration utilities
│   ├── setup-app.sh                # Generic application setup
│   └── utils.sh                    # Common utility functions
├── scripts/                        # System-wide utilities
│   ├── cleanup-all-apps.sh         # Centralized cleanup automation
│   ├── disaster-recovery-config.example.sh  # DR configuration template
│   ├── disaster-recovery.sh        # Complete system rebuild
│   ├── update-redis.sh             # Redis upgrade utility
│   └── upgrade-ruby.sh             # Ruby version upgrade utility
├── templates/                      # Application templates
│   ├── nextjs-app/                 # Next.js application template
│   └── rails-app/                  # Rails application template
├── rebuild-nginx-configs.sh        # Rebuild all nginx configs
├── ubuntu-init-setup.sh            # Complete Ubuntu server initialization
└── verify-domains.sh               # Domain and SSL verification
```

### Application Directory Structure (apps/*)

Each application follows this structure:

```
apps/example-app/
├── config.sh                       # Application configuration
├── deploy.sh                       # Deployment commands
├── setup.sh                        # Initial setup
├── nginx.conf.template             # Nginx configuration template
└── [app-specific files]
```

---

## Core Scripts

### ubuntu-init-setup.sh

**Purpose**: Complete Ubuntu server initialization and hardening

**Features**:
- System package updates and upgrades
- User creation with sudo privileges and SSH key setup
- Hostname configuration
- UFW firewall setup (SSH, HTTP, HTTPS)
- Fail2ban installation for SSH protection
- Essential development tools (git, curl, wget, vim, htop, etc.)
- Node.js 20.x installation with Yarn
- Ruby 3.4.4 with rbenv and Rails
- PostgreSQL and Redis 8 installation
- Docker and Docker Compose setup
- Nginx web server installation
- Let's Encrypt SSL certificate automation
- System optimization (swap, file limits, auto-updates)
- SSH security hardening (custom port, key-only auth, root disabled)
- GitHub SSH key generation
- Timezone and locale configuration
- fzf fuzzy finder with CTRL+P mapping

**Usage**:
```bash
sudo ./ubuntu-init-setup.sh
```

**Configuration Variables** (edit in script):
- `USERNAME`: User to create (default: andrzej)
- `NEW_HOSTNAME`: Server hostname (default: webet)
- `SSH_PORT`: Custom SSH port (default: 2222)
- `TIMEZONE`: Server timezone (default: Europe/Warsaw)
- `RUBY_VERSION`: Ruby version (default: 3.4.4)
- `NODE_VERSION`: Node.js version (default: 20)
- `SWAP_SIZE`: Swap file size (default: 2G)

**Interactive Prompts**:
- User setup confirmation
- Hostname change confirmation
- Component installation confirmations
- SSL certificate setup
- GitHub SSH key generation
- SSH hardening (final step)

**Post-Setup**:
- Verify SSH access on new port before closing session
- Add GitHub SSH key to GitHub account
- Review installation log: `/var/log/server-init-setup.log`

---

### rebuild-nginx-configs.sh

**Purpose**: Rebuild all nginx configurations from templates with validation

**Features**:
- Discovers all applications with nginx templates
- Backs up existing configurations
- Removes old configurations (preserves defaults)
- Verifies container status and health
- Generates new configurations from templates
- Validates SSL certificates (expiry, coverage)
- Tests nginx configuration syntax
- Performs hot reload without downtime
- Provides rollback capability

**Usage**:
```bash
# Dry run to preview changes
./rebuild-nginx-configs.sh --dry-run

# Full rebuild with SSL validation
./rebuild-nginx-configs.sh

# Skip SSL checks
./rebuild-nginx-configs.sh --skip-ssl

# Force rebuild even if issues found
./rebuild-nginx-configs.sh --force
```

**Options**:
- `-d, --dry-run`: Preview changes without applying
- `-s, --skip-ssl`: Skip SSL certificate validation
- `-f, --force`: Force rebuild despite validation failures
- `-h, --help`: Show usage information

**Backup Location**: `/tmp/nginx_backup_YYYYMMDD_HHMMSS/`

---

### verify-domains.sh

**Purpose**: Comprehensive domain and SSL verification report

**Features**:
- Tests HTTP to HTTPS redirects
- Validates SSL certificate validity
- Checks response times
- Verifies backend health endpoints
- Tests all configured domains and subdomains
- Reports nginx and container status
- Checks for recent nginx errors

**Usage**:
```bash
./verify-domains.sh
```

**Checks Performed**:
- HTTP redirect status (301/302)
- HTTPS response (200 OK)
- SSL certificate validation
- Response time measurement
- Backend port health checks
- Container count and status
- Nginx error log analysis

---

## Infrastructure Components

### 1. Nginx Web Server

**Configuration Management**:
- Template-based configuration in each app directory
- Dynamic upstream generation based on container scale
- SSL configuration with Let's Encrypt integration
- Default catch-all server for security
- HTTP to HTTPS automatic redirection

**Template Variables**:
- `{{NGINX_UPSTREAM_NAME}}`: Upstream group name
- `{{DOMAIN}}`: Primary domain
- `{{APP_NAME}}`: Application name
- `{{UPSTREAM_SERVERS}}`: Generated server list

**Features**:
- Load balancing across multiple containers
- Health checks with automatic failover
- Security headers (HSTS, XSS, Content-Type, etc.)
- Rate limiting and DDoS protection
- Gzip compression
- Access and error logging

---

### 2. Docker Containerization

**Container Architecture**:
- Multi-stage builds for optimized images
- Non-root user execution
- Health check endpoints
- Volume mounts for logs
- Host or bridge networking based on app type
- Automatic restart policies

**Rails Applications**:
- Web containers (scalable, default 2)
- Worker containers (Sidekiq)
- Scheduler containers (Clockwork)
- Host networking for PostgreSQL access
- Asset precompilation during build

**Next.js Applications**:
- Standalone output mode
- Multi-container load balancing
- Bridge networking
- Static asset optimization
- Environment-based configuration

**Image Management**:
- Timestamped image tags
- Automatic cleanup of old images
- Image backup before deployment
- Rollback capability

---

### 3. SSL Certificate Management

**Fully Automated SSL with Let's Encrypt** (No Manual Commands Required):
- **Automatic during every deployment**: SSL certificates are checked and obtained automatically - no separate commands needed
- Multi-domain support (apex, www, internal domains)
- Certificate validation and expiry checking (30-day warning threshold)
- Auto-renewal with systemd timer (twice daily)
- Nginx reload hook after renewal
- DNS validation before certificate acquisition
- Graceful handling when DNS not ready or certbot account missing
- **Simply run `./deploy.sh deploy` and SSL is handled automatically**

**Automated Certificate Workflow During Deployment**:
Every time you run `./deploy.sh deploy`, the system automatically:
1. Checks if certbot is installed
2. Verifies if certificates exist for the domain
3. Checks certificate expiry (warns if < 30 days remaining)
4. Validates certificate covers all required domains
5. If certificates don't exist:
   - Validates DNS configuration
   - Checks for existing certbot account
   - Automatically obtains certificates (if DNS and account ready)
   - Configures nginx with SSL
   - Sets up HTTP to HTTPS redirect
6. Logs SSL status in deployment log

**SSL Status During Deployment**:
- `success`: Certificates valid and working
- `skipped`: Certificates don't exist but couldn't be obtained automatically (DNS not ready, no certbot account, etc.)
- `failed`: Attempted to obtain certificates but failed

**If Automatic SSL Setup is Skipped**:
If DNS or certbot account wasn't ready during deployment, configure DNS properly and redeploy. SSL will be automatically obtained during the next deployment. Alternatively, use certbot directly:
```bash
sudo certbot --nginx -d domain.com -d www.domain.com
```

**Certificate Auto-Renewal**:
Certbot automatically renews certificates via systemd timer:
- Checks twice daily for certificates expiring within 30 days
- Automatically renews when needed
- Nginx reloads after successful renewal
- No manual intervention required

---

### 4. Database Management (PostgreSQL)

**Setup**:
- Automatic database creation
- User and privilege management
- Password configuration
- Connection testing

**Backup Automation**:
- Daily automated backups (cron)
- Compressed backup files (.sql.gz)
- Retention policy (default 30 days)
- Automatic cleanup of old backups

**Backup Location**:
```
~/apps/{app-name}/backups/
```

**Migration Management**:
- Pre-migration database backup
- Automatic Rails migrations during deployment
- Migration rollback capability

---

### 5. Redis Configuration

**Redis 8 Optimizations**:
- AOF (Append-Only File) persistence
- Memory management (maxmemory policy)
- Redis Streams configuration
- Connection pooling
- Database isolation (per-app DB numbers)

**Configuration Template**: `common/templates/redis.conf`

**Setup Script**: `common/redis-setup.sh`

**Features**:
- Optimized for Streams workloads
- Automatic backup and restore
- Performance monitoring
- Memory eviction policies

---

## Application Management

### Application Types

#### Rails Applications

**Configuration** (`config.sh` variables):
- `APP_TYPE="rails"`
- Database settings (name, user, password)
- Redis settings (DB number, URL)
- Container settings (scale, ports)
- Worker and scheduler settings

**Deployment Features**:
- Database migrations with backup
- Asset precompilation in Docker build
- Sidekiq worker containers
- Clockwork scheduler container
- Rails console access
- Database restore capability

**Container Types**:
1. **Web**: Rails server (Puma) with health check endpoint
2. **Worker**: Sidekiq for background jobs
3. **Scheduler**: Clockwork for scheduled tasks

---

#### Next.js Applications

**Configuration** (`config.sh` variables):
- `APP_TYPE="nextjs"`
- Build-time environment variables
- Container settings (scale, ports)
- Domain configuration

**Deployment Features**:
- Standalone output mode
- Static optimization
- Environment variable injection
- Multi-container load balancing

**Requirements**:
- `output: 'standalone'` in `next.config.js`
- Build-time environment variables in `.env.production`

---

### Deployment Commands

Each application has a `deploy.sh` script with these commands:

```bash
./deploy.sh deploy          # Deploy latest code from repository
./deploy.sh restart         # Restart all containers with current image
./deploy.sh stop            # Stop all containers
./deploy.sh scale <N>       # Scale web containers (1-10)
./deploy.sh status          # Show container status and health
./deploy.sh logs [name]     # View container logs (default: web_1)
./deploy.sh console         # Rails console (Rails apps only)
./deploy.sh help            # Show all available commands
```

---

### Application Setup Process

**Initial Setup**:
```bash
cd DevOps/apps/{app-name}
./setup.sh
```

**Setup Workflow**:
1. Create directory structure
2. Clone application repository
3. Check prerequisites (Node.js, Ruby, PostgreSQL, Redis)
4. Setup database and user
5. Create environment file (.env.production)
6. Install dependencies
7. Generate nginx configuration
8. Setup default catch-all server
9. Configure automated cleanup
10. Setup SSL certificates
11. Create deployment info file

---

### Deployment Workflow

**Standard Deployment**:
```bash
cd DevOps/apps/{app-name}
./deploy.sh deploy
```

**Deployment Steps**:
1. Pull latest code from repository
2. Build Docker image with timestamp tag
3. Run database migrations (Rails only, with backup)
4. Perform rolling restart or fresh deployment
5. Health check each container
6. Update nginx upstream if scaling changed
7. Cleanup old Docker images
8. **Automated SSL certificate check and setup**:
   - Verify existing certificates are valid
   - Check certificate expiry (warn if < 30 days)
   - Automatically obtain certificates if missing (when DNS configured)
   - Skip gracefully if DNS not ready or no certbot account
9. Log deployment with SSL status
10. Display deployment summary with SSL status

**Automated SSL During Deployment**:
SSL certificates are automatically managed during every deployment:
- **If certificates exist**: Validates they're current and not expiring soon
- **If certificates missing**: Attempts to obtain them automatically
- **If DNS not ready**: Skips with informative message, configure DNS and redeploy to automatically obtain certificates
- **Status logged**: Every deployment logs SSL status (success/skipped/failed)

**Rolling Restart**:
- Starts new containers before stopping old ones
- Health checks each new container
- Zero-downtime deployment
- Automatic rollback on failure
- SSL check runs after containers are healthy

---

## Common Utilities

### utils.sh

Core utility functions used across all scripts:

**Logging**:
- `log_info()`: Blue informational messages
- `log_success()`: Green success messages
- `log_warning()`: Yellow warning messages
- `log_error()`: Red error messages

**Database Operations**:
- `check_database_exists()`: Check if database exists
- `check_db_user_exists()`: Check if user exists
- `create_db_user()`: Create PostgreSQL user with password
- `create_database()`: Create PostgreSQL database
- `grant_database_privileges()`: Grant all privileges
- `reset_db_user_password()`: Reset user password
- `test_db_credentials()`: Test database connection
- `backup_database()`: Create compressed backup
- `cleanup_old_backups()`: Remove old backups by retention policy
- `restore_database()`: Restore from backup file

**Docker Operations**:
- `get_running_containers()`: List running containers
- `get_container_count()`: Count containers for an app
- `check_container_health()`: Health check with retries

**Utilities**:
- `command_exists()`: Check if command is available
- `wait_for_service()`: Wait for service to be ready
- `generate_random_string()`: Generate secure random strings
- `get_or_generate_secret()`: Get existing or generate new secrets
- `load_env_file()`: Load environment variables
- `ensure_directory()`: Create directory with permissions

---

### docker-utils.sh

Docker-specific container management:

**Image Building**:
- `build_docker_image()`: Build with temporary .env for build
- Handles multi-stage builds
- Cleans up temporary files

**Container Management**:
- `start_container()`: Start web container with health checks
- `start_worker_container()`: Start background worker
- `start_scheduler_container()`: Start scheduled task container
- `stop_container()`: Graceful shutdown with timeout
- `rolling_restart()`: Zero-downtime restart
- `scale_application()`: Scale to target container count

**Features**:
- Host or bridge networking
- Log volume mounting
- Environment file injection
- Health check configuration
- Automatic restart policies

---

### setup-app.sh

Generic application setup workflow:

**Functions**:
- `setup_application()`: Main setup orchestration
- `setup_directories()`: Create directory structure
- `setup_repository()`: Clone and checkout code
- `setup_nginx()`: Generate and validate nginx config
- `setup_default_server()`: Security catch-all server
- `setup_cleanup()`: Automated cleanup cron job
- `setup_ssl()`: DNS validation and certificate acquisition
- `create_deployment_info()`: Generate deployment documentation

**App-Type Integration**:
Calls app-type-specific functions from `common/app-types/{type}.sh`:
- `{type}_check_prerequisites()`
- `{type}_setup_database()`
- `{type}_create_env_file()`
- `{type}_setup_requirements()`

---

### deploy-app.sh

Generic deployment workflow:

**Functions**:
- `deploy_application()`: Main deployment orchestration
- `restart_application()`: Restart with current image
- `scale_application_web()`: Scale web containers
- `stop_application()`: Stop all containers
- `handle_status()`: Display detailed status
- `check_and_setup_ssl()`: Verify/obtain SSL certificates
- `update_nginx_upstream()`: Update nginx for scaling
- `handle_deploy_command()`: Command-line interface

**App-Type Integration**:
Calls app-type-specific functions:
- `{type}_pull_code()`
- `{type}_build_image()`
- `{type}_deploy_fresh()`
- `{type}_deploy_rolling()`
- `{type}_stop_containers()`
- `{type}_display_deployment_summary()`

---

### redis-setup.sh

Redis configuration management:

**Functions**:
- `redis_check_installed()`: Check Redis installation
- `redis_check_running()`: Check Redis status
- `redis_get_version()`: Get Redis version
- `setup_redis_for_streams()`: Deploy Streams configuration
- `enable_redis_streams_for_app()`: Enable for specific app

**Features**:
- Backup existing configuration
- Deploy optimized template
- Validate configuration
- Restart with new settings
- Verify functionality

---

## Templates

### Application Templates

Located in `templates/` directory:

#### nextjs-app/
- `config.sh`: Next.js configuration template
- `deploy.sh`: Deployment script template
- `setup.sh`: Setup script template
- `nginx.conf.template`: Nginx configuration template

#### rails-app/
- `config.sh`: Rails configuration template
- `deploy.sh`: Deployment script template
- `setup.sh`: Setup script template
- `nginx.conf.template`: Nginx configuration template

**Creating New Application**:
1. Copy appropriate template directory to `apps/{new-app-name}`
2. Edit `config.sh` with app-specific settings
3. Create `nginx.conf.template` based on requirements
4. Run `./setup.sh` to initialize
5. Run `./deploy.sh deploy` to deploy

---

### Docker Templates

#### Next.js Dockerfile Template
Located in: `common/nextjs/Dockerfile.template`

**Features**:
- Multi-stage build (dependencies, builder, runner)
- Node.js official images
- Non-root user execution
- Standalone output mode
- Static file optimization
- Environment variable configuration
- Health check endpoint

#### Rails Dockerfile Template
Located in: `common/rails/Dockerfile.template`

**Features**:
- Multi-stage build (base, build, production)
- Ruby official images
- System dependencies installation
- Asset precompilation
- Non-root user execution
- Bundler configuration
- Rails optimizations
- Health check endpoint

---

## Deployment Workflows

### Fresh Deployment (No Existing Containers)

1. Pull latest code from repository
2. Build new Docker image
3. Run database migrations (Rails only, with backup)
4. Start configured number of web containers
5. Start worker containers (Rails only)
6. Start scheduler container (Rails only, if enabled)
7. Wait for health checks
8. Update nginx configuration
9. Verify SSL certificates
10. Display summary

### Rolling Restart (Existing Containers)

1. Pull latest code from repository
2. Build new Docker image
3. Run database migrations (Rails only, with backup)
4. For each existing web container:
   - Start new container with new image
   - Wait for health check
   - Stop old container
   - Remove old container
5. Restart worker containers (Rails only)
6. Restart scheduler container (Rails only)
7. Verify SSL certificates
8. Display summary

### Scaling Operations

**Scale Up** (increase containers):
1. Determine new container count
2. Start additional containers with new ports
3. Wait for health checks
4. Update nginx upstream configuration
5. Reload nginx
6. Verify all containers healthy

**Scale Down** (decrease containers):
1. Determine containers to remove
2. Stop excess containers gracefully
3. Remove stopped containers
4. Update nginx upstream configuration
5. Reload nginx
6. Verify remaining containers healthy

---

## SSL Certificate Management

### Fully Automated SSL During Every Deployment

SSL certificate management is **completely automated** and runs as part of every deployment. There is no manual `ssl-setup` command - certificates are automatically checked and obtained when you deploy your application. You don't need to remember to check certificates or renew them - the system handles everything automatically.

**What Happens During Each Deployment**:
Every time you run `./deploy.sh deploy`, the deployment automatically:

1. **Checks for certbot installation**
   - If not installed, logs a warning and skips SSL setup

2. **Builds domain list** for the certificate
   - Primary domain (e.g., example.com)
   - www subdomain (e.g., www.example.com) for non-API domains
   - Additional domains (e.g., DOMAIN_INTERNAL if configured)

3. **If certificates already exist**:
   - Validates certificate covers all required domains
   - Checks expiry date (warns if less than 30 days remaining)
   - Certbot auto-renewal will handle renewal when needed
   - Logs "success" status

4. **If certificates don't exist**:
   - Validates DNS configuration (checks A records point to server)
   - Checks for existing certbot account (from previous setup)
   - If DNS is configured AND certbot account exists:
     - Automatically obtains certificates using certbot --nginx
     - Configures nginx with SSL
     - Sets up HTTP to HTTPS redirect
     - Logs "success" status
   - If DNS not configured OR no certbot account:
     - Skips automatic setup (logs "skipped" status)
     - Provides instructions for manual setup

**SSL Status in Deployment Log**:
Each deployment logs the SSL status:
- `ssl=success`: Certificates are valid and working
- `ssl=skipped`: Couldn't obtain certificates automatically (DNS/account not ready)
- `ssl=failed`: Attempted to obtain certificates but failed

**DNS Validation**:
Before obtaining certificates, the system:
- Checks A records for all domains
- Compares to server IP address
- Only proceeds if DNS is correctly configured
- Provides clear feedback if DNS issues found

**Certificate Auto-Renewal** (System-Wide):
- Systemd timer checks twice daily for certificates expiring within 30 days
- Automatically renews certificates when needed
- Post-renewal hook reloads nginx automatically
- No manual intervention required
- View timer status: `systemctl status certbot.timer`

**SSL Management Commands**:
SSL certificates are automatically managed during deployment. For manual operations:

```bash
# Check certificate status
sudo certbot certificates

# Manually obtain/expand certificates (if automatic setup was skipped)
sudo certbot --nginx -d domain.com -d www.domain.com

# Manually renew certificates (usually not needed - auto-renewal handles this)
sudo certbot renew

# Test renewal process (dry-run)
sudo certbot renew --dry-run

# View renewal timer status
systemctl status certbot.timer

# View certbot logs
sudo tail -50 /var/log/letsencrypt/letsencrypt.log
```

**First Deployment Workflow**:
1. Deploy application: `./deploy.sh deploy`
2. System automatically checks SSL:
   - If DNS ready + certbot account exists: **Automatically obtains certificates**
   - If not ready: Skips with informational message
3. If skipped, configure DNS properly and redeploy (SSL will be automatically obtained)
4. Future deployments: SSL automatically validated

**Completely Hands-Off SSL Management**:
- No need to remember certificate expiry dates
- No manual renewal commands to run
- No separate SSL setup commands to remember
- No cron jobs to configure (handled by systemd)
- SSL status included in every deployment summary
- Just deploy your app - SSL is handled automatically

### Certificate Files

**Location**: `/etc/letsencrypt/live/{domain}/`
- `fullchain.pem`: Full certificate chain
- `privkey.pem`: Private key
- `cert.pem`: Certificate only
- `chain.pem`: Chain only

---

## Database and Redis Setup

### PostgreSQL

**Installation** (via ubuntu-init-setup.sh):
- PostgreSQL server and contrib packages
- libpq-dev for development
- User creation for deployment user

**Per-Application Setup**:
- Dedicated database creation
- Dedicated user with password
- Full privileges granted
- Connection validation

**Database Credentials**:
Stored in application `.env.production` file:
```bash
DATABASE_NAME=app_production
DATABASE_USER=app_user
DATABASE_PASSWORD=secure_random_password
DATABASE_HOST=localhost
```

**Backup Strategy**:
- Daily automated backups via cron
- Compressed with gzip
- 30-day retention (configurable)
- Pre-migration backups
- Manual backup/restore capabilities

**Migration Safety**:
- Automatic backup before migrations
- Migration failure rollback
- Container restart after migrations
- Migration log in deployment summary

---

### Redis

**Installation** (via ubuntu-init-setup.sh):
- Redis 8 from official repository
- Systemd service configuration
- Baseline configuration

**Streams Configuration** (via redis-setup.sh):
- AOF persistence enabled
- Memory management configured
- Eviction policy optimization
- Connection pooling

**Per-Application Configuration**:
- Dedicated Redis database number (0-15)
- Isolated namespaces
- Connection URL in environment

**Redis Credentials**:
```bash
REDIS_URL=redis://localhost:6379/0
REDIS_DB_NUMBER=0
```

**Configuration Location**: `/etc/redis/redis.conf`

**Template Location**: `common/templates/redis.conf`

---

## Monitoring and Maintenance

### Status Checking

**Single Application**:
```bash
cd DevOps/apps/{app-name}
./deploy.sh status
```

**All Applications**:
```bash
cd DevOps/apps
./status.sh
```

**Status Information**:
- Container names and status
- Mapped ports
- Start time and uptime
- Resource usage
- Health check status

---

### Log Management

**Container Logs**:
```bash
# Follow logs for specific container
./deploy.sh logs web_1

# View all logs for container
docker logs {app-name}_web_1

# Follow logs with timestamps
docker logs -f --timestamps {app-name}_web_1
```

**Nginx Logs**:
```bash
# Access logs
sudo tail -f /var/log/nginx/access.log

# Error logs
sudo tail -f /var/log/nginx/error.log

# Application-specific logs (if configured)
sudo tail -f /var/log/nginx/{domain}-access.log
sudo tail -f /var/log/nginx/{domain}-error.log
```

**Application Logs** (Rails):
```bash
# Production logs (mounted volume)
tail -f ~/apps/{app-name}/logs/production.log

# Inside container
docker exec {app-name}_web_1 tail -f /app/log/production.log
```

**System Logs**:
```bash
# Nginx service
sudo journalctl -u nginx -f

# Docker service
sudo journalctl -u docker -f

# Redis service
sudo journalctl -u redis-server -f

# PostgreSQL service
sudo journalctl -u postgresql -f
```

---

### Automated Cleanup

**Centralized Cleanup** (scripts/cleanup-all-apps.sh):
- Runs daily at 2 AM via cron
- Cleans up for all applications
- Removes old Docker images
- Removes old image backups
- Removes old database backups (Rails)

**Per-Application Cleanup**:
Each app has automatic cleanup for:
- Docker images (keeps last 20)
- Image backups (keeps last 20)
- Database backups (keeps 30 days for Rails)

**Manual Cleanup**:
```bash
# Cleanup specific app
cd DevOps/apps/{app-name}
./cleanup.sh

# Cleanup all apps
cd DevOps/scripts
./cleanup-all-apps.sh

# Docker system cleanup
docker system prune -a

# Remove dangling images
docker image prune

# Remove unused volumes
docker volume prune
```

**Cron Job Verification**:
```bash
crontab -l
```

---

### Health Monitoring

**Container Health Checks**:
- Automatic health check every 30s
- `/up` endpoint (Rails) or `/` endpoint
- 3 retries before marking unhealthy
- 40s start period grace time
- Automatic restart if unhealthy

**Manual Health Checks**:
```bash
# Check container health
docker inspect {container-name} | grep -A 10 Health

# Test health endpoint directly
curl http://localhost:{port}/up

# Test via nginx
curl https://{domain}/up
```

**Domain Verification**:
```bash
./verify-domains.sh
```

---

## Disaster Recovery

### Complete System Rebuild

**Purpose**: Rebuild entire server from scratch or restore to new server

**Script**: `scripts/disaster-recovery.sh`

**Configuration**: Copy and edit `scripts/disaster-recovery-config.example.sh`

**Configuration Variables**:
```bash
RECOVERY_USER="andrzej"
RECOVERY_HOME="/home/andrzej"
DEVOPS_REPO_URL="git@github.com:username/DevOps.git"
DEVOPS_REPO_BRANCH="master"
INSTALL_DEPENDENCIES=true
SETUP_SSL=true
APPS_TO_DEPLOY=(
    "cheaperfordrug-api"
    "cheaperfordrug-landing"
    "cheaperfordrug-web"
)
```

**Recovery Steps**:
1. Install basic dependencies (git, curl, wget)
2. Clone DevOps repository
3. Run ubuntu-init-setup.sh for system dependencies
4. Setup each configured application
5. Deploy each application
6. Setup SSL certificates
7. Configure centralized cleanup
8. Verify deployment

**Usage**:
```bash
cd DevOps/scripts
./disaster-recovery.sh disaster-recovery-config.sh
```

**Recovery Time**: 30-60 minutes (depending on server speed and number of apps)

---

### Backup Strategy

**What to Backup**:
1. **Environment Files**: All `.env.production` files
2. **PostgreSQL Databases**: Regular automated backups
3. **SSL Certificates**: Managed by certbot (auto-restored)
4. **DevOps Repository**: Git repository (GitHub backup)
5. **Application Repositories**: Git repositories (GitHub backup)
6. **Configuration Files**: nginx configs (regenerated from templates)

**Database Backups**:
- Location: `~/apps/{app-name}/backups/`
- Frequency: Daily (cron)
- Retention: 30 days
- Format: `.sql.gz` (compressed)

**Manual Backup**:
```bash
# Backup database
sudo -u postgres pg_dump {database_name} | gzip > backup.sql.gz

# Backup all environment files
tar -czf env-backup.tar.gz ~/apps/*/.env.production

# Backup nginx configs
sudo tar -czf nginx-backup.tar.gz /etc/nginx/sites-available /etc/nginx/sites-enabled
```

---

### Rollback Procedures

**Rollback to Previous Image**:
```bash
# List available images
docker images {app-name}

# Stop current containers
./deploy.sh stop

# Start with previous image
docker run -d --name {app-name}_web_1 ... {app-name}:{previous-tag}

# Update nginx if needed
./rebuild-nginx-configs.sh
```

**Rollback Database Migrations** (Rails):
```bash
# Access Rails console
./deploy.sh console

# Run migration rollback
rake db:rollback STEP=1
```

**Restore Database from Backup**:
```bash
cd ~/apps/{app-name}
./restore.sh backups/{database_name}_YYYYMMDD_HHMMSS.sql.gz
```

**Restore Nginx Configuration**:
```bash
# Restore from rebuild-nginx backup
sudo cp -r /tmp/nginx_backup_YYYYMMDD_HHMMSS/sites-available/* /etc/nginx/sites-available/
sudo nginx -t && sudo systemctl reload nginx
```

---

## Prerequisites

### Server Requirements

**Operating System**:
- Ubuntu Server 18.04, 20.04, 22.04, or 24.04 LTS
- 64-bit architecture
- Minimal or Standard installation

**Hardware**:
- CPU: 2+ cores recommended
- RAM: 4GB minimum, 8GB+ recommended
- Storage: 20GB minimum, 50GB+ recommended
- Network: Public IP address

**Network Requirements**:
- Open ports: 80 (HTTP), 443 (HTTPS), 2222 (SSH custom port)
- Registered domain names with DNS access
- A records pointing to server IP address

**Access Requirements**:
- Root or sudo access
- SSH key-based authentication (recommended)
- GitHub account with repository access

---

### Local Development Requirements

**Workstation Tools**:
- Git client
- SSH client (OpenSSH or PuTTY)
- Text editor (VS Code, Sublime, vim)
- Terminal emulator

**GitHub Access**:
- SSH key added to GitHub account
- Access to DevOps and application repositories

---

## Getting Started

### 1. Initial Server Setup

**Prepare Server**:
```bash
# Connect to new server as root
ssh root@your-server-ip

# Clone DevOps repository
git clone git@github.com:username/DevOps.git
cd DevOps

# Make scripts executable
chmod +x *.sh
chmod +x scripts/*.sh
chmod +x common/*.sh
```

**Run System Initialization**:
```bash
# Run complete Ubuntu server setup
sudo ./ubuntu-init-setup.sh
```

**Interactive Setup**:
- Confirm system updates
- User creation and SSH key setup
- Hostname configuration
- Firewall setup with custom SSH port
- Fail2ban installation
- Essential tools installation
- fzf installation with CTRL+P mapping
- Node.js installation
- Ruby/Rails installation (10-15 minutes)
- PostgreSQL and Redis installation
- Docker installation
- Nginx installation
- SSL certificate setup (if DNS ready)
- Rails development libraries
- GitHub SSH key generation
- System optimization (swap, limits, updates)
- SSH security hardening (final step)

**Important**: Test SSH access on new port (2222) before closing session!

---

### 2. Setup First Application

**Choose Application Type**:
- Rails API: Copy from `templates/rails-app/`
- Next.js: Copy from `templates/nextjs-app/`

**Create Application Directory**:
```bash
# Create new app from template
cp -r templates/nextjs-app apps/my-new-app
cd apps/my-new-app
```

**Configure Application** (`config.sh`):
```bash
# Edit configuration
nano config.sh

# Required settings:
# - APP_NAME: Unique name
# - APP_TYPE: rails or nextjs
# - DOMAIN: Primary domain
# - REPO_URL: Git repository URL
# - BASE_PORT: Starting port number
# - DEFAULT_SCALE: Container count
```

**Create Nginx Template** (`nginx.conf.template`):
```nginx
# Copy and modify from similar application
# Ensure placeholders: {{NGINX_UPSTREAM_NAME}}, {{DOMAIN}}, {{UPSTREAM_SERVERS}}
```

**Run Application Setup**:
```bash
# Initial setup (one-time)
./setup.sh
```

**Setup Process**:
- Creates directories
- Clones repository
- Checks prerequisites
- Sets up database (Rails)
- Creates environment file
- Generates nginx config
- Attempts SSL setup (if DNS ready)
- Creates deployment info

**Review Deployment Info**:
```bash
cat ~/apps/my-new-app/deployment-info.txt
```

---

### 3. Configure Environment Variables

**Edit Environment File**:
```bash
nano ~/apps/my-new-app/.env.production
```

**Rails Required Variables**:
```bash
DATABASE_NAME=app_production
DATABASE_USER=app_user
DATABASE_PASSWORD=auto_generated
DATABASE_HOST=localhost
REDIS_URL=redis://localhost:6379/0
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true
SECRET_KEY_BASE=auto_generated
```

**Next.js Required Variables**:
```bash
NODE_ENV=production
NEXT_PUBLIC_API_URL=https://api.yourdomain.com
# Add other build-time variables
```

---

### 4. Deploy Application

**First Deployment**:
```bash
cd DevOps/apps/my-new-app
./deploy.sh deploy
```

**Deployment Process**:
- Pulls latest code
- Builds Docker image
- Runs migrations (Rails)
- Starts containers
- Performs health checks
- Checks SSL certificates
- Displays summary

**Verify Deployment**:
```bash
# Check container status
./deploy.sh status

# View logs
./deploy.sh logs

# Test endpoint
curl https://your-domain.com
```

---

### 5. Setup DNS and SSL

**Configure DNS**:
```
your-domain.com        A    your-server-ip
www.your-domain.com    A    your-server-ip
```

**SSL Certificates**:
SSL certificates are automatically checked and obtained during the first deployment. If DNS wasn't ready during setup, simply ensure DNS is configured and redeploy:
```bash
./deploy.sh deploy  # SSL will be automatically obtained
```

**Verify SSL**:
```bash
# Check certificate
sudo certbot certificates

# Test in browser
https://your-domain.com
```

---

## Best Practices

### Security

1. **SSH Hardening**:
   - Use custom SSH port (not 22)
   - Disable password authentication
   - Disable root login
   - Use SSH keys only
   - Configure fail2ban

2. **Firewall**:
   - Enable UFW firewall
   - Only open necessary ports (custom SSH, 80, 443)
   - Configure fail2ban for SSH protection

3. **SSL/TLS**:
   - Always use HTTPS in production
   - Enable HSTS headers
   - Use strong cipher suites
   - Monitor certificate expiry

4. **Database**:
   - Use strong passwords
   - Restrict database access to localhost
   - Regular automated backups
   - Test restore procedures

5. **Environment Variables**:
   - Never commit `.env` files to git
   - Use strong, random secrets
   - Rotate secrets periodically
   - Restrict file permissions (600)

6. **Container Security**:
   - Run as non-root user
   - Keep base images updated
   - Scan for vulnerabilities
   - Limit resource usage

---

### Performance

1. **Container Scaling**:
   - Scale based on traffic patterns
   - Monitor CPU and memory usage
   - Use load testing to determine optimal scale
   - Consider auto-scaling solutions

2. **Database Optimization**:
   - Regular VACUUM and ANALYZE
   - Proper indexing
   - Connection pooling
   - Query optimization

3. **Redis Tuning**:
   - Appropriate maxmemory setting
   - Correct eviction policy
   - Persistence strategy (AOF vs RDB)
   - Connection pooling

4. **Nginx Optimization**:
   - Enable gzip compression
   - Set appropriate timeouts
   - Configure connection limits
   - Use caching headers

5. **Asset Optimization**:
   - Precompile assets (Rails)
   - Optimize images
   - Minimize CSS/JS
   - Use CDN for static assets

---

### Operational

1. **Monitoring**:
   - Regular status checks
   - Log monitoring (errors, performance)
   - Resource usage tracking
   - SSL certificate expiry monitoring
   - Container health checks

2. **Backup Strategy**:
   - Automated daily database backups
   - Retain backups for 30+ days
   - Test restore procedures regularly
   - Backup environment files off-server
   - Document backup locations

3. **Deployment**:
   - Test in staging environment first
   - Deploy during low-traffic periods
   - Monitor logs during deployment
   - Have rollback plan ready
   - Document deployment procedures

4. **Maintenance**:
   - Regular system updates
   - Docker image updates
   - Dependency updates
   - Log rotation
   - Cleanup old images and backups

5. **Documentation**:
   - Keep deployment info current
   - Document configuration changes
   - Maintain runbooks for common issues
   - Update environment variable documentation
   - Record SSL renewal procedures

---

### Development Workflow

1. **Version Control**:
   - Use feature branches
   - Pull request reviews
   - Tag releases
   - Keep DevOps repo in sync

2. **Testing**:
   - Run tests before deployment
   - Test in staging environment
   - Verify health checks work
   - Test rollback procedures

3. **Configuration Management**:
   - Use templates for consistency
   - Version control nginx configs
   - Document environment variables
   - Keep secrets out of git

4. **Scaling**:
   - Start with default scale
   - Monitor and adjust based on usage
   - Plan for peak traffic
   - Test scaling procedures

5. **Cleanup**:
   - Regular automated cleanup
   - Monitor disk space
   - Remove unused containers
   - Clean up old images

---

## Troubleshooting

### Common Issues

**SSH Connection Issues After Hardening**:
```bash
# Verify SSH service is running
sudo systemctl status ssh

# Check SSH port
sudo ss -tlnp | grep sshd

# Check firewall
sudo ufw status

# Restore from backup if needed
sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
sudo systemctl restart ssh
```

**Container Won't Start**:
```bash
# Check container logs
docker logs {container-name}

# Verify environment file
cat ~/apps/{app-name}/.env.production

# Check port conflicts
sudo netstat -tlnp | grep {port}

# Check Docker status
sudo systemctl status docker
```

**Database Connection Issues**:
```bash
# Test database credentials
PGPASSWORD={password} psql -h localhost -U {user} -d {database} -c "SELECT 1;"

# Check PostgreSQL status
sudo systemctl status postgresql

# Check PostgreSQL logs
sudo journalctl -u postgresql -n 50
```

**Nginx Configuration Errors**:
```bash
# Test nginx configuration
sudo nginx -t

# Check nginx logs
sudo tail -50 /var/log/nginx/error.log

# Restore from backup
sudo cp /tmp/nginx_backup_*/sites-available/* /etc/nginx/sites-available/
sudo systemctl reload nginx
```

**SSL Certificate Issues**:
```bash
# Check certificate status
sudo certbot certificates

# Check DNS configuration
dig {domain} +short

# Check certbot logs
sudo tail -50 /var/log/letsencrypt/letsencrypt.log

# Renew manually
sudo certbot renew --dry-run
sudo certbot renew --force-renewal
```

**Out of Disk Space**:
```bash
# Check disk usage
df -h

# Find large files
du -sh /* | sort -h

# Clean up Docker
docker system prune -a

# Clean up old backups
find ~/apps/*/backups -name "*.sql.gz" -mtime +30 -delete

# Clean up old images
docker images | grep {app-name} | tail -n +21 | awk '{print $3}' | xargs docker rmi
```

---

## Support and Contribution

### Getting Help

**Log Files**:
- Server init: `/var/log/server-init-setup.log`
- Nginx errors: `/var/log/nginx/error.log`
- Container logs: `docker logs {container-name}`
- Deployment logs: `~/apps/{app-name}/logs/deployments.log`

**Useful Commands**:
```bash
# System status
sudo systemctl status

# Container status
docker ps -a

# Disk space
df -h

# Memory usage
free -h

# Network connections
sudo netstat -tlnp

# Recent system logs
sudo journalctl -n 100
```

---

## Summary

This DevOps repository provides a comprehensive, production-ready infrastructure for deploying and managing multiple applications on Ubuntu servers. Key capabilities:

- **Automated Setup**: Complete server initialization from scratch
- **Multi-App Support**: Rails APIs and Next.js frontends
- **Zero-Downtime Deployments**: Rolling restarts with health checks
- **SSL Automation**: Let's Encrypt with auto-renewal
- **Scalability**: Dynamic container scaling with load balancing
- **Monitoring**: Health checks, logs, and status reporting
- **Backup & Recovery**: Automated backups and disaster recovery
- **Security**: Firewall, SSH hardening, fail2ban, SSL/TLS
- **Maintenance**: Automated cleanup and system optimization

The modular design allows easy addition of new applications and supports both fresh deployments and updates to existing infrastructure. All scripts follow bash best practices with proper error handling, logging, and documentation.

For production use, follow the best practices outlined in this README, maintain regular backups, and monitor your applications continuously.

---

**Version**: 2.0.0
**Last Updated**: 2025-10-30
**Maintained By**: DevOps Team

---

## Container Networking on Linux (Critical for Rails APIs)

### Host Networking Requirement

**IMPORTANT**: On native Linux (Ubuntu/Hetzner), Rails API applications **must use `--network host`** mode to access PostgreSQL, Redis, and Elasticsearch running on the host machine.

**Why**: Unlike Docker Desktop (macOS/Windows), native Linux does NOT support `host.docker.internal` hostname for accessing host services from containers.

### Required Pattern

```bash
# ✅ CORRECT Configuration for Linux
DATABASE_URL=postgresql://user:password@localhost/database_name
REDIS_URL=redis://localhost:6379/0
ELASTICSEARCH_URL=http://localhost:9200

# Container creation
docker run -d \
  --name app_web_1 \
  --network host \
  --env-file .env.production \
  -e PORT=3000 \
  app:latest

# ❌ WRONG - Does NOT work on native Linux
DATABASE_URL=postgresql://user:password@host.docker.internal/database_name
docker run -d --network bridge -p 3000:3000 ...
```

### Port Management with Host Networking

**Trade-off**: With `--network host`, multiple containers cannot bind to the same port. Each web container needs a unique `PORT` environment variable.

**Solution**: Use sequential ports starting from a base port:

```bash
# config.sh
export BASE_PORT=3020
export DEFAULT_SCALE=3

# Results in:
app_web_1 on PORT=3020
app_web_2 on PORT=3021
app_web_3 on PORT=3022
```

**Nginx Load Balancing**:
```nginx
upstream app_backend {
    server localhost:3020;
    server localhost:3021;
    server localhost:3022;
}
```

### Comprehensive Documentation

For complete details on container networking patterns, port allocation strategy, scaling patterns, and troubleshooting, see:

**[Global Container Patterns Documentation](/home/andrzej/DevOps/CONTAINER-PATTERNS.md)**

This document provides:
- Detailed networking requirements for Linux
- Port allocation strategy and current allocations
- Container naming conventions
- Scaling patterns for web and worker containers
- Database connectivity patterns
- Configuration templates
- Troubleshooting guides
- Best practices

**Application-Specific Documentation**:
- **CheaperForDrug API**: `/home/andrzej/DevOps/apps/cheaperfordrug-api/CONTAINER-MANAGEMENT.md`

### Quick Reference

```bash
# Add new web container (host networking)
docker run -d \
  --name ${APP_NAME}_web_${N} \
  --network host \
  --env-file /home/andrzej/DevOps/apps/${APP_NAME}/.env.production \
  -e PORT=$((BASE_PORT + N - 1)) \
  --restart unless-stopped \
  ${APP_NAME}:latest

# Add worker container (no port needed)
docker run -d \
  --name ${APP_NAME}_worker_${N} \
  --network host \
  --env-file /home/andrzej/DevOps/apps/${APP_NAME}/.env.production \
  --restart unless-stopped \
  ${APP_NAME}:latest \
  bundle exec sidekiq

# Update nginx after scaling
cd /home/andrzej/DevOps
./rebuild-nginx-configs.sh
```

**See CONTAINER-PATTERNS.md for full details on adding new applications and scaling strategies.**

