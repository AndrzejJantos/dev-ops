# Next.js App Template

This template provides a complete setup for deploying a Next.js application using the DevOps infrastructure.

## Quick Start

### 1. Copy Template
```bash
cd ~/DevOps/apps
cp -r ../templates/nextjs-app your-app-name
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
- `BASE_PORT` - Starting port (e.g., 3030, 3040, 3050)

### 3. Ensure Next.js Standalone Output
Your Next.js app must be configured for standalone output. Edit `next.config.js`:

```javascript
module.exports = {
  output: 'standalone',
  // ... other config
}
```

### 4. Run Setup
```bash
chmod +x setup.sh deploy.sh
bash setup.sh
```

This will:
- Create directory structure
- Clone your repository
- Setup nginx configuration
- Configure SSL certificates (if DNS is ready)
- Setup automated cleanup

### 5. Configure Environment
```bash
nano ~/apps/your-app-name/.env.production
```

Update:
- API URLs
- Google Maps API key (if needed)
- Google Analytics ID (if needed)
- Any custom environment variables

### 6. Deploy
```bash
./deploy.sh deploy
```

## Management

### Deploy Latest Code
```bash
./deploy.sh deploy
```

### Scale Containers
```bash
./deploy.sh scale 5  # Scale to 5 containers
```

### Check Status
```bash
./deploy.sh status
```

### View Logs
```bash
./deploy.sh logs              # View logs for web_1
./deploy.sh logs web_2        # View logs for web_2
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

## Customization

### Custom Nginx Configuration
Edit `nginx.conf.template` to customize:
- Proxy settings
- Caching rules
- Security headers
- Timeouts

### Custom Ports
If port 3030 is taken, update `BASE_PORT` in `config.sh`:
- 3030-3032: Used by cheaperfordrug-web
- 3020-3022: Used by cheaperfordrug-api
- 3010-3012: Used by cheaperfordrug-landing
- Choose a free range (e.g., 3040-3049)

### Multiple Domains
To serve the same app on multiple domains, update nginx.conf.template:
```nginx
server_name domain1.com domain2.com;
```

## Troubleshooting

### Container Won't Start
```bash
docker logs your-app-name_web_1
```

### DNS Not Configured
```bash
# Check DNS
dig +short your-domain.com

# Setup SSL manually after DNS is ready
./deploy.sh ssl-setup
```

### Port Already in Use
```bash
# Check what's using the port
sudo lsof -i :3030

# Update BASE_PORT in config.sh
```

### Next.js Build Fails
Ensure `next.config.js` has `output: 'standalone'`

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
├── docker-images/         # Docker image backups
├── .env.production        # Environment variables
├── cleanup.sh             # Automated cleanup script
└── deployment-info.txt    # Deployment information
```

## Next Steps

1. Verify deployment: `curl https://your-domain.com`
2. Monitor logs: `./deploy.sh logs`
3. Setup monitoring (optional)
4. Configure backups (optional)
