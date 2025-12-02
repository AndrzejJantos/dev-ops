# Elasticsearch Monitoring System

**Version:** 1.0.0
**Last Updated:** 2025-12-02
**Status:** Production Ready

## Overview

Automated health monitoring and auto-restart system for Elasticsearch, designed to ensure high availability and minimize downtime.

### Features

- **Automated Health Checks** - Runs every 5 minutes via cron
- **Retry Logic** - 3 attempts with 5-second delays before triggering restart
- **Auto-Restart** - Automatically restarts Elasticsearch via docker-compose if unhealthy
- **Timestamped Logging** - All actions logged with timestamps for audit trail
- **Log Rotation** - Automatic log rotation via logrotate (30-day retention)
- **Cluster Health Monitoring** - Checks cluster status (green/yellow/red)
- **Email Alerts** - Optional email notifications for failures and restarts
- **Configurable** - Environment variables for easy customization
- **Production-Grade** - Based on existing DevOps patterns in this repository

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Cron Scheduler                            │
│              (Every 5 minutes)                               │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│            monitor-elasticsearch.sh                          │
│                                                              │
│  1. Health Check (3 retries)                                │
│  2. Cluster Health Status                                   │
│  3. Auto-restart if unhealthy                               │
│  4. Post-restart verification                               │
│  5. Alert notifications                                     │
└───────────────────────┬─────────────────────────────────────┘
                        │
        ┌───────────────┴──────────────┬──────────────┐
        ▼                              ▼              ▼
