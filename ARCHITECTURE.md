# DevOps Deployment System - New Architecture

A modular, framework-specific deployment system for managing multiple applications with Docker, zero-downtime deployments, and automated monitoring.

## Architecture Overview

```
DevOps/
├── common/                      # Shared utilities
│   ├── utils.sh                # Common utility functions
│   ├── docker-utils.sh         # Docker-specific utilities
│   ├── rails/                  # Rails framework modules
│   │   ├── setup.sh           # Rails setup functions
│   │   └── deploy.sh          # Rails deployment functions
│   └── nodejs/                 # Node.js framework modules
│       ├── setup.sh           # Node.js setup functions
│       └── deploy.sh          # Node.js deployment functions
├── apps/                       # Application-specific configs
│   └── <app-name>/
│       ├── config.sh          # App configuration
│       ├── setup.sh           # App setup script (executable)
│       ├── deploy.sh          # App deploy script (executable)
│       └── nginx.conf.template # Nginx configuration template
└── scripts/                    # Global helper scripts
    ├── console.sh             # Rails console access
    └── rails-task.sh          # Rails task runner
```

## Key Design Principles

1. **DRY (Don't Repeat Yourself)**: Common functionality lives in framework modules
2. **Flexible**: Easy to customize per app with override capabilities
3. **Clear**: Each app has visible `setup.sh` and `deploy.sh` scripts
4. **Maintainable**: Common changes propagate to all apps automatically
5. **Type-Safe**: Rails apps use Rails modules, Node apps use Node modules

## Quick Start

### For Rails Applications

```bash
cd ~/DevOps

# 1. Create app directory structure
mkdir -p apps/my-rails-app

# 2. Copy configuration template
cp apps/cheaperfordrug-landing/config.sh apps/my-rails-app/config.sh
# Edit configuration (see Configuration Guide below)

# 3. Copy app-specific setup script
cp apps/cheaperfordrug-landing/setup.sh apps/my-rails-app/setup.sh
chmod +x apps/my-rails-app/setup.sh
# Customize if needed

# 4. Copy app-specific deploy script
cp apps/cheaperfordrug-landing/deploy.sh apps/my-rails-app/deploy.sh
chmod +x apps/my-rails-app/deploy.sh
# Customize if needed

# 5. Copy Nginx template
cp apps/cheaperfordrug-landing/nginx.conf.template apps/my-rails-app/

# 6. Run setup
./apps/my-rails-app/setup.sh

# 7. Deploy
./apps/my-rails-app/deploy.sh deploy
```

### For Node.js Applications

Similar structure, but:
1. Set Node.js-specific flags in `config.sh`
2. App scripts source nodejs modules instead of rails modules

```bash
# In apps/my-nodejs-app/setup.sh
source "${DEVOPS_DIR}/common/nodejs/setup.sh"

# In apps/my-nodejs-app/deploy.sh
source "${DEVOPS_DIR}/common/nodejs/deploy.sh"
```

## Usage

### Setup (First Time Only)

```bash
cd ~/DevOps
./apps/<app-name>/setup.sh
```

### Deployment Commands

```bash
# Deploy with default scale
./apps/<app-name>/deploy.sh deploy

# Deploy with specific scale
./apps/<app-name>/deploy.sh deploy 4

# Restart containers
./apps/<app-name>/deploy.sh restart

# Scale to N instances
./apps/<app-name>/deploy.sh scale 4

# Stop all containers
./apps/<app-name>/deploy.sh stop

# Show help
./apps/<app-name>/deploy.sh help
```

### Rails Console & Tasks

```bash
# Access Rails console
./scripts/console.sh <app-name>

# Run Rails tasks
./scripts/rails-task.sh <app-name> db:migrate
./scripts/rails-task.sh <app-name> routes
```

## Configuration Guide

### App Configuration (`apps/<app-name>/config.sh`)

**Required Variables:**

```bash
# Application identification
export APP_NAME="my-app"
export APP_DISPLAY_NAME="My Application"

# Repository configuration
export REPO_URL="https://github.com/user/repo.git"
export REPO_BRANCH="master"

# Server paths
export DEPLOY_USER="andrzej"
export DEPLOY_HOME="/home/${DEPLOY_USER}"
export APP_BASE_DIR="${DEPLOY_HOME}/apps"
export APP_DIR="${APP_BASE_DIR}/${APP_NAME}"
export REPO_DIR="${APP_DIR}/repo"
export ENV_FILE="${APP_DIR}/.env.production"
export BACKUP_DIR="${APP_DIR}/backups"
export LOG_DIR="${APP_DIR}/logs"

# Network configuration
export DOMAIN="myapp.example.com"
export BASE_PORT=3020      # Must be unique per app!
export PORT_RANGE_END=3029
export DEFAULT_SCALE=2

# Docker configuration
export DOCKER_IMAGE_NAME="${APP_NAME}"
export DOCKER_NETWORK="bridge"

# Health check configuration
export HEALTH_CHECK_PATH="/up"
export HEALTH_CHECK_TIMEOUT=60
export HEALTH_CHECK_INTERVAL=2

# Deployment configuration
export MIGRATION_BACKUP_ENABLED=true
export ZERO_DOWNTIME_ENABLED=true
export AUTO_CLEANUP_ENABLED=true
export BACKUP_RETENTION_DAYS=30
export MAX_IMAGE_VERSIONS=3
```

**Rails-Specific Variables:**

```bash
# Database configuration
export DB_NAME="${APP_NAME//-/_}_production"
export DB_USER="postgres"
export DB_PASSWORD=""  # Leave empty for peer auth

# Redis configuration
export REDIS_DB_NUMBER=1  # Unique per app!
export REDIS_URL="redis://localhost:6379/${REDIS_DB_NUMBER}"

# Mailgun configuration
export MAILGUN_API_KEY="your-api-key"
export MAILGUN_DOMAIN="mg.example.com"
export MAILGUN_FROM_EMAIL="noreply@mg.example.com"
export NOTIFICATION_EMAIL="admin@example.com"

# Nginx configuration
export NGINX_CONF="/etc/nginx/sites-available/${APP_NAME}"
export NGINX_ENABLED="/etc/nginx/sites-enabled/${APP_NAME}"
export NGINX_UPSTREAM_NAME="${APP_NAME//-/_}_backend"

# Application-specific environment variables
export APP_ENV_VARS=(
    "STRIPE_PUBLISHABLE_KEY=pk_live_xxx"
    "STRIPE_SECRET_KEY=sk_live_xxx"
    "GOOGLE_ANALYTICS_ID=G-XXXXXXXXXX"
)
```

**Node.js-Specific Variables:**

```bash
# Feature flags
export NEEDS_POSTGRES=true      # Does app need PostgreSQL?
export NEEDS_REDIS=true          # Does app need Redis?
export NEEDS_MAILGUN=true        # Does app need Mailgun?
export NEEDS_MIGRATIONS=true     # Does app have migrations?

# If NEEDS_POSTGRES=true, include database config
export DB_NAME="${APP_NAME//-/_}_production"
export DB_USER="postgres"
export DB_PASSWORD=""

# If NEEDS_REDIS=true, include Redis config
export REDIS_DB_NUMBER=2
export REDIS_URL="redis://localhost:6379/${REDIS_DB_NUMBER}"

# Application-specific environment variables
export APP_ENV_VARS=(
    "API_KEY=your_api_key"
    "CUSTOM_CONFIG=value"
)
```

## Customizing App Behavior

### Overriding Framework Functions

In your app-specific `setup.sh` or `deploy.sh`, override any function:

```bash
# In apps/my-app/setup.sh

# Load common modules first
source "${DEVOPS_DIR}/common/rails/setup.sh"

# Override specific function
rails_precompile_assets() {
    log_info "Custom asset precompilation with Node.js..."
    cd "$REPO_DIR"

    # Install Node.js dependencies
    npm ci

    # Custom precompilation with both Rails and Node
    RAILS_ENV=production NODE_ENV=production bundle exec rails assets:precompile

    return 0
}

# Rest of your setup script...
```

### Adding Pre/Post Hooks

```bash
# In apps/my-app/deploy.sh

# Pre-deployment hook
pre_deploy_hook() {
    log_info "Running custom pre-deployment checks..."

    # Check if external API is available
    if ! curl -sf https://api.example.com/health > /dev/null; then
        log_error "External API is down, aborting deployment"
        return 1
    fi

    # Warm up cache
    docker exec "${APP_NAME}_web_1" /bin/bash -c "bundle exec rails cache:warm"

    return 0
}

# Post-deployment hook
post_deploy_hook() {
    log_info "Running post-deployment tasks..."

    # Ping monitoring service
    curl -sf "https://monitoring.example.com/ping?app=${APP_NAME}"

    # Clear CDN cache
    curl -X POST "https://cdn.example.com/purge" \
        -H "Authorization: Bearer ${CDN_TOKEN}"

    return 0
}

# Use in handle_deploy function
handle_deploy() {
    # ... existing code ...

    pre_deploy_hook || exit 1

    if rails_deploy_application "$scale"; then
        post_deploy_hook
        send_deploy_success_notification "$scale" "$image_tag"
        exit 0
    else
        send_deploy_failure_notification "Deployment workflow failed"
        exit 1
    fi
}
```

### Custom Notification Functions

```bash
# In apps/my-app/deploy.sh

# Custom Slack notification
send_slack_notification() {
    local message="$1"
    local webhook_url="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

    curl -X POST "$webhook_url" \
        -H 'Content-Type: application/json' \
        -d "{\"text\": \"${message}\"}"
}

# Override email notification to also send to Slack
send_deploy_success_notification() {
    local scale="$1"
    local image_tag="$2"

    # Send email (original)
    send_mailgun_notification \
        "${APP_DISPLAY_NAME} - Deployment Successful" \
        "..." \
        "$MAILGUN_API_KEY" \
        "$MAILGUN_DOMAIN" \
        "$NOTIFICATION_EMAIL"

    # Also send to Slack (custom)
    send_slack_notification "✅ ${APP_DISPLAY_NAME} deployed successfully! (${scale} instances)"
}
```

## Framework Modules Reference

### Rails Module Functions

#### Setup Functions (`common/rails/setup.sh`)

- **`rails_check_prerequisites()`** - Verify Ruby, PostgreSQL, Redis installed
- **`rails_setup_database()`** - Create PostgreSQL database
- **`rails_create_env_file()`** - Generate .env.production file
- **`rails_setup_native_environment()`** - Install gems with bundler
- **`rails_precompile_assets()`** - Precompile Rails assets
- **`rails_run_migrations()`** - Execute database migrations
- **`rails_setup_workflow()`** - Complete setup workflow (calls all above)

#### Deploy Functions (`common/rails/deploy.sh`)

- **`rails_pull_code()`** - Pull latest code from git repository
- **`rails_build_image(TAG)`** - Build Docker image with specific tag
- **`rails_check_pending_migrations(CONTAINER)`** - Check for pending migrations
- **`rails_run_migrations_with_backup(CONTAINER)`** - Run migrations with DB backup
- **`rails_deploy_fresh(SCALE, TAG)`** - Fresh deployment (no running containers)
- **`rails_deploy_rolling(SCALE, TAG)`** - Zero-downtime rolling restart
- **`rails_deploy_application(SCALE)`** - Main deployment workflow
- **`rails_restart_application(SCALE)`** - Restart with current image
- **`rails_scale_application(SCALE)`** - Scale to N instances
- **`rails_stop_application()`** - Stop all containers
- **`rails_run_console()`** - Start Rails console in container
- **`rails_run_task(TASK)`** - Run Rails task in container

### Node.js Module Functions

#### Setup Functions (`common/nodejs/setup.sh`)

- **`nodejs_check_prerequisites()`** - Verify Node.js, npm, optional services
- **`nodejs_setup_database()`** - Setup PostgreSQL if NEEDS_POSTGRES=true
- **`nodejs_create_env_file()`** - Generate .env.production file
- **`nodejs_setup_native_environment()`** - Install npm dependencies
- **`nodejs_build_application()`** - Run build script if package.json has "build"
- **`nodejs_run_migrations()`** - Run migrations if package.json has "migrate"
- **`nodejs_setup_workflow()`** - Complete setup workflow

#### Deploy Functions (`common/nodejs/deploy.sh`)

- **`nodejs_pull_code()`** - Pull latest code from git
- **`nodejs_build_image(TAG)`** - Build Docker image
- **`nodejs_check_pending_migrations(CONTAINER)`** - Check for pending migrations
- **`nodejs_run_migrations_with_backup(CONTAINER)`** - Run migrations with backup
- **`nodejs_deploy_fresh(SCALE, TAG)`** - Fresh deployment
- **`nodejs_deploy_rolling(SCALE, TAG)`** - Zero-downtime rolling restart
- **`nodejs_deploy_application(SCALE)`** - Main deployment workflow
- **`nodejs_restart_application(SCALE)`** - Restart containers
- **`nodejs_scale_application(SCALE)`** - Scale containers
- **`nodejs_stop_application()`** - Stop all containers
- **`nodejs_run_shell()`** - Access container shell
- **`nodejs_run_script(SCRIPT)`** - Run npm script in container

## Example: Rails App with Custom Asset Pipeline

```bash
# apps/my-app/setup.sh

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${DEVOPS_DIR}/common/utils.sh"
source "${DEVOPS_DIR}/common/docker-utils.sh"
source "${DEVOPS_DIR}/common/rails/setup.sh"

# Override asset precompilation to use webpack
rails_precompile_assets() {
    log_info "Precompiling assets with Webpack..."
    cd "$REPO_DIR"

    # Install Node.js dependencies
    npm ci

    # Run Webpack build
    NODE_ENV=production npm run build

    # Then run Rails asset precompilation
    RAILS_ENV=production bundle exec rails assets:precompile

    if [ $? -eq 0 ]; then
        log_success "Assets precompiled successfully"
        return 0
    else
        log_error "Asset precompilation failed"
        return 1
    fi
}

# Custom post-setup tasks
post_setup_hook() {
    log_info "Setting up cron jobs..."

    # Add cron job for scheduled tasks
    (crontab -l 2>/dev/null; echo "0 2 * * * cd $REPO_DIR && RAILS_ENV=production bundle exec rails cleanup:old_records") | crontab -

    log_success "Cron jobs configured"
    return 0
}

main() {
    log_info "Starting setup for ${APP_DISPLAY_NAME}"

    # ... standard checks ...

    rails_setup_workflow || exit 1
    post_setup_hook || exit 1

    log_success "Setup completed!"
}

main "$@"
```

## Example: Node.js App with TypeScript

```bash
# apps/my-nodejs-app/config.sh

export APP_NAME="my-nodejs-app"
export APP_DISPLAY_NAME="My Node.js Application"
export REPO_URL="https://github.com/user/my-nodejs-app.git"
export REPO_BRANCH="main"

# Node.js feature flags
export NEEDS_POSTGRES=true
export NEEDS_REDIS=true
export NEEDS_MAILGUN=false
export NEEDS_MIGRATIONS=true

# ... rest of config ...
```

```bash
# apps/my-nodejs-app/setup.sh

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${DEVOPS_DIR}/common/utils.sh"
source "${DEVOPS_DIR}/common/docker-utils.sh"
source "${DEVOPS_DIR}/common/nodejs/setup.sh"

# Override build to handle TypeScript
nodejs_build_application() {
    log_info "Building TypeScript application..."
    cd "$REPO_DIR"

    # Install all dependencies (including dev for TypeScript compilation)
    npm ci

    # Run TypeScript build
    npm run build

    if [ $? -eq 0 ]; then
        log_success "TypeScript build completed successfully"
        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

main() {
    log_info "Starting setup for ${APP_DISPLAY_NAME}"

    # Standard setup workflow
    nodejs_setup_workflow || exit 1

    log_success "Setup completed!"
}

main "$@"
```

## Port Allocation Strategy

Each app needs a unique port range. Recommended allocation:

```
App 1:  BASE_PORT=3010  Range: 3010-3019  Redis DB: 1
App 2:  BASE_PORT=3020  Range: 3020-3029  Redis DB: 2
App 3:  BASE_PORT=3030  Range: 3030-3039  Redis DB: 3
App 4:  BASE_PORT=3040  Range: 3040-3049  Redis DB: 4
...
```

## Zero-Downtime Deployment Process

1. **Pull latest code** from repository
2. **Build new Docker image** with timestamp tag
3. **Check for migrations** using test container
4. **Backup database** if migrations detected
5. **Run migrations** in test container
6. **Start new containers** with new image (one at a time)
7. **Health check** each new container (60s timeout)
8. **Stop old containers** only after new ones are healthy
9. **Rename containers** to standard names
10. **Clean up** old images (keep last 3 versions)

## Troubleshooting

### Deployment Fails

```bash
# Check deployment logs
tail -f ~/apps/<app-name>/logs/deployments.log

# Check container logs
docker logs <app-name>_web_1 --tail 100

# Check running containers
docker ps | grep <app-name>

# Inspect container
docker inspect <app-name>_web_1
```

### Migration Fails

```bash
# List backups
ls -lh ~/apps/<app-name>/backups/

# Restore from backup
cd ~/apps/<app-name>/backups
gunzip <backup-file>.sql.gz
sudo -u postgres psql <db-name> < <backup-file>.sql
```

### Health Check Fails

```bash
# Test health endpoint
curl -v http://localhost:3010/up

# Check container health
docker exec <app-name>_web_1 curl http://localhost:80/up

# Check logs
docker logs <app-name>_web_1

# Check environment
docker exec <app-name>_web_1 env | grep -E '(DATABASE|REDIS|SECRET)'
```

### Override Not Working

Make sure you:
1. Source the common module BEFORE defining your override
2. Use the exact same function name
3. Return proper exit codes (0 for success, 1 for failure)

## Best Practices

1. **Test Locally First** - Build and test Docker image before deploying
2. **Use Staging Environment** - Create separate staging app configs
3. **Monitor Notifications** - Check email after each deployment
4. **Keep Backups** - Backups are automatic, but verify they exist
5. **Review Logs** - Check deployment logs regularly
6. **Scale Gradually** - Don't jump from 2 to 20 instances immediately
7. **Update Common Modules Carefully** - Changes affect all apps
8. **Document Custom Functions** - Add comments explaining overrides
9. **Version Control Everything** - Keep DevOps configs in git
10. **Test Rollback Procedures** - Know how to restore from backup

## File Locations

### Development Machine
```
/Users/andrzej/Development/DevOps/
├── common/
├── apps/
├── scripts/
└── ARCHITECTURE.md (this file)
```

### Production Server
```
/home/andrzej/
├── DevOps/              # Git clone
│   ├── common/
│   ├── apps/
│   └── scripts/
└── apps/                # Deployed applications
    └── <app-name>/
        ├── repo/
        ├── .env.production
        ├── backups/
        └── logs/
```

## Support

For issues or questions:
1. Check this documentation
2. Review logs in `~/apps/<app-name>/logs/`
3. Check email notifications
4. Review app-specific `config.sh` and custom functions

---

**Version**: 2.0 (New Modular Architecture)
**Last Updated**: October 2025
**Maintained By**: andrzej@webet.pl
