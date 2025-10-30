# CheaperForDrug Scraper

Automated pharmacy data scraper for Poland, Germany, and Czech Republic. Runs in Docker containers with NordVPN for geo-specific access.

## Quick Start

### 1. Prerequisites

Get your NordVPN access token from: [https://my.nordaccount.com/dashboard/nordvpn/access-tokens/](https://my.nordaccount.com/dashboard/nordvpn/access-tokens/)

### 2. Set Environment Variables

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, or `~/.bash_profile`):

```bash
export NORDVPN_TOKEN="your_token_here"
export SCRAPER_AUTH_TOKEN="Andrzej12345"  # Optional, defaults to this value
export SENDGRID_API_KEY="SG.xxx..."       # Optional, for email notifications
```

Reload your shell:

```bash
source ~/.bashrc  # or source ~/.zshrc
```

### 3. Run Setup

```bash
./setup.sh
```

That's it! The script will:
- Check prerequisites (Docker, docker-compose, git, NordVPN token)
- Create necessary directories
- Clone/update the repository
- Build Docker images
- Start all containers
- Show status

## Daily Operations

### Check Status

```bash
./setup.sh --status
```

or

```bash
npm run status
```

### Watch Logs

Watch all containers:

```bash
npm run scrapers:watch
```

Watch specific country:

```bash
npm run scrapers:watch:poland
npm run scrapers:watch:germany
npm run scrapers:watch:czech
```

### Start Scrapers Manually

Start all:

```bash
npm run scrapers:start
```

Start specific country:

```bash
npm run scrapers:start:poland
npm run scrapers:start:germany
npm run scrapers:start:czech
```

### Stop Scrapers

```bash
npm run scrapers:stop
```

### Container Management

```bash
./setup.sh --restart    # Restart all containers
./setup.sh --stop       # Stop all containers
./setup.sh --logs       # Show and follow logs
```

## Automatic Scheduling

Scrapers run automatically on:
- **Monday** at 7:00 AM (Europe/Warsaw timezone)
- **Thursday** at 7:00 AM (Europe/Warsaw timezone)

Each container has its own cron job configured internally.

## Architecture

### Containers

Three independent containers, one per country:

- **cheaperfordrug-scraper-poland** - NordVPN connected to Poland
- **cheaperfordrug-scraper-germany** - NordVPN connected to Germany
- **cheaperfordrug-scraper-czech** - NordVPN connected to Czech Republic

### Data Persistence

Each container has isolated persistent directories:

```
~/apps/cheaperfordrug-scraper/
├── logs/
│   ├── poland/      # Poland logs
│   ├── germany/     # Germany logs
│   └── czech/       # Czech logs
├── outputs/
│   ├── poland/      # Poland output files
│   ├── germany/     # Germany output files
│   └── czech/       # Czech output files
└── state/
    ├── poland/      # Poland state files
    ├── germany/     # Germany state files
    └── czech/       # Czech state files
```

### VPN Configuration

Each container:
- Connects to NordVPN in its respective country
- Rotates VPN servers every 15 minutes (configurable)
- Automatically reconnects on disconnection
- Includes health checks for VPN connectivity

## Email Notifications

Deployment notifications are automatically sent via SendGrid when configured.

### Setup SendGrid API Key

