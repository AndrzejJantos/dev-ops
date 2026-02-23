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
- **2026-02-23**: Killed cheaperfordrug-landing app entirely. Removed 2 containers (web_1, web_2), 1 image (428MB), and 2 cron jobs (backup-db.sh every 30min, cleanup.sh daily at 2am). Database left intact. No nginx config existed for landing.

## Infrastructure Notes
- Bulk `update_all` on OnlinePharmacyDrug (~370K rows) works fine without batching
- Docker containers use host networking (per CLAUDE.md: 30 API containers on ports 3020-3049)
- Landing app is DECOMMISSIONED (2026-02-23). DB and backups still on disk at `/home/andrzej/apps/cheaperfordrug-landing/`
- Landing had no nginx upstream/config -- was likely accessed directly or proxied differently

## Crontab (as of 2026-02-23)
- `*/30 * * * *` - API backup
- `0 2 * * *` - Web cleanup, API cleanup
- `*/30 * * * *` - Brokik API backup
- `0 3 * * 0` - Scraper log cleanup (weekly Sunday)
- `*/5 * * * *` - Elasticsearch monitor
- `* * * * *` - Server monitor (every minute)
- `0 * * * *` - Scraper hourly report
