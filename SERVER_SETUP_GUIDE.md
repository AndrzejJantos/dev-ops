# Server Setup Guide - Complete Checklist

This guide walks you through setting up your server from scratch and deploying cheaperfordrug-landing.

## 📋 Prerequisites

- Ubuntu 20.04+ server
- Root or sudo access
- Server IP address
- Domain pointed to server: `presale.taniejpolek.pl`

## 🚀 Step-by-Step Setup

### Step 1: Connect to Server

```bash
# From your local machine
ssh root@your-server-ip

# Or if user already exists
ssh andrzej@your-server-ip
```

### Step 2: Initial Server Setup (One-Time)

This installs all prerequisites: Docker, PostgreSQL, Redis, Nginx, Ruby, Node.js, etc.

```bash
# Clone DevOps repository
cd /home/andrzej
git clone https://github.com/YOUR_USERNAME/DevOps.git DevOps

# Run server initialization script
cd DevOps
sudo ./ubuntu-init-setup.sh
```

**This script will:**
- ✅ Create user `andrzej` (if needed)
- ✅ Install Docker
- ✅ Install PostgreSQL 14
- ✅ Install Redis 6
- ✅ Install Nginx
- ✅ Install Ruby 3.3.4 (via rbenv)
- ✅ Install Node.js 20
- ✅ Configure firewall (UFW)
- ✅ Set up SSH security
- ✅ Configure timezone and locale

**Time:** 10-15 minutes

**Expected output:**
```
[SUCCESS] Server initialization completed!
[INFO] Please reconnect using:
  ssh -p 2222 andrzej@your-server-ip
```

### Step 3: Reconnect as Deploy User

After ubuntu-init-setup.sh completes, SSH port changes to 2222:

```bash
# Exit current session
exit

# Reconnect with new SSH port
ssh -p 2222 andrzej@your-server-ip
```

### Step 4: Setup Application

```bash
cd ~/DevOps
./apps/cheaperfordrug-landing/setup.sh
```

**This script will:**
- ✅ Clone application repository
- ✅ Create PostgreSQL database: `cheaperfordrug_landing_production`
- ✅ Configure Redis (database 1)
- ✅ Install gems natively (`bundle install`)
- ✅ Generate `.env.production` file
- ✅ Precompile assets
- ✅ Run database migrations
- ✅ Build Docker image
- ✅ Configure Nginx
- ✅ Send email notification

**Time:** 5-10 minutes

**Expected output:**
```
[SUCCESS] Setup completed successfully!

Next steps:
  1. Edit the environment file and update credentials:
     nano /home/andrzej/apps/cheaperfordrug-landing/.env.production
  2. Deploy the application:
     cd /home/andrzej/DevOps/apps/cheaperfordrug-landing
     ./deploy.sh deploy
```

### Step 5: Configure Environment Variables

```bash
nano /home/andrzej/apps/cheaperfordrug-landing/.env.production
```

**Update these values:**

```bash
# Required for payments (if using Stripe)
STRIPE_PUBLISHABLE_KEY=pk_live_YOUR_ACTUAL_KEY
STRIPE_SECRET_KEY=sk_live_YOUR_ACTUAL_KEY

# Required for analytics (if using)
GOOGLE_ANALYTICS_ID=G-YOUR_ACTUAL_ID
GOOGLE_TAG_MANAGER_ID=GTM-YOUR_ACTUAL_ID

# Optional integrations
FACEBOOK_PIXEL_ID=your_actual_pixel_id
ROLLBAR_ACCESS_TOKEN=your_rollbar_token_here
```

