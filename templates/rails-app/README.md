# Rails App Template

This template provides a complete setup for deploying a Rails API application with Sidekiq workers and Clockwork scheduler using the DevOps infrastructure.

## Quick Start

### 1. Copy Template
```bash
cd ~/DevOps/apps
cp -r ../templates/rails-app your-app-name
cd your-app-name
```

### 2. Configure Your App
Edit `config.sh`:
```bash
nano config.sh
```

Update these required fields:
- `APP_NAME` - Your app identifier (lowercase, hyphens)
- `APP_DISPLAY_NAME` - Human-readable name
- `DOMAIN` - Your domain name
- `REPO_URL` - Your Git repository URL
- `BASE_PORT` - Starting port (e.g., 3020, 3040, 3050)
- `REDIS_DB_NUMBER` - Dedicated Redis database (0-15, choose unique)

Optional but recommended:
- `DEFAULT_SCALE` - Number of web containers (default: 2)
- `WORKER_COUNT` - Number of Sidekiq workers (default: 1)
- `SCHEDULER_ENABLED` - Enable Clockwork scheduler (default: true)

### 3. Run Setup
```bash
chmod +x setup.sh deploy.sh
bash setup.sh
```

This will:
- Create directory structure
- Clone your repository
- Setup PostgreSQL database with dedicated user
- Create production environment file
- Setup nginx configuration
- Configure SSL certificates (if DNS is ready)
- Setup automated cleanup and backups

### 4. Configure Environment
```bash
nano ~/apps/your-app-name/.env.production
```

The setup script generates most values automatically, but you should update:
- **ALLOWED_ORIGINS** - Frontend domains allowed to access your API (comma-separated)
- Mailgun credentials (for application emails)
- Any API keys your app needs
- Custom environment variables

Example:
```bash
# Update CORS allowed origins with your actual frontend domain(s)
ALLOWED_ORIGINS=https://your-frontend.com,https://www.your-frontend.com
```

**Note:** `PORT=3000` is automatically set by the setup script to ensure Puma listens on the correct port.

### 5. Deploy
```bash
./deploy.sh deploy
```

This will:
- Pull latest code
- Build Docker image
- Run database migrations (with backup)
- Deploy web containers with zero downtime
- Start worker containers
- Start scheduler container

## Management

### Deploy Latest Code
```bash
./deploy.sh deploy
```

### Scale Web Containers
```bash
./deploy.sh scale 5  # Scale to 5 web containers
```

### Check Status
```bash
./deploy.sh status
```

### View Logs
```bash
./deploy.sh logs              # View logs for web_1
./deploy.sh logs worker_1     # View logs for worker_1
./deploy.sh logs scheduler    # View logs for scheduler
```

### Rails Console
```bash
./deploy.sh console
# Or use the helper script
~/DevOps/scripts/console.sh your-app-name
```

### Run Rails Tasks
```bash
~/DevOps/scripts/rails-task.sh your-app-name db:seed
~/DevOps/scripts/rails-task.sh your-app-name db:migrate:status
```

### Restart
```bash
./deploy.sh restart
```

### Stop
```bash
./deploy.sh stop
```

### Setup SSL
```bash
./deploy.sh ssl-setup
```

## Database Management

### Backup Database
Backups are automatic (every 30 minutes), but you can trigger manually:
```bash
~/apps/your-app-name/backup.sh
```

### Restore Database
```bash
~/apps/your-app-name/restore.sh
# Follow prompts to select backup file
```

### List Backups
```bash
ls -lh ~/apps/your-app-name/backups/
```

## Background Jobs

### Sidekiq Workers
- Workers process background jobs (emails, API calls, data processing)
- Scale workers by updating `WORKER_COUNT` in `config.sh` and redeploying
- Monitor: `./deploy.sh logs worker_1`

### Clockwork Scheduler
- Schedules recurring tasks (cleanup, reports, notifications)
- Configure in your Rails app: `config/clock.rb`
- Monitor: `./deploy.sh logs scheduler`

## Customization

### Custom Nginx Configuration
Edit `nginx.conf.template` to customize:
- CORS headers
- Proxy settings
- Timeouts
- Upload limits
- Security headers

### Custom Ports
If port 3020 is taken, update `BASE_PORT` in `config.sh`:
- 3010-3012: Used by cheaperfordrug-landing
- 3020-3022: Used by cheaperfordrug-api
- 3030-3032: Used by cheaperfordrug-web
- Choose a free range (e.g., 3040-3049)

### Multiple Domains
To serve the same app on multiple domains, update nginx.conf.template:
```nginx
server_name domain1.com domain2.com;
```

### Worker and Scheduler Commands
To customize commands, update the app-type module or create hooks in your deployment script.

## Troubleshooting

### Container Won't Start
```bash
docker logs your-app-name_web_1
```

### Database Connection Errors
```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Check database exists
sudo -u postgres psql -l | grep your_app_name

# Test connection
cd ~/apps/your-app-name/repo
RAILS_ENV=production bundle exec rails db:migrate:status
```

### Migration Fails
```bash
# Check migration logs
./deploy.sh logs web_1

# Run migrations manually
docker exec -it your-app-name_web_1 rails db:migrate
```

### Worker Not Processing Jobs
```bash
# Check worker logs
./deploy.sh logs worker_1

# Check Redis connection
redis-cli -n YOUR_REDIS_DB_NUMBER ping
```

### Port Already in Use
```bash
# Check what's using the port
sudo lsof -i :3020

# Update BASE_PORT in config.sh
```

## Files Structure

```
your-app-name/
├── config.sh              # Application configuration
├── setup.sh               # Initial setup script
├── deploy.sh              # Deployment script
├── nginx.conf.template    # Nginx configuration template
└── README.md              # This file
```

## Deployed Structure

After setup, you'll have:

```
~/apps/your-app-name/
├── repo/                  # Git repository
├── logs/                  # Application logs
├── backups/               # Database backups
├── docker-images/         # Docker image backups
├── .env.production        # Environment variables
├── cleanup.sh             # Automated cleanup script
├── backup.sh              # Database backup script
├── restore.sh             # Database restore script
└── deployment-info.txt    # Deployment information
```

## Next Steps

1. Verify deployment: `curl https://your-domain.com/up`
2. Open Rails console: `./deploy.sh console`
3. Run seeds (if needed): `~/DevOps/scripts/rails-task.sh your-app-name db:seed`
4. Monitor logs: `./deploy.sh logs`
5. Setup monitoring (optional)
6. Configure alert notifications (optional)
