# CheaperForDrug Landing Page - DevOps Configuration

This directory contains deployment and configuration files for the CheaperForDrug landing page application.

## Overview

- **Application Type**: Rails 8 Landing Page
- **Domain**: [taniejpolek.pl](https://taniejpolek.pl)
- **Additional Domain**: presale.taniejpolek.pl (presale subdomain)
- **Server**: Hetzner (65.109.22.232:2222)
- **User**: andrzej
- **Port Range**: 3010-3019 (supports up to 10 instances)
- **Container Port**: 3000

## Architecture

### Container Setup
- **Web Containers**: 2 instances (default)
- **Worker Containers**: 0 (disabled for landing page)
- **Scheduler**: Disabled (no background jobs needed)

### Email Configuration
- **Provider**: SendGrid API (not SMTP)
- **From Address**: noreply@taniejpolek.pl
- **Notifications To**: andrzej@webet.pl

## Files

- **config.sh** - Main configuration file (sourced by other scripts)
- **deploy.sh** - Deployment wrapper script (uses common infrastructure)
- **setup.sh** - Initial server setup script
- **nginx.conf.template** - Nginx reverse proxy configuration
- **.env.production.template** - Environment variables template

## Quick Deployment

### Prerequisites
1. Server access configured in SSH config:
   ```
   Host hetzner-andrzej
       HostName 65.109.22.232
       Port 2222
       User andrzej
       IdentityFile ~/.ssh/hetzner_ed25519
   ```

2. Environment file on server:
   ```
   ~/apps/cheaperfordrug-landing/.env.production
   ```

### Deploy from Landing Repository

The landing repository includes a simplified deployment script at `bin/deploy-production.sh`:

```bash
# From landing repository root
rsync -avz --exclude='node_modules' --exclude='.git' \
  -e "ssh -p 2222 -i ~/.ssh/hetzner_ed25519" \
  . andrzej@65.109.22.232:~/cheaperfordrug-landing-deploy/

ssh hetzner-andrzej "cd ~/cheaperfordrug-landing-deploy && ./bin/deploy-production.sh"
```

This script:
1. Builds Docker image with timestamp tag
2. Stops old container gracefully
3. Starts new container with `--env-file .env.production`
4. Shows deployment status and logs

### Deploy Using DevOps Infrastructure

Alternatively, use the standardized DevOps deployment:

```bash
# From DevOps repository root
./apps/cheaperfordrug-landing/deploy.sh
```

## Environment Variables

All environment variables are configured in `.env.production` on the server.

### Required Variables

#### Rails Configuration
- `RAILS_ENV=production`
- `SECRET_KEY_BASE` - Generate with: `rails secret`
- `RAILS_MASTER_KEY` - From: `config/master.key`

#### Database
- `DATABASE_URL` - PostgreSQL connection string
- `DB_POOL=5`

#### Redis
- `REDIS_URL=redis://localhost:6379/1`

#### Email (SendGrid API)
- `SENDGRID_API_KEY` - Get from: https://app.sendgrid.com/settings/api_keys
- `SENDGRID_FROM_EMAIL=noreply@taniejpolek.pl` - Must be verified in SendGrid
- `NOTIFICATION_EMAIL=andrzej@webet.pl`

#### Payment (Stripe)
- `STRIPE_PUBLISHABLE_KEY=pk_live_...`
- `STRIPE_SECRET_KEY=sk_live_...`

#### Analytics
- `GOOGLE_ANALYTICS_ID=G-...`
- `GOOGLE_TAG_MANAGER_ID=GTM-...`
- `FACEBOOK_PIXEL_ID=...`

#### Admin Access
- `ADMIN_EMAIL=admin@taniejpolek.pl`
- `ADMIN_PASSWORD` - Change from default!

See `.env.production.template` for complete list and documentation.

## Email Configuration Details

### SendGrid Setup

The application uses **SendGrid API** (not SMTP) for better deliverability and error handling.

1. **Custom Delivery Method**: `lib/sendgrid_api_delivery.rb`
2. **Configuration**: `config/environments/production.rb` (lines 64-71)
3. **Default From Address**: `config/initializers/sendgrid.rb`

### Testing Email

From server:
```bash
docker exec cheaperfordrug-landing_web_1 /bin/bash -c '
  rails runner "
    ContactMailer.test_email(
      to: \"andrzej@webet.pl\",
      subject: \"Test from taniejpolek.pl\"
    ).deliver_now
  "
'
```

### Verify Configuration

Check environment variables are loaded:
```bash
docker exec cheaperfordrug-landing_web_1 /bin/bash -c '
  echo "SENDGRID_API_KEY: ${SENDGRID_API_KEY:0:20}..." && \
  echo "SENDGRID_FROM_EMAIL: ${SENDGRID_FROM_EMAIL}" && \
  echo "RAILS_ENV: ${RAILS_ENV}"
'
```

## Database Setup

PostgreSQL database configuration:
- Database: `cheaperfordrug_landing_production`
- User: `cheaperfordrug_landing_user`
- Connection: localhost (from Docker host)

## Nginx Configuration

The application sits behind Nginx reverse proxy:
- **Config**: `/etc/nginx/sites-available/cheaperfordrug-landing`
- **Enabled**: `/etc/nginx/sites-enabled/cheaperfordrug-landing`
- **SSL**: Managed by Certbot (Let's Encrypt)
- **Domains**:
  - taniejpolek.pl
  - www.taniejpolek.pl
  - presale.taniejpolek.pl

Upstream backends:
- Port 3010 → cheaperfordrug-landing_web_1
- Port 3011 → cheaperfordrug-landing_web_2 (if scaled)

## Monitoring

### Check Application Status
```bash
ssh hetzner-andrzej
docker ps | grep cheaperfordrug-landing
```

### View Logs
```bash
docker logs cheaperfordrug-landing_web_1 -f
```

### Health Check
```bash
curl https://taniejpolek.pl/up
```

## Troubleshooting

### Container Won't Start
1. Check environment file exists: `ls ~/apps/cheaperfordrug-landing/.env.production`
2. Check logs: `docker logs cheaperfordrug-landing_web_1`
3. Verify database connection
4. Check Redis is running: `redis-cli ping`

### Email Not Sending
1. Verify SendGrid API key is correct
2. Check from address is verified in SendGrid
3. View Rails logs for delivery errors
4. Test with manual delivery command (see above)

### Database Connection Failed
1. Check PostgreSQL is running: `sudo systemctl status postgresql`
2. Verify database exists: `sudo -u postgres psql -l`
3. Check DATABASE_URL in .env.production
4. Ensure Docker can reach host: `docker exec <container> ping host.docker.internal`

## Rollback

If deployment fails:

### Quick Rollback
```bash
# Find previous image
docker images | grep cheaperfordrug-landing

# Run previous version
docker stop cheaperfordrug-landing_web_1
docker run -d --name cheaperfordrug-landing_web_1 \
  --network host \
  --env-file ~/apps/cheaperfordrug-landing/.env.production \
  cheaperfordrug-landing:PREVIOUS_TAG
```

### Database Rollback
```bash
# Restore from backup
cd ~/apps/cheaperfordrug-landing/backups
# List available backups
ls -lh

# Restore specific backup
sudo -u postgres pg_restore -d cheaperfordrug_landing_production backup_file.sql
```

## Security Notes

1. **Never commit .env.production** - Contains sensitive credentials
2. **Use strong passwords** - Change all default values
3. **Rotate keys regularly** - Especially API keys and database passwords
4. **Monitor access logs** - Check for suspicious activity
5. **Keep dependencies updated** - Run `bundle update` regularly
6. **Use HTTPS only** - Force SSL is enabled in production.rb

## Support

For deployment issues or questions:
- Review deployment logs
- Check application logs
- Verify environment configuration
- Contact: andrzej@webet.pl

## References

- [SendGrid API Documentation](https://docs.sendgrid.com/api-reference)
- [Rails Deployment Guide](https://guides.rubyonrails.org/deploying.html)
- [Docker Documentation](https://docs.docker.com/)
- [DevOps Common Scripts](../../common/)
