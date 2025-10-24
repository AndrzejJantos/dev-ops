# One-Command Server Setup

## 🎯 Super Simple Setup

Get from **fresh server** to **running application** in one command!

## 🚀 The One Command

```bash
git clone https://github.com/YOUR_USERNAME/DevOps.git /home/andrzej/DevOps
cd /home/andrzej/DevOps
sudo bash setup-server.sh
```

That's it! ✅

## 📋 What This Does

### Step 1: Server Initialization (10-15 min)
Automatically installs:
- ✅ Docker
- ✅ PostgreSQL 14
- ✅ Redis 6
- ✅ Nginx
- ✅ Ruby 3.3.4
- ✅ Node.js 20
- ✅ UFW Firewall
- ✅ Creates `andrzej` user

### Step 2: Application Setup (5-10 min per app)
For each application:
- ✅ Clones repository
- ✅ Creates PostgreSQL database
- ✅ Installs gems natively (`bundle install`)
- ✅ Runs database migrations
- ✅ Builds Docker image
- ✅ Configures Nginx

### Step 3: Environment Configuration (Interactive)
Prompts you to edit:
- `.env.production` files
- API keys and credentials

### Step 4: Deployment (3-5 min per app)
- ✅ Starts 2 Docker containers
- ✅ Configures Nginx load balancer
- ✅ Verifies health checks
- ✅ Sends email notification

## 🎬 Interactive Prompts

The script will ask:

### 1. Which applications to setup?
```
Which applications do you want to setup?
Options:
  1) All applications
  2) Select specific applications
  3) Skip application setup (only server initialization)

Enter choice [1-3]:
```

### 2. Edit environment files?
```
Do you want to edit environment files now? [y/N]:
```

### 3. Deploy now?
```
Do you want to deploy applications now? [Y/n]:
```

## 📊 Example Run

```bash
root@server:~# git clone https://github.com/user/DevOps.git /home/andrzej/DevOps
root@server:~# cd /home/andrzej/DevOps
root@server:/home/andrzej/DevOps# sudo bash setup-server.sh

========================================
  STEP 1/4: Server Initialization
========================================

[INFO] Running ubuntu-init-setup.sh...
[INFO] This will install: Docker, PostgreSQL, Redis, Nginx, Ruby, Node.js
[INFO] Time estimate: 10-15 minutes

[SUCCESS] Docker installed
[SUCCESS] PostgreSQL installed
[SUCCESS] Redis installed
[SUCCESS] Nginx installed
[SUCCESS] Ruby 3.3.4 installed
[SUCCESS] Server initialization completed!

========================================
  STEP 2/4: Application Setup
========================================

[INFO] Scanning for applications...
[SUCCESS] Found 1 application(s) to setup:
  - cheaperfordrug-landing

Which applications do you want to setup?
Options:
  1) All applications
  2) Select specific applications
  3) Skip application setup (only server initialization)

Enter choice [1-3]: 1

========================================
  Setting up: cheaperfordrug-landing
========================================

[INFO] Running: /home/andrzej/DevOps/apps/cheaperfordrug-landing/setup.sh
[INFO] This will:
  - Clone repository
  - Create database
  - Install gems
  - Run migrations
  - Build Docker image
  - Configure Nginx

[INFO] Cloning repository...
[SUCCESS] Repository cloned
[INFO] Creating database: cheaperfordrug_landing_production
[SUCCESS] Database created
[INFO] Installing gems...
[SUCCESS] Gems installed
[INFO] Running migrations...
[SUCCESS] Migrations completed
[INFO] Building Docker image...
[SUCCESS] Docker image built
[INFO] Configuring Nginx...
[SUCCESS] Nginx configured
[SUCCESS] Application cheaperfordrug-landing setup completed!

========================================
  STEP 3/4: Environment Configuration
========================================

[WARNING] IMPORTANT: You need to configure environment variables!

Application: cheaperfordrug-landing
Environment file: /home/andrzej/apps/cheaperfordrug-landing/.env.production

[INFO] Edit this file and update:
  - STRIPE_PUBLISHABLE_KEY
  - STRIPE_SECRET_KEY
  - GOOGLE_ANALYTICS_ID
  - GOOGLE_TAG_MANAGER_ID
  - FACEBOOK_PIXEL_ID
  - ROLLBAR_ACCESS_TOKEN

Do you want to edit environment files now? [y/N]: y

[INFO] Opening /home/andrzej/apps/cheaperfordrug-landing/.env.production...
(nano opens for editing)

========================================
  STEP 4/4: Application Deployment
========================================

Do you want to deploy applications now? [Y/n]: y

[INFO] Deploying: cheaperfordrug-landing
[INFO] Starting deployment with scale=2
[SUCCESS] Docker image built
[SUCCESS] Container cheaperfordrug-landing_web_1 is healthy
[SUCCESS] Container cheaperfordrug-landing_web_2 is healthy
[SUCCESS] Application cheaperfordrug-landing deployed successfully!

========================================
  🎉 SETUP COMPLETE!
========================================

✅ Server initialized
   - Docker installed
   - PostgreSQL installed
   - Redis installed
   - Nginx installed
   - Ruby 3.3.4 installed
   - Node.js 20 installed

✅ Applications setup: 1
   - cheaperfordrug-landing

========================================
  Next Steps
========================================

1. Reconnect to server using:
   ssh -p 2222 andrzej@<server-ip>

2. Verify applications are running:
   docker ps | grep cheaperfordrug-landing

3. Configure DNS for your domains

4. Enable SSL/HTTPS:
   sudo certbot --nginx -d presale.taniejpolek.pl

5. Access Rails console:
   cd /home/andrzej/DevOps
   ./scripts/console.sh cheaperfordrug-landing

6. Deploy updates:
   cd /home/andrzej/DevOps/apps/cheaperfordrug-landing
   ./deploy.sh deploy

========================================
  Server Information
========================================

Deploy User: andrzej
DevOps Location: /home/andrzej/DevOps
Apps Location: /home/andrzej/apps

Running Containers:
cheaperfordrug-landing_web_1   Up 1 minute   0.0.0.0:3010->80/tcp
cheaperfordrug-landing_web_2   Up 1 minute   0.0.0.0:3011->80/tcp

Services Status:
  ✅ docker - running
  ✅ postgresql - running
  ✅ redis-server - running
  ✅ nginx - running

[SUCCESS] Setup completed successfully! 🚀
```

