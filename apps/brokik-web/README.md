# Brokik Web Infrastructure

This directory contains the infrastructure configuration for the Brokik Web frontend application.

## Overview

- **Application Type**: Next.js frontend
- **Domain**: brokik.com, www.brokik.com
- **Container Architecture**: 3 web containers (no workers/schedulers)
- **Ports**: 3050-3052 (host side)
- **Backend API**: api-public.brokik.com, api-internal.brokik.com

## Architecture

The Brokik Web is a Next.js application that serves as the frontend for the Brokik platform:

- **Static Site Generation (SSG)** - Pre-rendered pages for optimal performance
- **Client-Side Rendering (CSR)** - Dynamic content loaded from API
- **API Communication** - All backend calls to Brokik API subdomains
- **No Backend Processing** - Pure frontend, no database or workers needed

## Container Setup

- **Web Containers**: 3 instances (ports 3050, 3051, 3052)
  - Serve Next.js application
  - Load balanced by nginx
  - Standalone mode for optimized Docker images
  - Health check endpoint: `/`

## Files

- **config.sh** - Application configuration (ports, domains, scaling)
- **.env.production.template** - Environment variables template
- **nginx.conf.template** - Nginx configuration with caching rules
- **setup.sh** - Initial application setup script
- **deploy.sh** - Deployment script

## Initial Setup (First Time Only)

1. **SSH into the server**:
   ```bash
   ssh -p 2222 andrzej@your-server-ip
   ```

2. **Clone the DevOps repository** (if not already done):
   ```bash
   cd ~
   git clone git@github.com:YourOrg/DevOps.git
   ```

3. **Run the setup script**:
   ```bash
   cd ~/DevOps/apps/brokik-web
   ./setup.sh
   ```

   The setup script will:
   - Create application directory structure
   - Clone the application repository
   - Copy environment template
   - Prompt you to edit `.env.production` with API URLs and keys
   - Build Docker image (includes Next.js build)
   - Set up nginx configuration with caching rules
   - Obtain SSL certificates via Let's Encrypt
   - Start containers

