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
- `nginx.conf.template` - Nginx configuration template (HTTPS public/internal)
- `nginx-local-scraper.conf` - Local scraper access (HTTP port 4100)
- `setup-local-scraper-access.sh` - Install local scraper nginx config

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

## Local Scraper Access

The scraper runs on the same machine as the API and needs local HTTP access with subdomain routing.

### Why Subdomain Matters

Rails routes are configured with subdomain constraints (see `config/routes.rb:52-69`):
```ruby
constraints subdomain: "api-scraper" do
  namespace :api do
    namespace :scraper do
      resources :online_pharmacy_drugs, only: [:create, :update]
    end
  end
end
```

Without the correct subdomain, routes won't match.

### Architecture

```
Scraper (same machine)
    ↓
http://api-scraper.localtest.me:4100
    ↓
(localtest.me resolves to 127.0.0.1)
    ↓
Nginx listening on localhost:4100
    ↓
Load balances to Docker containers
    ↓
localhost:3020 (cheaperfordrug-api_web_1)
localhost:3021 (cheaperfordrug-api_web_2)
```

### Setup

**One-time setup on production server:**
```bash
cd ~/DevOps/apps/cheaperfordrug-api
sudo ./setup-local-scraper-access.sh
```

This installs nginx configuration for port 4100 and reloads nginx.

### Testing

```bash
# Test health endpoint
curl http://api-scraper.localtest.me:4100/up
curl http://localhost:4100/up

# View logs
sudo tail -f /var/log/nginx/api-scraper-local-access.log
sudo tail -f /var/log/nginx/api-scraper-local-error.log
```

### Scraper Configuration

The scraper `.env` file should contain:
```bash
API_ENDPOINT=http://api-scraper.localtest.me:4100/api/scraper/online_pharmacy_drugs
API_TOKEN=your_token_here
```

### Key Points

1. **Port 4100** - Local HTTP access (no SSL needed for localhost)
2. **Subdomain preserved** - Nginx passes `Host: api-scraper.localtest.me:4100` to Rails
3. **Load balanced** - Nginx distributes requests across both web containers
4. **No internet** - Everything stays on localhost (127.0.0.1)
