# Elasticsearch Monitoring - Quick Start Guide

**Created:** 2025-12-02
**Status:** Ready for Deployment

## What Was Added

This update adds version-controlled, automated Elasticsearch monitoring to the DevOps repository. The system monitors Elasticsearch health every 5 minutes and automatically restarts it if unhealthy.

## Files Created

### 1. Monitoring Script
**Location:** `/DevOps/scripts/monitor-elasticsearch.sh`
- Main monitoring script with health checks and auto-restart logic
- Retry logic: 3 attempts with 5-second delays
- Automatic restart via docker-compose on failure
- Comprehensive timestamped logging
- Integration with existing DevOps utilities

### 2. Cron Configuration
**Location:** `/DevOps/config/cron.d/elasticsearch-monitoring`
- Cron job configuration (runs every 5 minutes)
- Environment variable configuration
- Deployment instructions in comments
- Alternative schedules provided

### 3. Logrotate Configuration
**Location:** `/DevOps/config/logrotate.d/elasticsearch-monitoring`
- Log rotation configuration (30-day retention for monitoring logs)
- Compression enabled
- Separate rotation for cron logs (weekly, 8-week retention)

### 4. Deployment Script
**Location:** `/DevOps/scripts/deploy-elasticsearch-monitoring.sh`
- Automated deployment to production server
- Verification and testing built-in
- Can run from local machine or on server

### 5. Documentation
**Location:** `/DevOps/docs/ELASTICSEARCH_MONITORING.md`
- Complete documentation (40+ pages)
- Installation instructions
- Configuration guide
- Troubleshooting section
- Integration with existing systems

## Directory Structure

```
DevOps/
├── config/
│   ├── cron.d/
│   │   └── elasticsearch-monitoring          # Cron configuration
│   └── logrotate.d/
│       └── elasticsearch-monitoring          # Log rotation config
├── docs/
│   └── ELASTICSEARCH_MONITORING.md           # Full documentation
├── scripts/
│   ├── deploy-elasticsearch-monitoring.sh    # Deployment script
│   └── monitor-elasticsearch.sh              # Main monitoring script
└── ELASTICSEARCH_MONITORING_SUMMARY.md       # This file
```

## Quick Deployment

### From Local Machine (Recommended)

```bash
cd /Users/andrzej/Development/CheaperForDrug/DevOps
./scripts/deploy-elasticsearch-monitoring.sh
```

This will:
1. Copy all files to the production server
2. Install cron and logrotate configurations
3. Create log directories
4. Run a test execution
5. Display usage instructions

### Manual Deployment (If Needed)

```bash
# 1. Copy files to server
scp -P 2222 DevOps/scripts/monitor-elasticsearch.sh andrzej@65.109.22.232:/home/andrzej/DevOps/scripts/
scp -P 2222 DevOps/config/cron.d/elasticsearch-monitoring andrzej@65.109.22.232:/tmp/
scp -P 2222 DevOps/config/logrotate.d/elasticsearch-monitoring andrzej@65.109.22.232:/tmp/

# 2. SSH to server and install
ssh -p 2222 andrzej@65.109.22.232

# 3. Install configurations
sudo cp /tmp/elasticsearch-monitoring /etc/cron.d/
sudo chmod 644 /etc/cron.d/elasticsearch-monitoring
sudo cp /tmp/elasticsearch-monitoring /etc/logrotate.d/
sudo chmod 644 /etc/logrotate.d/elasticsearch-monitoring

# 4. Make script executable
chmod +x /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# 5. Create log directory
mkdir -p /home/andrzej/logs/elasticsearch-monitoring

# 6. Reload cron
sudo systemctl reload cron

# 7. Test
/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh
```

## Configuration

### Basic Setup

Edit `/etc/cron.d/elasticsearch-monitoring` on the server:

```bash
# Elasticsearch endpoint (required)
ELASTICSEARCH_URL=http://localhost:9200

# Docker-compose configuration (if ES runs in docker-compose)
DOCKER_COMPOSE_DIR=/home/andrzej/apps/elasticsearch
ES_SERVICE_NAME=elasticsearch

# Email alerts (optional)
SEND_ALERTS=true
ALERT_EMAIL=andrzej@webet.pl
```

### If Elasticsearch is AWS/External

If Elasticsearch is hosted on AWS or external service:

```bash
# Set the external URL
ELASTICSEARCH_URL=https://your-cluster.es.amazonaws.com

# Disable docker-compose restart (AWS is managed)
# Leave DOCKER_COMPOSE_DIR empty or remove the line

# Health checks and alerts will still work
SEND_ALERTS=true
ALERT_EMAIL=andrzej@webet.pl
```

### If Elasticsearch Requires Authentication

```bash
# Add credentials to cron file
ELASTICSEARCH_USERNAME=elastic
ELASTICSEARCH_PASSWORD=your-password

# Or better: Use environment file
# Create ~/.elasticsearch-monitor.env
echo "ELASTICSEARCH_USERNAME=elastic" > ~/.elasticsearch-monitor.env
echo "ELASTICSEARCH_PASSWORD=your-password" >> ~/.elasticsearch-monitor.env
chmod 600 ~/.elasticsearch-monitor.env

# Source in cron file
. /home/andrzej/.elasticsearch-monitor.env
```

## Monitoring and Logs

### View Logs

