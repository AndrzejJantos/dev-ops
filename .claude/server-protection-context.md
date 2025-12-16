# Server Protection & Monitoring Context

## Overview

This document provides context for Claude Code sessions regarding server protection, zombie process prevention, and scraper request controls for the CheaperForDrug infrastructure.

## Infrastructure Summary

- **Server**: Hetzner VPS (`ssh hetzner-andrzej`)
- **Apps**: cheaperfordrug-web, cheaperfordrug-api, cheaperfordrug-scraper, brokik-web, brokik-api
- **Scrapers**: 10 product-update-worker containers running Playwright/Chrome

## Current Protection (Implemented)

### Security Hardening (Dec 2025)
After a cryptominer (`linuxsys`) incident, the following was implemented:

1. **Dockerfile.template** (`/DevOps/common/nextjs/Dockerfile.template`):
   - Removed wget/curl from production images
   - Prevents runtime malware download

2. **docker-utils.sh** (`/DevOps/common/docker-utils.sh`):
   - `--read-only` filesystem
   - `--tmpfs /tmp:size=50M`
   - `--cap-drop=ALL`
   - `--security-opt=no-new-privileges:true`
   - Memory and CPU limits

### Zombie Prevention
1. **`init: true`** added to all 10 product-update-worker containers
   - Location: `/cheaperfordrug-scraper/docker-compose.yml`
   - Enables tini as PID 1 to reap orphaned Chrome processes

### Monitoring Script
- **Location**: `/DevOps/scripts/server-monitor.sh`
- **Cron**: Runs every minute
- **Alerts via**: SendGrid email
- **Monitors**:
  - CPU > 50% for 5+ minutes → email alert
  - Zombie processes > 100 → email alert
- **Cooldown**: 30 minutes between same alert types
- **Log**: `/var/log/server-monitor.log`

## Recommended Enhancements (Not Yet Implemented)

### Zombie Prevention Enhancements

```yaml
# Add to scraper docker-compose.yml
services:
  product-update-worker-poland-X:
    init: true           # ✓ Already done
    pids_limit: 200      # Hard cap on processes
    ulimits:
      nproc: 200         # Kernel-level limit
```

Also consider adding `init: true` to web containers (cheaperfordrug-web, brokik-web) which also accumulate `ssl_client` zombies from HTTP requests.

### Monitoring Enhancements

Expand `server-monitor.sh` to include:
- Memory usage > 85% alert
- Disk space < 10% free alert
- Container health status alerts
- Scraper request rate anomaly detection

### Unwanted Pharmacy Request Protection

| Protection | Description | Priority |
|------------|-------------|----------|
| **Rate limiting** | Max requests/min per pharmacy in scraper code | High |
| **Domain whitelist** | Only allow requests to known pharmacy URLs | High |
| **Request quotas** | Daily/hourly limits per pharmacy | Medium |
| **Circuit breaker** | Stop scraping if error rate > 50% | Medium |
| **Schedule enforcement** | Scrapers only run during allowed windows | Medium |
| **Kill switch script** | One command to stop all scrapers | High |
| **Request logging** | Audit trail of all outbound requests | Medium |
| **Egress firewall** | iptables rules to restrict outbound IPs | Low |
| **Anomaly alerts** | Alert if requests/hour spike unexpectedly | Medium |

### Infrastructure Protection

| Protection | Status | Notes |
|------------|--------|-------|
| UFW firewall | Check | Should only allow 22, 80, 443 |
| Fail2ban | Not installed | Block brute-force attacks |
| Unattended upgrades | Check | Auto security patches |
| External uptime monitoring | Not set up | UptimeRobot/Pingdom recommended |

## Key Files

| File | Purpose |
|------|---------|
| `/DevOps/scripts/server-monitor.sh` | CPU/zombie monitoring with email alerts |
| `/DevOps/common/docker-utils.sh` | Docker deployment with security options |
| `/DevOps/common/nextjs/Dockerfile.template` | Hardened Next.js Dockerfile |
| `/DevOps/common/email-config.sh` | Email configuration |
| `/DevOps/common/sendgrid-api.sh` | SendGrid email sending |
| `/cheaperfordrug-scraper/docker-compose.yml` | Scraper containers with init: true |

## Incident History

### Dec 2025 - Cryptominer Attack
- **Symptom**: 267,310 zombie processes, 100% CPU, slow website
- **Cause**: `linuxsys` cryptominer downloaded via wget/curl into web container
- **Entry**: Likely RCE vulnerability exploited at runtime
- **Fix**: Security hardening (read-only, no wget/curl, cap-drop)

## Common Tasks

### Stop All Scrapers Immediately
```bash
ssh hetzner-andrzej 'cd /home/andrzej/apps/cheaperfordrug-scraper && docker-compose stop'
```

### Check Current Zombie Count
```bash
ssh hetzner-andrzej 'ps aux | grep -c " Z "'
```

### Check Monitoring Log
```bash
ssh hetzner-andrzej 'tail -50 /var/log/server-monitor.log'
```

### Restart Scrapers with New Config
```bash
ssh hetzner-andrzej 'cd /home/andrzej/apps/cheaperfordrug-scraper && git pull && docker-compose up -d'
```

## Email Alert Configuration

Alerts are sent via SendGrid using credentials from `/DevOps/common/email-config.sh`:
- **From**: biuro@webet.pl (configurable via DEPLOYMENT_EMAIL_FROM)
- **To**: andrzej@webet.pl (configurable via DEPLOYMENT_EMAIL_TO)
