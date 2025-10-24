# Quick Start Guide

## New Architecture at a Glance

### Directory Structure
```
DevOps/
├── common/
│   ├── utils.sh                 # Shared utilities
│   ├── docker-utils.sh          # Docker operations
│   ├── rails/                   # Rails framework
│   │   ├── setup.sh
│   │   └── deploy.sh
│   └── nodejs/                  # Node.js framework
│       ├── setup.sh
│       └── deploy.sh
├── apps/
│   ├── cheaperfordrug-landing/  # Rails app (example)
│   │   ├── config.sh
│   │   ├── setup.sh             ⭐ Executable
│   │   ├── deploy.sh            ⭐ Executable
│   │   └── nginx.conf.template
│   └── _examples/               # Templates
│       └── nodejs-app-template/
└── scripts/
    ├── console.sh               # Rails console
    └── rails-task.sh            # Rails tasks
```

## Usage Comparison

### Old Way
```bash
cd ~/DevOps
./scripts/setup-app.sh cheaperfordrug-landing
./scripts/deploy-app.sh cheaperfordrug-landing deploy
./scripts/deploy-app.sh cheaperfordrug-landing scale 4
```

### New Way
```bash
cd ~/DevOps
./apps/cheaperfordrug-landing/setup.sh
./apps/cheaperfordrug-landing/deploy.sh deploy
./apps/cheaperfordrug-landing/deploy.sh scale 4
```

Or even shorter:
```bash
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy
./deploy.sh scale 4
```

## Quick Commands

### Setup New Rails App
```bash
cd ~/DevOps/apps
mkdir my-rails-app
cp cheaperfordrug-landing/{config.sh,setup.sh,deploy.sh,nginx.conf.template} my-rails-app/
cd my-rails-app
nano config.sh  # Edit configuration
./setup.sh
```

### Setup New Node.js App
```bash
cd ~/DevOps/apps
cp -r _examples/nodejs-app-template my-nodejs-app
cd my-nodejs-app
nano config.sh  # Edit configuration
./setup.sh
```

### Deploy
```bash
cd ~/DevOps/apps/<app-name>
./deploy.sh deploy       # Deploy with default scale
./deploy.sh deploy 4     # Deploy with 4 instances
./deploy.sh restart      # Restart current containers
./deploy.sh scale 6      # Scale to 6 instances
./deploy.sh stop         # Stop all containers
```

### Console & Tasks (Rails)
```bash
cd ~/DevOps
./scripts/console.sh <app-name>
./scripts/rails-task.sh <app-name> db:migrate
```

## Key Benefits

✅ **Visible** - Each app has its own scripts in its directory
✅ **Customizable** - Override any function per app
✅ **Maintainable** - Common logic in framework modules
✅ **Flexible** - Supports Rails and Node.js
✅ **Clear** - New developers can immediately see how to deploy

## File Purposes

### App Files (apps/<app-name>/)
- **config.sh** - App configuration (ports, domain, database, etc.)
- **setup.sh** - Setup script (runs once, creates infrastructure)
- **deploy.sh** - Deployment script (runs often, deploys code)
- **nginx.conf.template** - Nginx configuration template

### Common Files (common/)
- **utils.sh** - Logging, database, backups, notifications
- **docker-utils.sh** - Docker operations, health checks, scaling
- **rails/setup.sh** - Rails-specific setup functions
- **rails/deploy.sh** - Rails-specific deployment functions
- **nodejs/setup.sh** - Node.js-specific setup functions
- **nodejs/deploy.sh** - Node.js-specific deployment functions

### Helper Scripts (scripts/)
- **console.sh** - Access Rails console
- **rails-task.sh** - Run Rails tasks/commands

## Customization Example

Want custom behavior? Just override functions:

```bash
# In apps/my-app/setup.sh

source "${DEVOPS_DIR}/common/rails/setup.sh"

# Override asset precompilation
rails_precompile_assets() {
    log_info "Custom asset build with Webpack..."
    npm ci
    npm run build
    bundle exec rails assets:precompile
    return 0
}

# Use standard workflow (calls your override)
rails_setup_workflow
```

## Port Allocation

Each app needs unique ports and Redis DB:

| App | Ports | Redis DB |
|-----|-------|----------|
| cheaperfordrug-landing | 3010-3019 | 1 |
| my-app | 3020-3029 | 2 |
| another-app | 3030-3039 | 3 |

Set in config.sh:
```bash
export BASE_PORT=3020          # Start of range
export PORT_RANGE_END=3029     # End of range (10 ports)
export REDIS_DB_NUMBER=2       # Unique per app
```

## Documentation

- **ARCHITECTURE.md** - Complete architecture documentation
- **MIGRATION_GUIDE.md** - Migration from old system
- **apps/_examples/** - Templates for new apps
- **README.md** - Original documentation (still relevant)

## Next Steps

1. Review example: `apps/cheaperfordrug-landing/`
2. Read architecture: `ARCHITECTURE.md`
3. Create your app from template
4. Deploy and enjoy!

## Support

Questions? Check:
1. ARCHITECTURE.md - Detailed documentation
2. MIGRATION_GUIDE.md - Migration help
3. apps/_examples/ - Templates
4. apps/cheaperfordrug-landing/ - Working example

---

**Version 2.0** | October 2025 | andrzej@webet.pl