┌──────────────────┐        ┌──────────────────┐  ┌─────────────┐
│  Elasticsearch   │        │  Docker Compose  │  │  Logging    │
│  (HTTP API)      │        │  (Restart)       │  │  System     │
└──────────────────┘        └──────────────────┘  └─────────────┘
```

## Components

### 1. Monitoring Script

**Location:** `/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh`

**Responsibilities:**
- Execute health checks against Elasticsearch endpoint
- Implement retry logic with configurable delays
- Trigger docker-compose restart on repeated failures
- Log all activities with timestamps
- Send email alerts (optional)

**Health Check Process:**
1. Attempt HTTP request to Elasticsearch endpoint
2. If successful, check cluster health status
3. If failed, retry up to 3 times with 5-second delays
4. If all retries fail, trigger restart
5. Wait 30 seconds after restart
6. Verify Elasticsearch is responding
7. Log outcome and send alerts

**Exit Codes:**
- `0` - Elasticsearch healthy
- `1` - Elasticsearch unhealthy or restart failed

### 2. Cron Configuration

**Location:** `/etc/cron.d/elasticsearch-monitoring`

**Schedule:** Every 5 minutes (`*/5 * * * *`)

**User:** `andrzej` (must have docker permissions)

**Environment Variables:**
- `ELASTICSEARCH_URL` - Elasticsearch endpoint (default: http://localhost:9200)
- `DOCKER_COMPOSE_DIR` - Path to docker-compose directory (optional)
- `ES_SERVICE_NAME` - Service name in docker-compose (default: elasticsearch)
- `SEND_ALERTS` - Enable email alerts (default: false)
- `ALERT_EMAIL` - Email address for alerts

**Output:** Logs to `/home/andrzej/logs/elasticsearch-monitoring/cron.log`

### 3. Log Rotation

**Location:** `/etc/logrotate.d/elasticsearch-monitoring`

**Configuration:**
- **Monitoring logs** - Daily rotation, 30-day retention
- **Cron logs** - Weekly rotation, 8-week retention
- **Compression** - Enabled with delayed compression
- **Date extension** - Files named with YYYYMMDD format

**Log Files:**
- `/home/andrzej/logs/elasticsearch-monitoring/monitor.log` - Main monitoring log
- `/home/andrzej/logs/elasticsearch-monitoring/cron.log` - Cron execution log
- `/home/andrzej/logs/elasticsearch-monitoring/*.log-YYYYMMDD.gz` - Rotated logs

## Installation

### Prerequisites

- Ubuntu server with systemd and cron
- Elasticsearch running (local or remote)
- Docker and docker-compose (if Elasticsearch runs in containers)
- User `andrzej` with docker permissions
- SSH access to production server (port 2222)

### Quick Installation

From your local development machine:

```bash
cd /Users/andrzej/Development/CheaperForDrug/DevOps
./scripts/deploy-elasticsearch-monitoring.sh
```

This script will:
1. Verify all required files exist locally
2. Copy files to the production server
3. Install cron and logrotate configurations
4. Create log directories
5. Set proper permissions
6. Run test execution
7. Display usage instructions

### Manual Installation

If you need to install manually on the server:

```bash
# 1. Copy files to server
scp -P 2222 DevOps/scripts/monitor-elasticsearch.sh andrzej@65.109.22.232:/home/andrzej/DevOps/scripts/
scp -P 2222 DevOps/config/cron.d/elasticsearch-monitoring andrzej@65.109.22.232:/home/andrzej/DevOps/config/cron.d/
scp -P 2222 DevOps/config/logrotate.d/elasticsearch-monitoring andrzej@65.109.22.232:/home/andrzej/DevOps/config/logrotate.d/

# 2. SSH to server
ssh -p 2222 andrzej@65.109.22.232

# 3. Set permissions
chmod +x /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# 4. Create log directory
mkdir -p /home/andrzej/logs/elasticsearch-monitoring

# 5. Install cron configuration
sudo cp /home/andrzej/DevOps/config/cron.d/elasticsearch-monitoring /etc/cron.d/
sudo chmod 644 /etc/cron.d/elasticsearch-monitoring
sudo chown root:root /etc/cron.d/elasticsearch-monitoring

# 6. Install logrotate configuration
sudo cp /home/andrzej/DevOps/config/logrotate.d/elasticsearch-monitoring /etc/logrotate.d/
sudo chmod 644 /etc/logrotate.d/elasticsearch-monitoring
sudo chown root:root /etc/logrotate.d/elasticsearch-monitoring

# 7. Reload cron
sudo systemctl reload cron

# 8. Test
/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh
```

## Configuration

### Environment Variables

Edit `/etc/cron.d/elasticsearch-monitoring` to configure:

```bash
# Elasticsearch endpoint
ELASTICSEARCH_URL=http://localhost:9200

# If Elasticsearch runs in docker-compose
DOCKER_COMPOSE_DIR=/home/andrzej/apps/elasticsearch
ES_SERVICE_NAME=elasticsearch

# Email alerts (optional)
SEND_ALERTS=true
ALERT_EMAIL=andrzej@webet.pl
```

### Adjusting Check Frequency

Edit `/etc/cron.d/elasticsearch-monitoring`:

```bash
# Every 5 minutes (default)
*/5 * * * * andrzej /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# Every 10 minutes
*/10 * * * * andrzej /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# Every 15 minutes
*/15 * * * * andrzej /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# Hourly
0 * * * * andrzej /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh
```

After editing, reload cron:
```bash
sudo systemctl reload cron
```

### Retry Configuration

Edit `/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh`:

```bash
# Number of retry attempts before restart
MAX_RETRY_ATTEMPTS=3

# Seconds to wait between retries
RETRY_DELAY=5
```

## Usage

### Manual Execution

Run the monitoring script manually to test:

```bash
/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh
```

### View Logs

```bash
# Real-time monitoring log
tail -f /home/andrzej/logs/elasticsearch-monitoring/monitor.log

# Real-time cron log
tail -f /home/andrzej/logs/elasticsearch-monitoring/cron.log

# Last 100 lines
tail -100 /home/andrzej/logs/elasticsearch-monitoring/monitor.log

# Search for errors
grep ERROR /home/andrzej/logs/elasticsearch-monitoring/monitor.log

# View rotated logs
zcat /home/andrzej/logs/elasticsearch-monitoring/monitor.log-20251202.gz
```

### Check Cron Status

```bash
# Verify cron job is loaded
sudo grep elasticsearch /etc/cron.d/elasticsearch-monitoring

# View cron execution in system logs
sudo tail -f /var/log/syslog | grep CRON

