# Rails Dockerfile Usage Guide

## Overview

This Dockerfile template provides a production-ready, multi-stage Docker build for Rails applications that:

1. **Loads environment variables during asset precompilation** - Solves the issue where Rails needs env vars like `MAILGUN_API_KEY` during `rails assets:precompile`
2. **Excludes .env file from final image** - Ensures no secrets are baked into the Docker image
3. **Uses multi-stage builds** - Minimizes final image size and improves security
4. **Runs as non-root user** - Follows Docker security best practices

## Problem Solved

### Issue
Rails applications often need environment variables during asset precompilation because `config/environments/production.rb` or initializers reference them:

```ruby
# config/environments/production.rb
config.action_mailer.default_url_options = {
  host: ENV.fetch('MAILGUN_DOMAIN')
}
```

When running `rails assets:precompile` during Docker build, this causes an error:
```
KeyError: key not found: "MAILGUN_API_KEY"
```

### Traditional Solutions (and their problems)

1. **Using SECRET_KEY_BASE_DUMMY=1 only** - Doesn't work when app uses ENV.fetch()
2. **ARG/ENV in Dockerfile** - Bakes secrets into image layers
3. **Skip asset precompilation** - Requires precompiling on host or at runtime

### Our Solution

Use a multi-stage build that:
- **Stage 1 (Builder)**: Copies .env file, loads all variables, precompiles assets
- **Stage 2 (Production)**: Copies precompiled assets but NOT the .env file
- **Security**: .env file exists only in builder stage, never in final image

## How It Works

### Build Process

1. **Setup script copies .env.production to .env** (before Docker build)
   ```bash
   cp "$ENV_FILE" "${REPO_DIR}/.env"
   ```

2. **Dockerfile Stage 1 (Builder)**
   ```dockerfile
   COPY .env .env
   RUN set -a && . ./.env && set +a && \
       RAILS_ENV=production bundle exec rails assets:precompile
   ```
   - `set -a` - Auto-export all variables
   - `. ./.env` - Source the .env file
   - `set +a` - Disable auto-export
   - Asset precompilation now has access to all env vars

3. **Dockerfile Stage 2 (Production)**
   ```dockerfile
   COPY --from=builder /app ./
   RUN rm -f .env .env.production .env.local .env.*.local
   COPY --from=builder /app/public/assets ./public/assets
   ```
   - Copies app from builder
   - Explicitly removes all .env files
   - Final image is clean and secure

4. **Setup script removes .env after build**
   ```bash
   rm -f "${REPO_DIR}/.env"
   ```

### Runtime

At runtime, environment variables are provided via `docker run --env-file`:
```bash
docker run --env-file=/path/to/.env.production myapp:latest
```

This means:
- **Build time**: .env in builder stage only, loaded via shell sourcing
- **Runtime**: .env.production provided externally, never in image

## Using This Template

### For New Rails Apps

1. Copy Dockerfile.template to your Rails app repository:
   ```bash
   cp /home/andrzej/DevOps/common/rails/Dockerfile.template /path/to/rails-app/Dockerfile
   ```

2. Customize if needed (Ruby version, Node version, etc.)

3. Build normally - the setup script handles .env file creation and cleanup

### Build Requirements

Your Rails app directory must have these files when `docker build` runs:
- `.env` - Created by setup script from `.env.production`
- `Gemfile` and `Gemfile.lock`
- All application code
- `package.json` (optional, if using Node)

### Security Verification

Verify .env is not in final image:
```bash
docker run --rm myapp:latest ls -la / | grep env
docker run --rm myapp:latest cat .env  # Should fail with "No such file"
```

Check image layers don't contain secrets:
```bash
docker history myapp:latest
```

## Environment Variables

### Build-Time Variables (from .env)
These are used during asset precompilation:
- `SECRET_KEY_BASE` - Rails secret (can be dummy for assets only)
- `MAILGUN_API_KEY` - If referenced in initializers
- `MAILGUN_DOMAIN` - If referenced in config
- Any other vars referenced by Rails during initialization

### Runtime Variables (from docker run)
These are provided when container starts:
- `DATABASE_URL` - Database connection
- `REDIS_URL` - Redis connection
- `SECRET_KEY_BASE` - Real production secret
- `RAILS_ENV=production`
- `PORT=80`
- All app-specific environment variables

## Customization

### Different Ruby Version
```dockerfile
FROM ruby:3.2.2-slim AS builder
# ...
FROM ruby:3.2.2-slim
```

### Additional Build Dependencies
```dockerfile
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    nodejs \
    npm \
    imagemagick \
    libvips-dev \
    git \
    curl && \
    rm -rf /var/lib/apt/lists/*
```

### Custom Health Check Endpoint
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:80/api/health || exit 1
```

### Use Specific Node Version
```dockerfile
# In builder stage
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs
```

## Troubleshooting

### Asset Precompilation Fails with "key not found"

**Problem**: Rails initializer or config references ENV var that's not in .env

**Solution**:
1. Check which var is missing: look at error message
2. Add it to .env.production:
   ```bash
   echo "MISSING_VAR=dummy_value" >> ~/.apps/yourapp/.env.production
   ```
3. Rebuild

### .env file not found during build

**Problem**: Setup script didn't copy .env before build

**Solution**: Check setup script workflow:
```bash
# In common/rails/setup.sh, ensure this runs before docker build:
cp "$ENV_FILE" "${REPO_DIR}/.env"
docker build -t "${DOCKER_IMAGE_NAME}:latest" "$REPO_DIR"
rm -f "${REPO_DIR}/.env"
```

### Variables not loading during asset precompilation

**Problem**: Shell not sourcing .env correctly

**Solution**: Check .env file format:
- No spaces around `=`
- Use `export VAR=value` or just `VAR=value`
- No comments on same line as variable
- Quotes for values with spaces: `VAR="value with spaces"`

### Image too large

**Problem**: Build artifacts not cleaned up

**Solution**: Add cleanup in builder stage:
```dockerfile
RUN rm -rf node_modules tmp/cache vendor/bundle/ruby/*/cache .git
```

## Best Practices

1. **Never commit .env files** - Add to .gitignore in app repo
2. **Use strong secrets in production** - Don't use dummy values at runtime
3. **Rotate secrets regularly** - Update .env.production periodically
4. **Test builds locally** - Before deploying to production
5. **Monitor image size** - Use `docker images` to track size
6. **Scan for vulnerabilities** - Use `docker scan myapp:latest`
7. **Keep Ruby version updated** - Update base image regularly

## Integration with DevOps System

This Dockerfile works seamlessly with the DevOps deployment system:

1. **setup.sh** - Copies .env.production to .env before build, removes after
2. **deploy.sh** - Runs containers with --env-file pointing to .env.production
3. **Rails console** - Uses native bundle exec with .env.production symlink

No changes needed to existing deployment scripts!

## References

- [Docker Multi-Stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [Rails Asset Pipeline](https://guides.rubyonrails.org/asset_pipeline.html)
- [Docker Security Best Practices](https://docs.docker.com/develop/security-best-practices/)
- [Rails Credentials](https://guides.rubyonrails.org/security.html#custom-credentials)

## Version History

- **v1.0** (2025-01-26) - Initial template with multi-stage build and .env sourcing