**Already configured (don't change):**
- ✅ DATABASE_URL
- ✅ SECRET_KEY_BASE (auto-generated)
- ✅ REDIS_URL
- ✅ MAILGUN_API_KEY
- ✅ ADMIN_PASSWORD (auto-generated)

**Save and exit:** Ctrl+X, then Y, then Enter

### Step 6: Deploy Application

```bash
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy
```

**This script will:**
- ✅ Pull latest code from GitHub
- ✅ Build Docker image
- ✅ Check for database migrations
- ✅ Start 2 containers (default scale)
- ✅ Wait for health checks
- ✅ Configure Nginx load balancer
- ✅ Send success email notification

**Time:** 3-5 minutes

**Expected output:**
```
[INFO] Starting deployment of CheaperForDrug Landing Page with scale=2
[SUCCESS] Docker image built and tagged successfully
[SUCCESS] Container cheaperfordrug-landing_web_1 is healthy
[SUCCESS] Container cheaperfordrug-landing_web_2 is healthy
[SUCCESS] Deployment completed successfully!
```

### Step 7: Verify Deployment

```bash
# Check containers are running
docker ps | grep cheaperfordrug-landing

# Expected output:
# cheaperfordrug-landing_web_1   Up 2 minutes   0.0.0.0:3010->80/tcp
# cheaperfordrug-landing_web_2   Up 2 minutes   0.0.0.0:3011->80/tcp

# Test health check
curl http://localhost:3010/up
curl http://localhost:3011/up

# Test through Nginx
curl -H "Host: presale.taniejpolek.pl" http://localhost/up
```

**Expected:** All commands return `200 OK`

### Step 8: Configure DNS

1. Go to your DNS provider (e.g., Cloudflare, Namecheap)
2. Add A record:
   - **Name:** `presale` (or `presale.taniejpolek`)
   - **Type:** A
   - **Value:** Your server IP address
   - **TTL:** 300 (or automatic)

3. Wait 5-60 minutes for DNS propagation

4. Test:
   ```bash
   # From your local machine
   curl http://presale.taniejpolek.pl/up
   ```

### Step 9: Enable SSL/HTTPS (Recommended)

```bash
# Install Certbot
sudo apt update
sudo apt install -y certbot python3-certbot-nginx

# Get SSL certificate
sudo certbot --nginx -d presale.taniejpolek.pl

# Test auto-renewal
sudo certbot renew --dry-run
```

**Expected output:**
```
Congratulations! You have successfully enabled HTTPS on https://presale.taniejpolek.pl
```

**Time:** 2-3 minutes

## ✅ Deployment Complete!

Your application is now live at:
- **HTTP:** http://presale.taniejpolek.pl
- **HTTPS:** https://presale.taniejpolek.pl (if SSL configured)

## 🔍 Verification Checklist

```bash
# 1. Check services are running
sudo systemctl status docker
sudo systemctl status postgresql
sudo systemctl status redis-server
sudo systemctl status nginx

# 2. Check containers
docker ps

# 3. Check database
sudo -u postgres psql -l | grep cheaperfordrug_landing_production

# 4. Check Redis
redis-cli ping

# 5. Check Nginx
sudo nginx -t

# 6. Check application logs
docker logs cheaperfordrug-landing_web_1 --tail 50

# 7. Check Rails logs
tail -f ~/apps/cheaperfordrug-landing/repo/log/production.log

# 8. Test application
curl http://presale.taniejpolek.pl
```

## 📊 Post-Deployment

### View Logs

```bash
# Docker container logs
docker logs cheaperfordrug-landing_web_1 -f

# Rails logs (native)
tail -f ~/apps/cheaperfordrug-landing/repo/log/production.log

# Nginx access logs
sudo tail -f /var/log/nginx/cheaperfordrug-landing-access.log

# Nginx error logs
sudo tail -f /var/log/nginx/cheaperfordrug-landing-error.log

# Deployment history
tail -f ~/apps/cheaperfordrug-landing/logs/deployments.log
```

### Access Rails Console

```bash
cd ~/DevOps
./scripts/console.sh cheaperfordrug-landing
```

**In console:**
```ruby
# Check everything is working
User.count
Subscriber.count
Rails.env
ActiveRecord::Base.connection.execute("SELECT 1")
```

### Run Database Migrations

```bash
cd ~/DevOps
./scripts/rails-task.sh cheaperfordrug-landing db:migrate
```

### Scale Application

```bash
cd ~/DevOps/apps/cheaperfordrug-landing

# Scale to 4 instances
./deploy.sh scale 4

# Scale back to 2
./deploy.sh scale 2
```

## 🔄 Deploying Updates

When you push changes to GitHub:

```bash
# SSH to server
ssh -p 2222 andrzej@your-server-ip

# Deploy
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy
```

**That's it!** Zero-downtime deployment happens automatically.

## 🛠️ Troubleshooting

### Issue: Setup script fails

**Check prerequisites:**
```bash
# Check Ruby
ruby -v

# Check Bundler
bundle -v

# Check PostgreSQL
sudo systemctl status postgresql

# Check Redis
sudo systemctl status redis-server

# Check Docker
docker --version
```

**Fix:** Run ubuntu-init-setup.sh again:
```bash
cd ~/DevOps
sudo ./ubuntu-init-setup.sh
```

### Issue: Containers won't start

**Check Docker logs:**
```bash
docker logs cheaperfordrug-landing_web_1
```

**Check environment:**
```bash
cat ~/apps/cheaperfordrug-landing/.env.production | grep DATABASE_URL
```

**Check database connection:**
```bash
sudo -u postgres psql -d cheaperfordrug_landing_production -c "SELECT 1;"
```

### Issue: Can't access website

**Check Nginx:**
```bash
sudo nginx -t
sudo systemctl status nginx
```

**Check if containers are running:**
```bash
docker ps | grep cheaperfordrug-landing
```

**Check ports:**
```bash
sudo netstat -tlnp | grep -E ':(80|3010|3011)'
```

**Reload Nginx:**
```bash
sudo systemctl reload nginx
```

### Issue: Database connection failed

**Check PostgreSQL is running:**
```bash
sudo systemctl status postgresql
sudo systemctl start postgresql
```

**Test connection:**
```bash
sudo -u postgres psql -l
```

**Check DATABASE_URL:**
```bash
grep DATABASE_URL ~/apps/cheaperfordrug-landing/.env.production
```

### Issue: Gems not installing

**Update bundle:**
```bash
cd ~/apps/cheaperfordrug-landing/repo
RAILS_ENV=production bundle install --path vendor/bundle
```

**Fix permissions:**
```bash
sudo chown -R andrzej:andrzej ~/apps/cheaperfordrug-landing
```

## 📧 Email Notifications

You should receive emails at `andrzej@webet.pl` for:
- ✅ Setup completion
- ✅ Deployment success
- ✅ Deployment failure
- ✅ Scaling events

If not receiving emails, check:
```bash
# Test Mailgun API
curl -s --user "api:YOUR_MAILGUN_API_KEY" \
  https://api.mailgun.net/v3/mg.taniejpolek.pl/messages \
  -F from="Test <noreply@mg.taniejpolek.pl>" \
  -F to="andrzej@webet.pl" \
  -F subject="Test Email" \
  -F text="Test message"
```

## 🔐 Security Checklist

After deployment, verify:

- ✅ SSH port changed to 2222
- ✅ Root login disabled
- ✅ Password authentication disabled (SSH keys only)
- ✅ Firewall enabled (UFW)
- ✅ `.env.production` permissions: 600
- ✅ SSL/HTTPS configured
- ✅ Regular backups configured

**Check firewall:**
```bash
sudo ufw status
```

**Expected:**
```
Status: active

To                         Action      From
--                         ------      ----
2222/tcp                   ALLOW       Anywhere
80/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
```

## 📁 Important File Locations

```
/home/andrzej/
├── DevOps/                           # Deployment system
│   ├── apps/cheaperfordrug-landing/
│   │   ├── setup.sh                 # Setup script
│   │   ├── deploy.sh                # Deployment script
│   │   └── config.sh                # Configuration
│   └── scripts/
│       ├── console.sh               # Rails console
│       └── rails-task.sh            # Rails tasks
│
└── apps/
    └── cheaperfordrug-landing/
        ├── repo/                     # Application code
        ├── .env.production          # Environment variables ⚠️
        ├── backups/                 # Database backups
        └── logs/                    # Deployment logs

/etc/nginx/sites-enabled/
└── cheaperfordrug-landing           # Nginx configuration
```

## 🎯 Quick Reference

```bash
# Setup (one-time)
./apps/cheaperfordrug-landing/setup.sh

# Deploy
./apps/cheaperfordrug-landing/deploy.sh deploy

# Scale
./apps/cheaperfordrug-landing/deploy.sh scale 4

# Restart
./apps/cheaperfordrug-landing/deploy.sh restart

# Stop
./apps/cheaperfordrug-landing/deploy.sh stop

# Console
./scripts/console.sh cheaperfordrug-landing

# Run task
./scripts/rails-task.sh cheaperfordrug-landing db:migrate

# View logs
docker logs cheaperfordrug-landing_web_1 -f
tail -f ~/apps/cheaperfordrug-landing/repo/log/production.log
```

## ✅ Final Checklist

Before going live:

- [ ] Server initialized (ubuntu-init-setup.sh)
- [ ] Application setup completed
- [ ] Environment variables configured
- [ ] Application deployed
- [ ] Containers running (docker ps)
- [ ] Health checks passing
- [ ] DNS configured
- [ ] SSL/HTTPS enabled
- [ ] Database migrations run
- [ ] Nginx serving traffic
- [ ] Email notifications working
- [ ] Backups configured
- [ ] Firewall configured

## 🆘 Need Help?

1. **Check logs:**
   - Docker: `docker logs cheaperfordrug-landing_web_1`
   - Rails: `tail -f ~/apps/cheaperfordrug-landing/repo/log/production.log`
   - Nginx: `sudo tail -f /var/log/nginx/cheaperfordrug-landing-error.log`

2. **Check email notifications** for deployment status

3. **Review documentation:**
   - QUICKSTART.md
   - ARCHITECTURE.md
   - TROUBLESHOOTING.md

4. **Contact:** andrzej@webet.pl

---

**Estimated total time:** 30-45 minutes (including DNS propagation)
**Difficulty:** Intermediate
**Prerequisites:** Basic Linux command line knowledge
