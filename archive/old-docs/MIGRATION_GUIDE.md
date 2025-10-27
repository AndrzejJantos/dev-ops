# Migration Guide: v2.x to v3.0

This guide helps you migrate from the old structure to the new composition-based architecture.

## What Changed?

### Old Structure (v2.x)
```
apps/your-app/
├── config.sh           # 85 lines
├── setup.sh            # 318 lines - full setup logic
├── deploy.sh           # 510 lines - full deployment logic
├── diagnose.sh         # 200 lines
├── quick-check.sh      # 150 lines
├── fix-domain-and-ssl.sh  # 100 lines
└── nginx.conf.template
```

**Problems:**
- Each app has 1000+ lines of duplicated code
- Bug fixes need to be applied to each app
- Adding features requires updating every app
- Inconsistencies between apps

### New Structure (v3.0)
```
apps/your-app/
├── config.sh           # 30 lines - configuration only
├── setup.sh            # 15 lines - thin wrapper
├── deploy.sh           # 20 lines - thin wrapper
└── nginx.conf.template # Same
```

**Benefits:**
- 95% less code per app
- All logic in `common/` - one place to maintain
- Perfect consistency across all apps
- Adding new apps takes 5 minutes

## Migration Steps

### Step 1: Backup Current Setup
```bash
cd ~/DevOps
git stash  # Save any local changes
git checkout -b backup-v2  # Create backup branch
git checkout master
git pull origin master  # Get v3.0 code
```

### Step 2: Update Each App

For each app in `apps/`:

**A. Update config.sh**
```bash
cd ~/DevOps/apps/your-app
nano config.sh
```

Add at the top (after shebang):
```bash
export APP_TYPE="nextjs"  # or "rails"
```

**B. Create New setup.sh**
```bash
# Backup old version
mv setup.sh setup.sh.old

# Copy template
if [ "$APP_TYPE" = "nextjs" ]; then
    cp ../../templates/nextjs-app/setup.sh ./setup.sh
else
    cp ../../templates/rails-app/setup.sh ./setup.sh
fi

chmod +x setup.sh
```

**C. Create New deploy.sh**
```bash
# Backup old version
mv deploy.sh deploy.sh.old

# Copy template
if [ "$APP_TYPE" = "nextjs" ]; then
    cp ../../templates/nextjs-app/deploy.sh ./deploy.sh
else
    cp ../../templates/rails-app/deploy.sh ./deploy.sh
fi

chmod +x deploy.sh
```

**D. Test Deployment**
```bash
./deploy.sh deploy
```

If successful, deployment should work exactly as before.

### Step 3: Remove Old Diagnostic Scripts

These are no longer needed (functionality moved to core):
```bash
cd ~/DevOps/apps/your-app
rm -f diagnose.sh quick-check.sh fix-domain-and-ssl.sh
```

### Step 4: Update Cron Jobs

Remove per-app cleanup crons:
```bash
crontab -e
```

Remove lines like:
```
0 2 * * * ~/apps/cheaperfordrug-web/cleanup.sh >> ~/apps/cheaperfordrug-web/logs/cleanup.log 2>&1
0 2 * * * ~/apps/cheaperfordrug-api/cleanup.sh >> ~/apps/cheaperfordrug-api/logs/cleanup.log 2>&1
```

Add centralized cleanup:
```
0 2 * * * ~/DevOps/scripts/cleanup-all-apps.sh >> ~/DevOps/logs/cleanup-all.log 2>&1
```

### Step 5: Verify All Apps

```bash
cd ~/DevOps/apps

for app in */; do
    echo "Checking $app..."
    cd "$app"
    if [ -f "deploy.sh" ]; then
        ./deploy.sh status
    fi
    cd ..
done
```

## Rollback Plan

If something goes wrong:

### Quick Rollback
```bash
cd ~/DevOps
git checkout backup-v2  # Switch back to old code

# Restore old app scripts
cd apps/your-app
mv setup.sh.old setup.sh
mv deploy.sh.old deploy.sh
```

### Restore from Backup
```bash
# If you have a full backup
cd ~
rm -rf DevOps
tar -xzf DevOps-backup.tar.gz
```

## Common Migration Issues

### Issue 1: APP_TYPE Not Set
```
Error: APP_TYPE not set in config.sh
```

