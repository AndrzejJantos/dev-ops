# Node.js Application Template

This is a template for deploying Node.js applications using the modular DevOps deployment system.

## Quick Start

```bash
# 1. Copy this template to your app name
cd ~/DevOps/apps
cp -r _examples/nodejs-app-template my-nodejs-app
cd my-nodejs-app

# 2. Edit configuration
nano config.sh
# Update: APP_NAME, REPO_URL, DOMAIN, BASE_PORT, REDIS_DB_NUMBER
# Set feature flags: NEEDS_POSTGRES, NEEDS_REDIS, NEEDS_MAILGUN, NEEDS_MIGRATIONS

# 3. Run setup
./setup.sh

# 4. Edit environment variables
nano ~/apps/my-nodejs-app/.env.production

# 5. Deploy
./deploy.sh deploy
```

## Configuration Checklist

### Required Changes in config.sh

- [ ] `APP_NAME` - Unique app name (no spaces, use hyphens)
- [ ] `APP_DISPLAY_NAME` - Human-readable name
- [ ] `REPO_URL` - Your Git repository URL
- [ ] `REPO_BRANCH` - Branch to deploy (usually 'main' or 'master')
- [ ] `DOMAIN` - Your domain name
- [ ] `BASE_PORT` - Unique port range start (3020, 3030, 3040, etc.)
- [ ] `REDIS_DB_NUMBER` - Unique Redis database number (1-15)

### Feature Flags

Set these based on your application:

```bash
export NEEDS_POSTGRES=true      # PostgreSQL database
export NEEDS_REDIS=true          # Redis cache/queue
export NEEDS_MAILGUN=true        # Email notifications
export NEEDS_MIGRATIONS=true     # Database migrations
```

### Application Environment Variables

Add your app-specific env vars to `APP_ENV_VARS` array:

```bash
export APP_ENV_VARS=(
    "JWT_SECRET=generate_a_secure_secret"
    "API_KEY=your_api_key"
    "STRIPE_SECRET_KEY=sk_live_xxx"
)
```

## Customization

### Override Build Process

If your app needs custom build steps:

```bash
# In setup.sh
nodejs_build_application() {
    log_info "Custom build with TypeScript..."
    cd "$REPO_DIR"

    npm ci
    npm run lint
    npm run test
    npm run build

    return 0
}
```

### Add Custom Health Check Path

If your app uses a different health endpoint:

```bash
# In config.sh
export HEALTH_CHECK_PATH="/api/health"  # Instead of default /health
```

### Custom Migrations

If using Prisma, Sequelize, or other ORM:

```bash
# In deploy.sh
nodejs_check_pending_migrations() {
    local test_container="$1"

    # Check Prisma migrations
    local output=$(docker exec "$test_container" npx prisma migrate status 2>&1)

    if echo "$output" | grep -q "pending"; then
        return 0
    fi

    return 1
}

nodejs_run_migrations_with_backup() {
    local test_container="$1"

    # Backup database
    if [ "${NEEDS_POSTGRES}" = "true" ]; then
        backup_database "$DB_NAME" "$BACKUP_DIR"
    fi

    # Run Prisma migrations
    docker exec "$test_container" npx prisma migrate deploy

    return $?
}
```

## Package.json Requirements

### Required Scripts

Your package.json should have:

```json
{
  "scripts": {
    "start": "node dist/index.js",
    "build": "tsc"  // or webpack, etc.
  }
}
```

### Optional Scripts

```json
{
  "scripts": {
    "migrate": "npx prisma migrate deploy",
    "migrate:status": "npx prisma migrate status"
  }
}
```

## Dockerfile Example

Your Dockerfile should:

```dockerfile
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --production

# Copy app code
COPY . .

# Build if needed
RUN npm run build

# Expose port 80 (required!)
EXPOSE 80

# Start command
CMD ["npm", "start"]
```

**Important:** Container must listen on port 80 internally!

