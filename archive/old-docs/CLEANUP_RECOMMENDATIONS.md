# Cleanup Recommendations

This document lists files that can be removed or consolidated after the v3.0 refactoring.

## Files to Remove

### Redundant App-Specific Scripts

These scripts had duplicated logic now centralized in `common/`:

```bash
# Next.js app - can be replaced with new thin wrappers
apps/cheaperfordrug-web/setup.sh.old
apps/cheaperfordrug-web/deploy.sh.old
apps/cheaperfordrug-web/diagnose.sh
apps/cheaperfordrug-web/quick-check.sh
apps/cheaperfordrug-web/fix-domain-and-ssl.sh

# Rails API - same
apps/cheaperfordrug-api/setup.sh.old
apps/cheaperfordrug-api/deploy.sh.old

# Landing page - same
apps/cheaperfordrug-landing/setup.sh.old
apps/cheaperfordrug-landing/deploy.sh.old
apps/cheaperfordrug-landing/restore.sh  # Can use generic version
```

### Old Common Scripts

These are now replaced by app-type modules:

```bash
# Old Node.js scripts (replaced by common/app-types/nextjs.sh)
common/nodejs/setup.sh
common/nodejs/deploy.sh

# Old Rails scripts (replaced by common/app-types/rails.sh + setup-helpers.sh content)
common/rails/setup.sh
common/rails/setup-helpers.sh
common/rails/deploy.sh
```

## Files to Keep (Critical)

### Core Infrastructure
- `common/utils.sh` - Core utilities (database, logging, etc.)
- `common/docker-utils.sh` - Docker operations
- `common/app-types/nextjs.sh` - Next.js app type
- `common/app-types/rails.sh` - Rails app type
- `common/setup-app.sh` - Generic setup orchestrator
- `common/deploy-app.sh` - Generic deploy orchestrator

### Templates
- `common/nextjs/Dockerfile.template` - Next.js Dockerfile
- `common/nextjs/.dockerignore.template` - Next.js ignore file
- `common/rails/Dockerfile.template` - Rails Dockerfile
- `common/rails/.dockerignore.template` - Rails ignore file
- `common/nginx/default-server.conf` - Security catch-all

### App Templates
- `templates/nextjs-app/*` - Complete Next.js template
- `templates/rails-app/*` - Complete Rails template

### Scripts
- `scripts/cleanup-all-apps.sh` - Centralized cleanup
- `scripts/disaster-recovery.sh` - Full server rebuild
- `scripts/disaster-recovery-config.example.sh` - DR config example
- `scripts/console.sh` - Rails console helper
- `scripts/rails-task.sh` - Rails task helper
- `scripts/setup-ssl.sh` - SSL setup helper

### Documentation
- `README.md` - Main documentation
- `MIGRATION_GUIDE.md` - Migration guide
- `CLEANUP_RECOMMENDATIONS.md` - This file

## Cleanup Commands

### Safe Cleanup (Recommended)

Move old files to archive instead of deleting:

```bash
cd ~/DevOps

# Create archive directory
mkdir -p .archive/v2

# Move old common scripts
mv common/nodejs .archive/v2/
mv common/rails/setup.sh .archive/v2/rails-setup.sh
mv common/rails/setup-helpers.sh .archive/v2/rails-setup-helpers.sh
mv common/rails/deploy.sh .archive/v2/rails-deploy.sh

# Keep only Dockerfile templates in common/rails/
# (Dockerfile.template and .dockerignore.template stay)

# Archive old app scripts (after migration)
find apps/ -name "*.old" -exec mv {} .archive/v2/ \;
find apps/ -name "diagnose.sh" -exec mv {} .archive/v2/ \;
find apps/ -name "quick-check.sh" -exec mv {} .archive/v2/ \;
find apps/ -name "fix-domain-and-ssl.sh" -exec mv {} .archive/v2/ \;
```

### Aggressive Cleanup (After Verification)

Only run after thoroughly testing the new system:

```bash
cd ~/DevOps

# Remove old common scripts
rm -rf common/nodejs/
rm -f common/rails/setup.sh
rm -f common/rails/setup-helpers.sh
rm -f common/rails/deploy.sh

# Remove old app scripts
find apps/ -name "*.old" -delete
find apps/ -name "diagnose.sh" -delete
find apps/ -name "quick-check.sh" -delete
find apps/ -name "fix-domain-and-ssl.sh" -delete

# Remove archive if confident
rm -rf .archive/
```

## Migration Verification

Before cleanup, verify these work:

### For Each App
```bash
cd ~/DevOps/apps/your-app

# Test all operations
./deploy.sh deploy          # Deploy works
./deploy.sh scale 3         # Scaling works
./deploy.sh restart         # Restart works
./deploy.sh status          # Status works
./deploy.sh logs            # Logs work
./deploy.sh stop            # Stop works

# For Rails apps
./deploy.sh console         # Console works

# Test health
curl https://your-domain.com
```

### System-Wide
```bash
# Centralized cleanup works
~/DevOps/scripts/cleanup-all-apps.sh

# SSL renewal works
sudo certbot renew --dry-run

# Disaster recovery config valid
~/DevOps/scripts/disaster-recovery.sh --help
```

## What Each Cleanup Gains

### Removing common/nodejs/
- **Lines saved**: ~500 lines
- **Complexity reduced**: Consolidated into 300-line app-type module
- **Maintenance**: One place instead of duplicated logic

### Removing old common/rails/
- **Lines saved**: ~700 lines
- **Complexity reduced**: Consolidated into 600-line app-type module
- **Maintenance**: One place instead of duplicated logic

### Removing per-app diagnostic scripts
- **Lines saved**: ~450 lines per app × 3 apps = 1,350 lines
- **Complexity reduced**: Functionality moved to core
- **Maintenance**: No per-app variations

### Total Savings
- **Lines of code removed**: ~2,550 lines
- **Files removed**: ~15 files
- **Maintenance points**: Reduced from 20+ to 8 core files

## Gradual Cleanup Plan

**Week 1**: Move to archive
```bash
mkdir -p .archive/v2
mv old-files .archive/v2/
```

**Week 2**: Test in production
- Monitor all deployments
- Verify no issues
- Check all apps work correctly

**Week 3**: Permanent removal
```bash
rm -rf .archive/
git commit -m "Clean up v2.x code after successful v3.0 migration"
```

## Rollback Strategy

If issues arise after cleanup:

1. **From Archive**:
   ```bash
   cp .archive/v2/old-file ./restored-location/
   ```

2. **From Git**:
   ```bash
   git checkout v2-backup -- path/to/old-file
   ```

3. **Full Rollback**:
   ```bash
   git checkout v2-backup
   ```

## Post-Cleanup Checklist

After cleanup, verify:

- [ ] All apps still deploy successfully
- [ ] No broken symlinks or references
- [ ] Git repository is clean: `git status`
- [ ] Documentation is updated
- [ ] Team is notified of changes
- [ ] Backup exists before permanent deletion

## Notes

- **Don't rush cleanup**: Keep archive for at least 2 weeks
- **Test thoroughly**: One bad deployment could affect multiple apps
- **Document changes**: Update team on new structure
- **Keep backups**: Archive files before deletion
- **Monitor logs**: Watch for any references to old files

## Questions?

If unsure about removing a file:
1. Check if it's referenced anywhere: `grep -r "filename" .`
2. Check git history: `git log --all --full-history -- path/to/file`
3. Keep it in archive for safety
4. Document why it was kept
