# DevOps Hetzner Ops - Memory

## Server Access
- SSH remote: `hetzner-andrzej`
- API scraper container: `cheaperfordrug-api-scraper-1`
- Rails runner available inside container with `RAILS_ENV=production bundle exec rails runner`

## Key Database Models
- `OnlinePharmacyDrug` - scraped pharmacy drug prices
  - `check_requested` (bool) - flags drugs queued for re-scraping
  - `scraping_in_progress` (bool) - flags drugs currently being scraped
  - As of 2026-02-23: ~369K+ records had check_requested=true (full queue)

## Operations Performed
- **2026-02-23**: Reset scraping queue. 369,316 check_requested reset, 10 scraping_in_progress reset. Bulk `update_all` on ~370K rows completed without deadlocks (no need for batching). ~20 records got re-flagged by active scrapers during the operation (race condition, normal).
- **2026-02-23**: Killed cheaperfordrug-landing app entirely. Removed 2 containers (web_1, web_2), 1 image (428MB), and 2 cron jobs (backup-db.sh every 30min, cleanup.sh daily at 2am). Database left intact.
- **2026-02-23**: Removed landing nginx configs from `/etc/nginx/sites-available/`: 1 main config + 4 backups (cheaperfordrug-landing, .backup.20251031_213936, .backup.20251114_083445, .backup.20251114_123339, .backup.20251114_123749). None were symlinked into sites-enabled (already inactive). Nginx reloaded successfully.

## Infrastructure Notes
- Bulk `update_all` on OnlinePharmacyDrug (~370K rows) works fine without batching
- Docker containers use host networking (per CLAUDE.md: 30 API containers on ports 3020-3049)
- Landing app is DECOMMISSIONED (2026-02-23). DB and backups still on disk at `/home/andrzej/apps/cheaperfordrug-landing/`
- Landing nginx config existed but was NOT in sites-enabled (inactive). Proxied to ports 3010/3011 (or 3000/3001 in older backups). Served www.taniejpolek.pl and presale.taniejpolek.pl. All configs removed 2026-02-23.

## Scraper Image Rebuild Notes
- **Dockerfile** at `~/apps/cheaperfordrug-scraper/Dockerfile` expects `docker-scripts/cron-germany` and `docker-scripts/cron-czech` (placeholder files created 2026-02-23, only `cron-poland` has actual cron entries)
- **VPN dead containers**: `docker compose down` leaves containers in "Dead" state due to VPN filesystem locks. `docker rm -f` also fails. Only fix is `sudo systemctl restart docker`. All containers with `restart: always/unless-stopped` auto-recover.
- **drug-processor build context**: Copying scraper repo fails on `nordvpn-data/` (root-owned). Use `rsync --exclude nordvpn-data --exclude node_modules` instead of plain `cp -r`.
- **drug-processor deploy script**: `~/DevOps/apps/drug-processor/deploy.sh` supports `deploy` (build+start), `rebuild-and-run` (build+start+enqueue), `build`, `start`, `stop`, `status`, `logs`, `enqueue`. Does NOT use `--no-cache` by default -- for fresh builds, do manual `docker build --no-cache`.
- **drug-processor config**: `~/DevOps/apps/drug-processor/config.sh` -- build context at `~/apps/drug-processor/build-context/`, Dockerfile at `DevOps/apps/drug-processor/Dockerfile` (relative to build context), env file at `~/apps/drug-processor/.env`.

## Deployment Architecture (as of 2026-02-23)
- **Deploy scripts**: `~/DevOps/apps/{app-name}/deploy.sh` -- supports: `deploy`, `restart`, `stop`, `scale N`, `rollback`
- **Common deploy**: `~/DevOps/common/deploy-app.sh` has `handle_deploy_command` function
- **Container naming**: New deploy system uses underscores (`cheaperfordrug-api_web_1`), old docker-compose v1 used hyphens (`cheaperfordrug-api-web-1`). After full redeploy, old hyphen-style containers must be manually stopped/removed.
- **VPN container gotcha**: `scraper-vpn-poland` holds filesystem locks on `resolv.conf` in its network namespace. `docker compose down` may fail to remove it. Fix: `sudo systemctl restart docker` (all containers with `restart: always` come back automatically).

## Container Inventory (as of 2026-02-23 full redeploy)
- **cheaperfordrug-api**: 2 web (ports 3020-3021), 1 worker (sidekiq), 1 scheduler (clockwork)
- **cheaperfordrug-api-scraper**: 2 scraper API containers
- **cheaperfordrug-web**: 3 web (ports 3055-3057)
- **brokik-api**: 2 web, 1 worker, 1 scheduler
- **brokik-web**: 3 web (ports 3050-3052)
- **scraper-vpn-poland**: 1 VPN container
- **product-update-worker-poland**: 10 workers (1-10)
- **drug-processor**: 1 container
- **cheaperfordrug-elasticsearch**: 1 container (long-running, 5+ weeks)
- **Total**: 28 containers, all running, zero exited

## SSL Certificates
- `api-public.cheaperfordrug.com`: expires 2026-04-15 (50 days)
- `taniejpolek.pl`: expires 2026-03-29 (33 days) -- RENEW SOON
- `api-public.brokik.com`: expires 2026-03-30 (34 days) -- RENEW SOON
- `www.brokik.com`: expires 2026-03-30 (34 days) -- RENEW SOON
- **BUG**: brokik-web deploy tries to add `www.www.brokik.com` to cert (double www). DNS doesn't exist so certbot fails. Non-critical but should fix in config.

## Crontab (as of 2026-02-23)
- `*/30 * * * *` - API backup
- `0 2 * * *` - Web cleanup, API cleanup
- `*/30 * * * *` - Brokik API backup
- `0 3 * * 0` - Scraper log cleanup (weekly Sunday)
- `*/5 * * * *` - Elasticsearch monitor
- `* * * * *` - Server monitor (every minute)
- `0 * * * *` - Scraper hourly report