## ⏱️ Time Breakdown

| Step | Time | What Happens |
|------|------|--------------|
| Server Init | 10-15 min | Install all prerequisites |
| App Setup | 5-10 min | Clone, install, build per app |
| Edit Env | 2-5 min | Configure API keys |
| Deploy | 3-5 min | Start containers per app |
| **Total** | **20-35 min** | Fully automated |

## 🎯 What You Get

After running this one command:

```
✅ Server fully configured
✅ Application code cloned to: /home/andrzej/apps/<app-name>/repo/
✅ Gems installed natively
✅ Database created and migrated
✅ Docker containers running (2 instances)
✅ Nginx load balancing traffic
✅ SSL ready (just run certbot)
✅ Rails console ready: cd ~/apps/<app>/repo && bundle exec rails c
✅ Email notifications configured
```

## 🔧 Features

### Smart Detection
- Automatically finds all apps in `apps/` directory
- Skips `_examples` folder
- Only shows apps with `setup.sh` script

### Interactive
- Prompts for which apps to setup
- Asks before editing env files
- Confirms before deployment

### Safe
- Stops on errors
- Shows clear error messages
- Can run partially (e.g., just server init)

### Resumable
- Can skip steps if already done
- Re-running is safe (idempotent)

## 📁 Result

After completion, your server has:

```
/home/andrzej/
├── DevOps/                           # Git repository
│   ├── apps/
│   │   └── cheaperfordrug-landing/
│   │       ├── setup.sh
│   │       ├── deploy.sh
│   │       └── config.sh
│   └── setup-server.sh              # This master script
│
└── apps/                             # Deployed applications
    └── cheaperfordrug-landing/
        ├── repo/                     # Full Rails app
        │   ├── app/
        │   ├── vendor/bundle/       # Installed gems
        │   └── .env.production      # Symlink
        ├── .env.production          # Environment variables
        ├── backups/                  # Database backups
        └── logs/                     # Deployment logs
```

**Docker containers:**
- `cheaperfordrug-landing_web_1` on port 3010
- `cheaperfordrug-landing_web_2` on port 3011

**Nginx:**
- Configured and running
- Load balancing between containers
- Serving on port 80

## 🆘 If Something Goes Wrong

The script is safe to re-run:

```bash
sudo bash setup-server.sh
```

It will:
- Skip already completed steps
- Show what's already done
- Continue from where it stopped

## 🎓 Advanced Options

### Setup Only (No Deploy)
When prompted:
```
Do you want to deploy applications now? [Y/n]: n
```

Then deploy manually later:
```bash
su - andrzej
cd ~/DevOps/apps/cheaperfordrug-landing
./deploy.sh deploy
```

### Server Init Only
When prompted:
```
Which applications do you want to setup?
Options:
  1) All applications
  2) Select specific applications
  3) Skip application setup (only server initialization)

Enter choice [1-3]: 3
```

This only sets up the server, no apps.

### Specific Apps Only
When prompted:
```
Which applications do you want to setup?
Options:
  1) All applications
  2) Select specific applications
  3) Skip application setup (only server initialization)

Enter choice [1-3]: 2

Available applications:
  1) cheaperfordrug-landing
  2) another-app
  3) third-app

Enter application numbers (space-separated, e.g., 1 3): 1
```

## ✅ Verification

After setup completes:

```bash
# Check services
sudo systemctl status docker postgresql redis-server nginx

# Check containers
docker ps

# Check application
curl http://localhost:3010/up
curl http://localhost:3011/up

# Check through Nginx
curl -H "Host: presale.taniejpolek.pl" http://localhost/up

# Access Rails console
cd ~/apps/cheaperfordrug-landing/repo
RAILS_ENV=production bundle exec rails console
```

## 🎉 That's It!

One command. Everything automated. Production ready.

```bash
sudo bash setup-server.sh
```

**Questions?** See [SERVER_SETUP_GUIDE.md](SERVER_SETUP_GUIDE.md) for detailed manual setup.

---

**Total Time:** 20-35 minutes
**Commands to Run:** 3 (git clone, cd, sudo bash)
**Manual Steps:** Minimal (edit env, confirm prompts)