1. **Get API Key** from SendGrid dashboard: [https://app.sendgrid.com/settings/api_keys](https://app.sendgrid.com/settings/api_keys)

2. **Add to your shell profile** (`~/.bashrc`, `~/.zshrc`, or `~/.bash_profile`):
   ```bash
   export SENDGRID_API_KEY="SG.xxx..."
   ```

3. **Reload your shell**:
   ```bash
   source ~/.bashrc  # or source ~/.zshrc
   ```

### Email Configuration

- **From:** webet1@webet.pl
- **To:** andrzej@webet.pl
- **Triggers:** Deployment success and failure events

### Test Email Functionality

Test email sending:
```bash
cd /Users/andrzej/Development/CheaperForDrug/DevOps/apps/cheaperfordrug-scraper
./.scripts/send-email.sh "Test Subject" "<h1>Test Email</h1><p>This is a test.</p>"
```

Test deployment summary:
```bash
./.scripts/deployment-summary.sh success 120
```

### Email Content

Deployment emails include:

**Success Emails:**
- Deployment status and timestamp
- Container health status (Poland, Germany, Czech)
- Git commit information
- Deployment duration
- Next scheduled run time
- Quick command reference

**Failure Emails:**
- Error details and diagnostic information
- Container status at time of failure
- Recommended troubleshooting steps
- Action required alerts

### Disable Email Notifications

To disable email notifications, simply unset the environment variable:
```bash
unset SENDGRID_API_KEY
```

Or remove it from your shell profile and reload:
```bash
source ~/.bashrc
```

Deployment will continue normally without sending emails.

## Configuration

### Environment Variables

Set these in your shell profile or export before running:

| Variable | Description | Default |
|----------|-------------|---------|
| `NORDVPN_TOKEN` | NordVPN access token | **Required** |
| `SCRAPER_AUTH_TOKEN` | API authentication token | `Andrzej12345` |
| `API_TOKEN` | Alternative API token | Uses `SCRAPER_AUTH_TOKEN` |
| `SENDGRID_API_KEY` | SendGrid API key for email notifications | Optional |
| `SEND_TO_API` | Send data to API | `true` |
| `HEADLESS` | Run browser in headless mode | `true` |
| `LOG_LEVEL` | Logging level | `info` |
| `VPN_ROTATE_INTERVAL` | VPN rotation interval (minutes) | `15` |

### API Endpoint

Data is sent to:
```
http://api-scraper.localtest.me:4100/api/scraper/online_pharmacy_drugs
```

Ensure this API is accessible from your host machine.

## Updating

### Deploy Latest Code

```bash
./setup.sh --deploy
```

This will:
- Pull latest code from repository
- Rebuild Docker images
- Restart containers with new code

### Force Rebuild

```bash
./setup.sh --rebuild
```

Force rebuilds images from scratch (removes cached layers).

## NPM Commands Reference

### Scraper Operations

```bash
npm run scrapers:watch           # Watch all logs (color-coded)
npm run scrapers:watch:poland    # Watch Poland logs
npm run scrapers:watch:germany   # Watch Germany logs
npm run scrapers:watch:czech     # Watch Czech logs

npm run scrapers:start           # Start all scrapers manually
npm run scrapers:start:poland    # Start Poland scraper
npm run scrapers:start:germany   # Start Germany scraper
npm run scrapers:start:czech     # Start Czech scraper

npm run scrapers:stop            # Stop all running scrapers
npm run scrapers:stop:poland     # Stop Poland scraper
npm run scrapers:stop:germany    # Stop Germany scraper
npm run scrapers:stop:czech      # Stop Czech scraper

npm run scrapers:status          # Show container status
npm run scrapers:logs            # View recent logs
```

### Container Operations

```bash
npm run containers:restart       # Restart all containers
npm run containers:stop          # Stop all containers
npm run containers:start         # Start all containers
```

### Cron Management

```bash
npm run cron:status              # Check cron daemon status
npm run cron:list                # List crontab entries
npm run cron:logs                # View cron execution logs
npm run cron:next                # Show next scheduled run
```

### VPN Operations

```bash
npm run vpn:status               # Check VPN connection status
npm run vpn:rotate               # Manually rotate VPN connections
```

### Deployment

```bash
npm run deploy                   # Full deployment
npm run monitor                  # Monitor containers (5s refresh)
npm run help                     # Show all commands
```

## Troubleshooting

### Container Not Starting

Check logs:

```bash
./setup.sh --logs
```

or

```bash
docker logs cheaperfordrug-scraper-poland
```

### VPN Connection Issues

Check VPN status:

```bash
npm run vpn:status
```

Rotate VPN connection:

```bash
npm run vpn:rotate
```

Check if NordVPN token is set:

```bash
echo $NORDVPN_TOKEN
```

### Scraper Not Running

Check container status:

```bash
./setup.sh --status
```

Check cron status:

```bash
npm run cron:status
```

Check cron logs:

```bash
npm run cron:logs
```

### Permission Issues

Ensure docker-scripts are executable:

```bash
chmod +x .docker/*.sh
chmod +x .scripts/*.sh
```

### API Connection Issues

Verify API is accessible:

```bash
curl http://api-scraper.localtest.me:4100/health
```

Check if `api-scraper.localtest.me` resolves to host:

```bash
docker exec cheaperfordrug-scraper-poland ping -c 1 api-scraper.localtest.me
```

### Clean Start

Stop everything and remove containers:

```bash
./setup.sh --clean
```

Then setup again:

```bash
./setup.sh
```

## File Structure

```
cheaperfordrug-scraper/
├── README.md              # This file
├── setup.sh               # Main setup/deployment script
├── package.json           # NPM commands
├── docker-compose.yml     # Container orchestration
├── .docker/               # Docker files (hidden)
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── entrypoint.sh
│   ├── healthcheck.sh
│   ├── vpn-rotate.sh
│   ├── run-scraper.sh
│   └── ...
└── .scripts/              # Helper scripts (hidden)
    ├── deploy.sh
    ├── monitor.sh
    ├── watch-logs.sh
    └── ...
```

## Health Checks

Containers include automatic health checks:

- VPN connectivity
- Process status (supervisord)
- Network connectivity

Unhealthy containers will automatically restart.

Health check interval: 60 seconds
Health check timeout: 10 seconds
Startup grace period: 120 seconds

## Resource Requirements

### Minimum

- CPU: 2 cores
- RAM: 4 GB
- Disk: 10 GB

### Recommended

- CPU: 4 cores
- RAM: 8 GB
- Disk: 20 GB

## Security

- Containers run with minimal privileges
- VPN connections are encrypted
- API tokens should be kept secure
- NordVPN token should not be committed to git
- Each container is isolated

## Logs

### Log Locations

Host machine:
```
~/apps/cheaperfordrug-scraper/logs/<country>/
```

Container logs (Docker):
```bash
docker logs cheaperfordrug-scraper-<country>
```

### Log Rotation

Docker logs are automatically rotated:
- Max size: 10 MB
- Max files: 5

Host logs are retained for 30 days (configurable).

## Backups

Docker images are automatically backed up:
- Location: `~/apps/cheaperfordrug-scraper/docker-images/`
- Retention: Last 10 versions
- Format: Compressed tar archives

## Support

For issues or questions:

1. Check logs: `./setup.sh --logs`
2. Check status: `./setup.sh --status`
3. Check container health: `npm run vpn:status`

## License

Proprietary - CheaperForDrug Team
