# CheaperForDrug API Deployment

## Directory Structure

This directory contains **configuration only**. The deployed application lives at:
```
~/apps/cheaperfordrug-api/
```

### Quick Navigation
```bash
# From config dir to deployed app:
cd ~/DevOps/apps/cheaperfordrug-api
./deploy.sh             # Deploy from here

# From deployed app to config:
cd ~/apps/cheaperfordrug-api
cd ~/DevOps/apps/cheaperfordrug-api

# Or use the symlink:
cd ~/apps/cheaperfordrug-api/config  # → ~/DevOps/apps/cheaperfordrug-api
```

## Files Here (Config)
- `config.sh` - Application configuration
- `deploy.sh` - Deployment script
- `setup.sh` - Initial setup script
- `nginx.conf.template` - Nginx configuration template

## Files in ~/apps/cheaperfordrug-api/ (Deployed)
- `repo/` - Git repository (actual application code)
- `logs/` - Application logs
- `backups/` - Database backups
- `docker-images/` - Docker image backups
- `console.sh` - Rails console wrapper
- `logs.sh` - Log viewer
- `.env.production` - Environment variables (secrets)

## Common Operations

```bash
# Always run from config directory
cd ~/DevOps/apps/cheaperfordrug-api

# Deploy
./deploy.sh

# Scale
./deploy.sh scale 3

# View logs
./deploy.sh logs

# Rails console
./deploy.sh console
```

## Why Two Directories?

**Separation of concerns:**
- `~/DevOps/apps/` - Version controlled, safe to git pull
- `~/apps/` - Contains data, secrets, backups - never committed to git