4. **Edit production environment variables**:
   ```bash
   nano ~/apps/brokik-web/.env.production
   ```

   Update these values:
   - `NEXT_PUBLIC_APP_URL` - Frontend URL (https://brokik.com)
   - `NEXT_PUBLIC_API_PUBLIC_URL` - Public API URL
   - `NEXT_PUBLIC_API_INTERNAL_URL` - Internal API URL
   - `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY` - Google Maps API key
   - `NEXT_PUBLIC_GA_MEASUREMENT_ID` - Google Analytics ID
   - Add any other required API keys

5. **Verify setup**:
   ```bash
   # Check containers are running
   docker ps | grep brokik-web

   # Check application health
   curl https://brokik.com
   curl https://www.brokik.com

   # Check logs
   docker logs brokik-web_web_1
   ```

## Deployment

To deploy updates:

```bash
cd ~/DevOps/apps/brokik-web
./deploy.sh
```

The deployment process:
1. Pulls latest code from GitHub
2. Builds new Docker image (includes Next.js build)
3. Performs zero-downtime rolling restart
4. Validates container health
5. Updates nginx configuration
6. Saves Docker image backup

### Deployment Options

```bash
# Standard deployment
./deploy.sh

# Force rebuild (ignore cache)
./deploy.sh --force-rebuild

# Rollback to previous version
./deploy.sh --rollback
```

## DNS Configuration

Before deployment, ensure these DNS A records point to your server:

- `brokik.com` → Server IP
- `www.brokik.com` → Server IP

## SSL Certificates

SSL certificates are automatically obtained and renewed via Let's Encrypt during:
- Initial setup
- Each deployment (if needed)

Certificates are stored in:
- `/etc/letsencrypt/live/brokik.com/`

The certificate covers both `brokik.com` and `www.brokik.com`.

## Nginx Configuration

The nginx configuration includes optimized caching rules:

- **Static Assets** (`/_next/static/*`): 365 days cache
- **Image Optimization** (`/_next/image/*`): 7 days cache
- **Public Files** (`.jpg`, `.png`, `.css`, `.js`, etc.): 30 days cache
- **HTML Pages**: No cache (dynamic content)

## Monitoring

### Check Application Status

```bash
# Comprehensive status for all apps
~/DevOps/apps/status.sh

# Verify all domains
~/DevOps/verify-domains.sh

# Container logs
docker logs -f brokik-web_web_1
docker logs -f brokik-web_web_2
docker logs -f brokik-web_web_3

# Nginx logs
sudo tail -f /var/log/nginx/brokik-web-access.log
sudo tail -f /var/log/nginx/brokik-web-error.log
```

### Performance Monitoring

```bash
# Check response times
curl -o /dev/null -s -w "Time: %{time_total}s\n" https://brokik.com

# Check cache hit rate
sudo tail -100 /var/log/nginx/brokik-web-access.log | grep "HIT"

# Check container resource usage
docker stats brokik-web_web_1
```

## Troubleshooting

### Containers Not Starting

```bash
# Check container status
docker ps -a | grep brokik-web

# View container logs
docker logs brokik-web_web_1

# Check if port is in use
sudo lsof -i :3050
```

### Build Failures

```bash
# Check build logs
docker logs brokik-web_web_1

# Common issues:
# - Missing environment variables
# - API connection issues during build
# - Out of memory (increase Docker memory limit)
# - npm/yarn dependency issues
```

### SSL Certificate Issues

```bash
# Verify certificate
sudo certbot certificates

# Manually renew
sudo certbot renew

# Test nginx configuration
sudo nginx -t

# Rebuild nginx configs
~/DevOps/rebuild-nginx-configs.sh
```

### Page Not Loading

```bash
# Check if containers are running
docker ps | grep brokik-web

# Check nginx configuration
sudo nginx -t

# Restart nginx
sudo systemctl restart nginx

# Check DNS resolution
dig brokik.com
dig www.brokik.com

# Test direct container access
curl http://localhost:3050
```

### API Connection Issues

The frontend connects to the backend API. If API calls are failing:

1. Check API is running:
   ```bash
   curl https://api-public.brokik.com/up
   curl https://api-internal.brokik.com/up
   ```

2. Verify CORS configuration in API:
   - Check `ALLOWED_ORIGINS` in API `.env.production`
   - Should include `https://brokik.com`

3. Check browser console for CORS errors

4. Verify API URLs in frontend `.env.production`:
   - `NEXT_PUBLIC_API_PUBLIC_URL`
   - `NEXT_PUBLIC_API_INTERNAL_URL`

## Directory Structure

```
~/apps/brokik-web/
├── repo/                    # Git repository
├── .env.production          # Environment variables (never commit!)
├── logs/                    # Application logs
└── docker-images/           # Docker image backups (.tar files)
```

## Environment Variables

See `.env.production.template` for complete list. Key variables:

- **URLs**: `NEXT_PUBLIC_APP_URL`, `NEXT_PUBLIC_API_*_URL`
- **API Keys**: `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY`, `NEXT_PUBLIC_GA_MEASUREMENT_ID`
- **Feature Flags**: `NEXT_PUBLIC_ENABLE_*`
- **Build Config**: `OUTPUT=standalone`, `NEXT_IMAGE_DOMAINS`

## Next.js Configuration

The application uses Next.js standalone output mode for optimal Docker images:

- **Standalone Mode**: Includes only necessary files (smaller images)
- **Image Optimization**: Built-in Next.js image optimization
- **Static Exports**: Pre-rendered pages where possible
- **API Routes**: Proxied through Next.js (if used)

## Performance Optimization

- **Multi-container**: 3 containers for load balancing
- **Nginx Caching**: Aggressive caching for static assets
- **CDN Ready**: Can add CloudFlare or AWS CloudFront in front
- **Image Optimization**: Next.js built-in image optimization
- **Code Splitting**: Automatic code splitting by Next.js

## Related Documentation

- Main DevOps README: `~/DevOps/README.md`
- Nginx configuration: `/etc/nginx/sites-available/brokik-web`
- Common utilities: `~/DevOps/common/`
- Brokik API: `~/DevOps/apps/brokik-api/README.md`