```bash
# Real-time monitoring
tail -f /home/andrzej/logs/elasticsearch-monitoring/monitor.log

# Last 100 lines
tail -100 /home/andrzej/logs/elasticsearch-monitoring/monitor.log

# Cron execution log
tail -f /home/andrzej/logs/elasticsearch-monitoring/cron.log

# Search for errors
grep ERROR /home/andrzej/logs/elasticsearch-monitoring/monitor.log
```

### Manual Testing

```bash
# Run health check manually
/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# Check what cron will run
sudo cat /etc/cron.d/elasticsearch-monitoring

# View system cron logs
sudo tail -f /var/log/syslog | grep CRON
```

## Integration with Existing DevOps Patterns

This monitoring system follows the established patterns in the repository:

### 1. Common Utilities
- Uses `/DevOps/common/utils.sh` for logging functions
- Uses `/DevOps/common/elasticsearch-check.sh` for health checks
- Uses `/DevOps/common/email-notification.sh` for alerts

### 2. Logging Standards
- Same timestamp format: `[YYYY-MM-DD HH:MM:SS]`
- Same log levels: INFO, SUCCESS, WARNING, ERROR
- Same log rotation pattern (daily, 30-day retention)

### 3. Configuration Management
- Follows `/DevOps/config/` directory structure
- Cron files in `config/cron.d/`
- Logrotate files in `config/logrotate.d/`
- Environment variables for configuration

### 4. Email Notifications
- Integrates with SendGrid notification system
- Uses same email templates and formatting
- Follows existing alert patterns

### 5. Deployment Scripts
- Automated deployment script like other DevOps tools
- SSH/SCP deployment from local machine
- Verification and testing built-in

## Example Log Output

### Healthy Check
```
[2025-12-02 14:35:01] [INFO] ======================================================================
[2025-12-02 14:35:01] [INFO] Starting Elasticsearch health check (URL: http://localhost:9200)
[2025-12-02 14:35:01] [INFO] ======================================================================
[2025-12-02 14:35:01] [INFO] Health check attempt 1/3
[2025-12-02 14:35:01] [SUCCESS] Elasticsearch is responding
[2025-12-02 14:35:01] [INFO] Cluster health status: green
[2025-12-02 14:35:01] [SUCCESS] Elasticsearch cluster health is acceptable: green
[2025-12-02 14:35:01] [SUCCESS] Elasticsearch monitoring check completed - service is healthy
```

### Failed Check with Auto-Restart
```
[2025-12-02 14:40:11] [ERROR] Elasticsearch is unhealthy after 3 attempts
[2025-12-02 14:40:11] [WARNING] Attempting to restart Elasticsearch...
[2025-12-02 14:40:11] [INFO] Restarting Elasticsearch via docker-compose
[2025-12-02 14:40:15] [SUCCESS] Docker-compose restart completed
[2025-12-02 14:40:45] [SUCCESS] Elasticsearch is now responding after restart
[2025-12-02 14:40:45] [INFO] Cluster health status: yellow
```

## Verification Checklist

After deployment, verify:

- [ ] Script is executable: `ls -la /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh`
- [ ] Cron job is installed: `sudo cat /etc/cron.d/elasticsearch-monitoring`
- [ ] Logrotate is installed: `sudo cat /etc/logrotate.d/elasticsearch-monitoring`
- [ ] Log directory exists: `ls -la /home/andrzej/logs/elasticsearch-monitoring/`
- [ ] Manual test runs: `/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh`
- [ ] Logs are created: `ls -la /home/andrzej/logs/elasticsearch-monitoring/monitor.log`
- [ ] Cron is loaded: `sudo systemctl status cron`

## Troubleshooting

### Cron Not Running

```bash
# Check cron service
sudo systemctl status cron

# Reload cron
sudo systemctl reload cron

# Check cron logs
sudo tail -f /var/log/syslog | grep CRON
```

### Script Fails

```bash
# Run manually to see errors
/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# Check permissions
ls -la /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh

# Make executable if needed
chmod +x /home/andrzej/DevOps/scripts/monitor-elasticsearch.sh
```

### No Logs Created

```bash
# Create log directory
mkdir -p /home/andrzej/logs/elasticsearch-monitoring

# Check directory permissions
ls -la /home/andrzej/logs/

# Run script manually
/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh
```

## Next Steps

1. **Deploy to Production**
   - Run deployment script or manual installation
   - Verify all components are working

2. **Configure for Your Setup**
   - Set correct ELASTICSEARCH_URL
   - Configure docker-compose path if needed
   - Enable email alerts if desired

3. **Monitor Initial Runs**
   - Watch logs for first few executions
   - Verify health checks are working
   - Test auto-restart if possible (in non-production first)

4. **Schedule Review**
   - Adjust check frequency if needed (default: 5 minutes)
   - Review log retention settings
   - Configure email alerts

5. **Documentation**
   - Read full documentation: `/DevOps/docs/ELASTICSEARCH_MONITORING.md`
   - Update main README if needed
   - Document any custom configuration

## Support

For detailed information, see:
- **Full Documentation:** `/DevOps/docs/ELASTICSEARCH_MONITORING.md`
- **Main DevOps README:** `/DevOps/README.md`
- **Existing Patterns:** Other scripts in `/DevOps/scripts/`

For issues:
- Check logs: `/home/andrzej/logs/elasticsearch-monitoring/monitor.log`
- Review configuration: `/etc/cron.d/elasticsearch-monitoring`
- Test manually: `/home/andrzej/DevOps/scripts/monitor-elasticsearch.sh`

---

**Version:** 1.0.0
**Last Updated:** 2025-12-02
**Maintained By:** DevOps Team