**Fix:**
```bash
nano config.sh
# Add: export APP_TYPE="nextjs"  # or "rails"
```

### Issue 2: Module Not Found
```
Error: App type module not found: /path/to/common/app-types/nextjs.sh
```

**Fix:**
```bash
cd ~/DevOps
git pull  # Make sure you have latest code
ls -la common/app-types/  # Verify modules exist
```

### Issue 3: Permission Denied
```
Error: Permission denied: ./setup.sh
```

**Fix:**
```bash
chmod +x setup.sh deploy.sh
```

### Issue 4: Container Won't Start
```
Error: Container health check failed
```

**Fix:**
```bash
# Check logs
docker logs your-app_web_1

# Verify env file
cat ~/apps/your-app/.env.production

# Try with old scripts
mv setup.sh.old setup.sh
bash setup.sh
mv setup.sh setup.sh.new
mv setup.sh.old setup.sh
```

## Feature Parity Check

After migration, verify these features still work:

- [ ] Deploy: `./deploy.sh deploy`
- [ ] Scale: `./deploy.sh scale 3`
- [ ] Restart: `./deploy.sh restart`
- [ ] Stop: `./deploy.sh stop`
- [ ] Status: `./deploy.sh status`
- [ ] Logs: `./deploy.sh logs`
- [ ] Console (Rails): `./deploy.sh console`
- [ ] SSL setup: `./deploy.sh ssl-setup`
- [ ] Health checks work
- [ ] Zero-downtime deployment works
- [ ] Nginx load balancing works
- [ ] Database backups work (Rails)
- [ ] Worker containers work (Rails)
- [ ] Scheduler container works (Rails)

## New Features to Try

After migration, you can use these new features:

### Disaster Recovery
```bash
cd ~/DevOps/scripts
cp disaster-recovery-config.example.sh disaster-recovery-config.sh
nano disaster-recovery-config.sh  # Configure
./disaster-recovery.sh  # Test (on a test server!)
```

### Centralized Cleanup
```bash
# View cleanup logs
tail -f ~/DevOps/logs/cleanup-all.log

# Manual cleanup
~/DevOps/scripts/cleanup-all-apps.sh
```

### Quick App Creation
```bash
cd ~/DevOps/apps
cp -r ../templates/nextjs-app my-new-app
cd my-new-app
nano config.sh  # Configure
bash setup.sh   # Setup
./deploy.sh deploy  # Deploy
```

## Performance Impact

Migration should have **zero performance impact**:

- Same Docker images
- Same Nginx configuration
- Same container runtime
- Same networking
- Same health checks
- Same deployment strategy

Only the **management scripts** changed, not the runtime.

## Timeline

Recommended migration timeline:

**Day 1**:
- Backup everything
- Update one non-critical app
- Test thoroughly

**Day 2**:
- If Day 1 went well, update remaining apps
- Update cron jobs
- Test disaster recovery (on test server)

**Day 3**:
- Monitor for issues
- Update documentation
- Clean up old files

## Getting Help

If you encounter issues:

1. Check logs: `docker logs your-app_web_1`
2. Review this guide
3. Check troubleshooting in README.md
4. Use old scripts temporarily: `mv setup.sh.old setup.sh`
5. Restore from backup if needed

## Post-Migration Cleanup

After successful migration:

```bash
# Remove backup scripts
cd ~/DevOps/apps
find . -name "*.old" -delete

# Remove diagnostic scripts (no longer needed)
find . -name "diagnose.sh" -delete
find . -name "quick-check.sh" -delete
find . -name "fix-domain-and-ssl.sh" -delete

# Commit changes
cd ~/DevOps
git add apps/
git commit -m "Migrate all apps to v3.0 composition architecture"
```

## Success Criteria

Migration is successful when:

1. All apps deploy successfully: `./deploy.sh deploy`
2. All containers are healthy: `./deploy.sh status`
3. Applications respond: `curl https://your-domain.com`
4. Zero-downtime deployments work
5. Scaling works: `./deploy.sh scale 3`
6. Centralized cleanup runs nightly
7. No old backup files remain
8. Documentation is updated

## Questions?

If you have questions or issues:
- Review README.md for detailed documentation
- Check template READMEs in `templates/*/`
- Review example apps in `apps/`
- Check logs in `~/DevOps/logs/` and `~/apps/*/logs/`