## Health Check Endpoint

Your app must implement a health check endpoint:

```javascript
// Express example
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

// Fastify example
fastify.get('/health', async (request, reply) => {
  return { status: 'ok' };
});
```

## Environment Variables

Your app will receive these automatically:

```bash
NODE_ENV=production
PORT=80  # Container internal port
DATABASE_URL=postgresql://...  # If NEEDS_POSTGRES=true
REDIS_URL=redis://...           # If NEEDS_REDIS=true
# Plus all variables from APP_ENV_VARS
```

## Database Migrations

If `NEEDS_MIGRATIONS=true`, ensure your app supports:

1. **Check migration status** - Via npm script or command
2. **Run migrations** - Via npm script `migrate`
3. **Automatic migration on deploy** - Will backup DB first

## Deployment Commands

```bash
# Deploy with default scale (2 instances)
./deploy.sh deploy

# Deploy with specific scale
./deploy.sh deploy 4

# Restart containers
./deploy.sh restart

# Scale up/down
./deploy.sh scale 6

# Stop all containers
./deploy.sh stop

# Show help
./deploy.sh help
```

## Port Allocation

Your app gets a 10-port range:

- BASE_PORT=3020 → Ports 3020-3029
- Supports up to 10 container instances
- Nginx load balances across all instances

## Nginx Configuration

If you need custom Nginx config, create `nginx.conf.template`:

```nginx
upstream {{NGINX_UPSTREAM_NAME}} {
    least_conn;
{{UPSTREAM_SERVERS}}
}

server {
    listen 80;
    server_name {{DOMAIN}};

    # Custom settings here
    client_max_body_size 50M;

    location / {
        proxy_pass http://{{NGINX_UPSTREAM_NAME}};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    location /api/ {
        # Custom API settings
        proxy_pass http://{{NGINX_UPSTREAM_NAME}};
        proxy_read_timeout 300s;
    }
}
```

Variables available:
- `{{NGINX_UPSTREAM_NAME}}` - Upstream block name
- `{{UPSTREAM_SERVERS}}` - Generated server list
- `{{DOMAIN}}` - Your domain
- `{{APP_NAME}}` - App name

## Troubleshooting

### Container won't start

```bash
# Check logs
docker logs my-nodejs-app_web_1

# Check environment
docker exec my-nodejs-app_web_1 env

# Test manually
docker run -it --env-file ~/apps/my-nodejs-app/.env.production my-nodejs-app /bin/sh
```

### Health check fails

```bash
# Test endpoint
curl http://localhost:3020/health

# Check container response
docker exec my-nodejs-app_web_1 curl http://localhost:80/health
```

### Database connection fails

```bash
# Test PostgreSQL
docker exec my-nodejs-app_web_1 node -e "
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
pool.query('SELECT 1').then(() => console.log('OK')).catch(console.error);
"
```

## Examples

### Express.js API

```javascript
// index.js
const express = require('express');
const app = express();

app.get('/health', (req, res) => res.send('OK'));
app.get('/api/users', (req, res) => res.json({ users: [] }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server on port ${PORT}`));
```

### Fastify API

```javascript
// index.js
const fastify = require('fastify')({ logger: true });

fastify.get('/health', async () => ({ status: 'ok' }));
fastify.get('/api/users', async () => ({ users: [] }));

fastify.listen({ port: process.env.PORT || 3000, host: '0.0.0.0' });
```

### NestJS

```typescript
// main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  await app.listen(process.env.PORT || 3000, '0.0.0.0');
}
bootstrap();
```

## Next Steps

1. Copy and customize this template
2. Test setup locally
3. Run setup on server
4. Deploy and monitor
5. Scale as needed

## Support

See main documentation:
- `/Users/andrzej/Development/DevOps/ARCHITECTURE.md`
- `/Users/andrzej/Development/DevOps/MIGRATION_GUIDE.md`