# Check cron service status
sudo systemctl status cron
```

### Test Logrotate

```bash
# Dry run (shows what would happen)
sudo logrotate -d /etc/logrotate.d/elasticsearch-monitoring

# Force rotation (for testing)
sudo logrotate -f /etc/logrotate.d/elasticsearch-monitoring

# Check logrotate status
sudo cat /var/lib/logrotate/status | grep elasticsearch
```

## Monitoring Output

### Successful Health Check

```
[2025-12-02 14:35:01] [INFO] ======================================================================
[2025-12-02 14:35:01] [INFO] Starting Elasticsearch health check (URL: http://localhost:9200)
[2025-12-02 14:35:01] [INFO] ======================================================================
[2025-12-02 14:35:01] [INFO] Health check attempt 1/3
[2025-12-02 14:35:01] [SUCCESS] Elasticsearch is responding
[2025-12-02 14:35:01] [INFO] Cluster health status: green
[2025-12-02 14:35:01] [SUCCESS] Elasticsearch cluster health is acceptable: green
[2025-12-02 14:35:01] [SUCCESS] Elasticsearch monitoring check completed - service is healthy
[2025-12-02 14:35:01] [INFO] ======================================================================
[2025-12-02 14:35:01] [INFO] Elasticsearch monitoring completed with exit code: 0
[2025-12-02 14:35:01] [INFO] ======================================================================
```

### Failed Health Check with Auto-Restart

```
[2025-12-02 14:40:01] [INFO] ======================================================================
[2025-12-02 14:40:01] [INFO] Starting Elasticsearch health check (URL: http://localhost:9200)
[2025-12-02 14:40:01] [INFO] ======================================================================
[2025-12-02 14:40:01] [INFO] Health check attempt 1/3
[2025-12-02 14:40:01] [ERROR] Elasticsearch health check failed (attempt 1/3)
[2025-12-02 14:40:01] [INFO] Waiting 5 seconds before retry...
[2025-12-02 14:40:06] [INFO] Health check attempt 2/3
[2025-12-02 14:40:06] [ERROR] Elasticsearch health check failed (attempt 2/3)
[2025-12-02 14:40:06] [INFO] Waiting 5 seconds before retry...
[2025-12-02 14:40:11] [INFO] Health check attempt 3/3
[2025-12-02 14:40:11] [ERROR] Elasticsearch health check failed (attempt 3/3)
[2025-12-02 14:40:11] [ERROR] Elasticsearch is unhealthy after 3 attempts
[2025-12-02 14:40:11] [WARNING] Attempting to restart Elasticsearch...
[2025-12-02 14:40:11] [INFO] Restarting Elasticsearch via docker-compose in /home/andrzej/apps/elasticsearch
[2025-12-02 14:40:11] [INFO] Restarting service: elasticsearch
[2025-12-02 14:40:15] [SUCCESS] Docker-compose restart completed
[2025-12-02 14:40:15] [INFO] Restart completed, waiting 30 seconds for service to come up...
[2025-12-02 14:40:45] [SUCCESS] Elasticsearch is now responding after restart
[2025-12-02 14:40:45] [INFO] Cluster health status: yellow
[2025-12-02 14:40:45] [INFO] ======================================================================
[2025-12-02 14:40:45] [INFO] Elasticsearch monitoring completed with exit code: 0
[2025-12-02 14:40:45] [INFO] ======================================================================
```

## Troubleshooting

### Cron Job Not Running

**Symptoms:** No entries in cron.log, monitoring script never executes

**Diagnosis:**
```bash
# Check if cron is running
sudo systemctl status cron

# Verify cron file exists and has correct permissions
ls -la /etc/cron.d/elasticsearch-monitoring

# Check system logs for cron errors
sudo tail -100 /var/log/syslog | grep CRON
```

**Solutions:**
```bash
# Reload cron service
sudo systemctl reload cron

# Restart cron service (if reload doesn't work)
sudo systemctl restart cron

# Fix permissions if needed
sudo chmod 644 /etc/cron.d/elasticsearch-monitoring
sudo chown root:root /etc/cron.d/elasticsearch-monitoring
```

### Script Execution Errors

**Symptoms:** Errors in monitor.log, script fails to run

**Diagnosis:**
```bash
# Run script manually to see errors
/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# Check script permissions
ls -la /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# Check if user has docker permissions
docker ps
```

**Solutions:**
```bash
# Fix script permissions
chmod +x /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# Add user to docker group (if needed)
sudo usermod -aG docker andrzej

# Log out and back in for group changes to take effect
```

### Elasticsearch Not Restarting

**Symptoms:** Script detects failure but restart fails

**Diagnosis:**
```bash
# Check if docker-compose directory is set correctly
grep DOCKER_COMPOSE_DIR /etc/cron.d/elasticsearch-monitoring

# Check if docker-compose file exists
ls -la /home/andrzej/apps/elasticsearch/docker-compose.yml

# Check docker-compose status
cd /home/andrzej/apps/elasticsearch
docker-compose ps
```

**Solutions:**
```bash
# Set correct DOCKER_COMPOSE_DIR in cron file
sudo nano /etc/cron.d/elasticsearch-monitoring

# Verify docker-compose works manually
cd /home/andrzej/apps/elasticsearch
docker-compose restart elasticsearch
```

### Logs Not Rotating

**Symptoms:** Log files growing indefinitely

**Diagnosis:**
```bash
# Check logrotate configuration
sudo logrotate -d /etc/logrotate.d/elasticsearch-monitoring

# Check logrotate status
sudo cat /var/lib/logrotate/status | grep elasticsearch

# Check log file sizes
du -h /home/andrzej/logs/elasticsearch-monitoring/
```

**Solutions:**
```bash
# Fix logrotate configuration permissions
sudo chmod 644 /etc/logrotate.d/elasticsearch-monitoring
sudo chown root:root /etc/logrotate.d/elasticsearch-monitoring

# Force rotation manually
sudo logrotate -f /etc/logrotate.d/elasticsearch-monitoring
```

### Email Alerts Not Working

**Symptoms:** No email alerts received on failures

**Diagnosis:**
```bash
# Check if SEND_ALERTS is enabled
grep SEND_ALERTS /etc/cron.d/elasticsearch-monitoring

# Check if email-notification.sh exists
ls -la /home/andrzej/DevOps/common/email-notification.sh

# Check SendGrid configuration
grep SENDGRID /home/andrzej/DevOps/common/email-config.sh
```

**Solutions:**
```bash
# Enable alerts in cron file
sudo nano /etc/cron.d/elasticsearch-monitoring
# Set: SEND_ALERTS=true

# Configure email settings
nano /home/andrzej/DevOps/common/email-config.sh
# Set: SENDGRID_API_KEY and DEPLOYMENT_EMAIL_TO

# Test email system
/home/andrzej/DevOps/scripts/test-email-notification.sh
```

## Maintenance

### Daily

- Monitor the logs for any repeated failures
- Check Elasticsearch cluster health manually
- Verify cron job is executing (check cron.log)

```bash
# Quick daily check
tail -50 /home/andrzej/logs/elasticsearch-monitoring/monitor.log | grep ERROR
```

### Weekly

- Review rotated logs for patterns
- Check disk space usage for logs
- Verify logrotate is working

```bash
# Check log sizes
du -sh /home/andrzej/logs/elasticsearch-monitoring/*

# List rotated files
ls -lh /home/andrzej/logs/elasticsearch-monitoring/*.gz
```

### Monthly

- Review and adjust monitoring frequency if needed
- Test manual restart procedure
- Update documentation if configuration changes

### Disabling Monitoring

To temporarily disable monitoring:

```bash
# Comment out the cron line
sudo nano /etc/cron.d/elasticsearch-monitoring
# Add # to beginning of cron line

# Reload cron
sudo systemctl reload cron
```

To re-enable, remove the `#` and reload cron.

## Integration with Existing Systems

### Email Notifications

The monitoring script integrates with the existing SendGrid email notification system in this DevOps repository:

- Uses `/home/andrzej/DevOps/common/email-notification.sh`
- Follows the same patterns as deployment notifications
- Requires SendGrid configuration in `email-config.sh`

### Common Utilities

The monitoring script uses shared utilities from the DevOps repository:

- `common/utils.sh` - Logging functions, color codes
- `common/elasticsearch-check.sh` - Elasticsearch health check functions
- `common/docker-utils.sh` - Docker container management (if needed)

### Logging

Follows the same logging patterns as other DevOps scripts:

- Timestamped entries: `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`
- Log levels: INFO, SUCCESS, WARNING, ERROR
- Structured format for easy parsing and analysis

## Performance Considerations

### Resource Usage

- **CPU:** Minimal (curl requests only)
- **Memory:** < 10 MB per execution
- **Disk:** ~1 MB/day log growth (with rotation)
- **Network:** 1 HTTP request per check (every 5 minutes = ~288/day)

### Impact on Elasticsearch

- Health checks use lightweight `/_cluster/health` endpoint
- No impact on indexing or search performance
- No data written to Elasticsearch

### Restart Impact

When auto-restart is triggered:

- ~5-30 seconds downtime (depending on ES configuration)
- In-flight requests may fail
- Applications should implement retry logic
- Consider coordinating restarts with low-traffic periods

## Security Considerations

### Credentials

If Elasticsearch requires authentication:

```bash
# Set in cron file (not recommended - credentials visible in process list)
ELASTICSEARCH_USERNAME=admin
ELASTICSEARCH_PASSWORD=secret

# Better: Use environment file (more secure)
# Create /home/andrzej/.elasticsearch-monitor.env
echo "ELASTICSEARCH_USERNAME=admin" > ~/.elasticsearch-monitor.env
echo "ELASTICSEARCH_PASSWORD=secret" >> ~/.elasticsearch-monitor.env
chmod 600 ~/.elasticsearch-monitor.env

# Source in cron file
. /home/andrzej/.elasticsearch-monitor.env
```

### File Permissions

All files have appropriate permissions:

- Scripts: `755` (executable by owner, readable by all)
- Config files: `644` (readable by all, writable by owner)
- Log files: `644` (readable by all, writable by owner)
- Cron/logrotate: `644` owned by `root:root`

### Log Security

Logs may contain sensitive information:

- Elasticsearch URLs
- Error messages with internal details
- Keep log directory permissions restrictive
- Consider encrypting archived logs if compliance required

## Version History

### Version 1.0.0 (2025-12-02)

**Initial Release**

- Automated health monitoring every 5 minutes
- 3-retry logic with 5-second delays
- Auto-restart via docker-compose
- Comprehensive logging with timestamps
- Automatic log rotation (30-day retention)
- Cluster health status monitoring
- Email alert integration (optional)
- Deployment automation script
- Complete documentation

## Support

### Log Analysis

For debugging issues, provide:

1. Last 100 lines of monitor.log
2. Cron configuration (`/etc/cron.d/elasticsearch-monitoring`)
3. Elasticsearch version and configuration
4. Docker-compose configuration (if applicable)
5. System logs (`/var/log/syslog`)

### Common Questions

**Q: Can this monitor AWS Elasticsearch/OpenSearch?**
A: Yes, set `ELASTICSEARCH_URL` to your AWS endpoint. Auto-restart won't work (AWS managed), but health checks and alerts will.

**Q: How do I monitor multiple Elasticsearch clusters?**
A: Create separate cron entries with different environment variables and log directories.

**Q: What if Elasticsearch is not in docker-compose?**
A: The monitoring and health checks still work. Auto-restart functionality won't be available unless you modify the restart function to use your management method (systemd, etc.).

**Q: Can I run this on macOS for local development?**
A: Yes, but cron/logrotate paths differ. Main script works on macOS, but cron/logrotate configurations are Linux-specific.

## References

- [Elasticsearch Health API](https://www.elastic.co/guide/en/elasticsearch/reference/current/cluster-health.html)
- [Cron Format](https://crontab.guru/)
- [Logrotate Configuration](https://linux.die.net/man/8/logrotate)
- [DevOps Repository Structure](../README.md)

---

**Maintained By:** DevOps Team
**Contact:** andrzej@webet.pl
**Last Review:** 2025-12-02
