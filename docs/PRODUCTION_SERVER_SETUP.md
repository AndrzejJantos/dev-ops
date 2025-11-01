# Production Server Setup Guide

This guide covers the initial setup steps for a production server to support Rails applications running in Docker containers with PostgreSQL and Redis on the host.

## Prerequisites

- Ubuntu 20.04 LTS or newer (tested on Ubuntu 22.04)
- Root or sudo access
- Docker installed
- Git installed

## Step 1: Install PostgreSQL

```bash
# Update package lists
sudo apt update

# Install PostgreSQL
sudo apt install -y postgresql postgresql-contrib

# Start and enable PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

## Step 2: Configure PostgreSQL for Docker Access

### Edit postgresql.conf

Find and edit the PostgreSQL configuration file:

```bash
# Find the config file location
sudo -u postgres psql -c "SHOW config_file;"

# Edit the file (usually /etc/postgresql/14/main/postgresql.conf)
sudo nano /etc/postgresql/14/main/postgresql.conf
```

Find and change:
```ini
# From:
#listen_addresses = 'localhost'

# To:
listen_addresses = '*'
```

### Edit pg_hba.conf

```bash
# Edit pg_hba.conf (usually in same directory)
sudo nano /etc/postgresql/14/main/pg_hba.conf
```

Add these lines at the end:
```
# Allow Docker containers to connect
host    all    all    172.17.0.0/16    md5
host    all    all    192.168.0.0/16   md5
```

### Restart PostgreSQL

```bash
sudo systemctl restart postgresql
```

## Step 3: Create Application Databases and Users

For each Rails application, create a dedicated database and user:

### Brokik API

```bash
sudo -u postgres psql << EOF
-- Create user
CREATE USER brokik_user WITH PASSWORD 'CHANGE_DB_PASSWORD_HERE';

-- Create database
CREATE DATABASE brokik_production OWNER brokik_user;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE brokik_production TO brokik_user;
EOF
```

### CheaperForDrug API

```bash
sudo -u postgres psql << EOF
-- Create user
CREATE USER cheaperfordrug_user WITH PASSWORD 'CHANGE_DB_PASSWORD_HERE';

-- Create database
CREATE DATABASE cheaperfordrug_production OWNER cheaperfordrug_user;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE cheaperfordrug_production TO cheaperfordrug_user;
EOF
```

## Step 4: Install and Configure Redis

```bash
# Install Redis
sudo apt install -y redis-server

# Edit Redis configuration
sudo nano /etc/redis/redis.conf
```

Find and change:
```ini
# From:
bind 127.0.0.1 ::1

# To:
bind 0.0.0.0
```

**Security Note:** For production, consider using more restrictive binding or firewall rules.

Restart Redis:
```bash
sudo systemctl restart redis-server
sudo systemctl enable redis-server
```

## Step 5: Verify Docker Networking

Test that Docker containers can reach host services using `host.docker.internal`:

```bash
# Test PostgreSQL connectivity
docker run --rm --add-host=host.docker.internal:host-gateway postgres:14 \
  pg_isready -h host.docker.internal -p 5432

# Test Redis connectivity
docker run --rm --add-host=host.docker.internal:host-gateway redis:7 \
  redis-cli -h host.docker.internal ping
```

Expected outputs:
- PostgreSQL: `host.docker.internal:5432 - accepting connections`
- Redis: `PONG`

## Step 6: Test Database Connection

```bash
# Test PostgreSQL authentication with application user
docker run --rm -it --add-host=host.docker.internal:host-gateway postgres:14 \
  psql -h host.docker.internal -U brokik_user -d brokik_production

# You'll be prompted for password
# If successful, you'll see: brokik_production=>
```

## Step 7: Create Storage Directories

Create directories for Active Storage (file uploads):

```bash
# Create storage directories for all apps
sudo mkdir -p /var/storage/brokik-api/active_storage
sudo mkdir -p /var/storage/cheaperfordrug-api/active_storage

# Set permissions (777 allows Docker container's app user to write)
sudo chmod -R 777 /var/storage/
```

## Step 8: Security Hardening (Recommended)

### Firewall Configuration

```bash
# Install UFW if not present
sudo apt install -y ufw

# Allow SSH (important - don't lock yourself out!)
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# PostgreSQL - only allow from Docker bridge network
sudo ufw allow from 172.17.0.0/16 to any port 5432

# Redis - only allow from Docker bridge network
sudo ufw allow from 172.17.0.0/16 to any port 6379

# Enable firewall
sudo ufw enable
```

### PostgreSQL SSL (Optional but Recommended)

```bash
# Generate self-signed certificate
sudo -u postgres openssl req -new -x509 -days 365 -nodes -text \
  -out /var/lib/postgresql/14/main/server.crt \
  -keyout /var/lib/postgresql/14/main/server.key \
  -subj "/CN=postgres.example.com"

# Set permissions
sudo chmod 600 /var/lib/postgresql/14/main/server.key
sudo chown postgres:postgres /var/lib/postgresql/14/main/server.*

# Enable SSL in postgresql.conf
sudo nano /etc/postgresql/14/main/postgresql.conf
```

Add:
```ini
ssl = on
ssl_cert_file = '/var/lib/postgresql/14/main/server.crt'
ssl_key_file = '/var/lib/postgresql/14/main/server.key'
```

Restart:
```bash
sudo systemctl restart postgresql
```

## Step 9: Monitoring Setup (Optional)

### Install PostgreSQL Monitoring

```bash
# Install pg_stat_statements for query monitoring
sudo -u postgres psql -c "CREATE EXTENSION pg_stat_statements;"
```

### Install Redis Monitoring

```bash
# Check Redis stats
redis-cli info stats
```

## Verification Checklist

Before deploying applications, verify:

- [ ] PostgreSQL is running: `sudo systemctl status postgresql`
- [ ] PostgreSQL listens on all interfaces: `sudo netstat -tlnp | grep 5432`
- [ ] Redis is running: `sudo systemctl status redis-server`
- [ ] Redis listens on all interfaces: `sudo netstat -tlnp | grep 6379`
- [ ] Docker can ping host: `docker run --rm --add-host=host.docker.internal:host-gateway alpine ping -c 3 host.docker.internal`
- [ ] Database users created with correct passwords
- [ ] Databases created with correct owners
- [ ] Storage directories exist with correct permissions
- [ ] Firewall configured (if using UFW)

## Troubleshooting

### Can't connect to PostgreSQL from container

1. Check if PostgreSQL is listening:
   ```bash
   sudo netstat -tlnp | grep 5432
   ```
   Should show: `0.0.0.0:5432`

2. Check pg_hba.conf has Docker network:
   ```bash
   sudo cat /etc/postgresql/14/main/pg_hba.conf | grep 172.17
   ```

3. Check PostgreSQL logs:
   ```bash
   sudo tail -f /var/log/postgresql/postgresql-14-main.log
   ```

### Can't resolve host.docker.internal

Ensure Docker run includes:
```bash
--add-host=host.docker.internal:host-gateway
```

DevOps scripts should handle this automatically.

### Permission denied on Active Storage

```bash
# Fix permissions
sudo chmod -R 777 /var/storage/
```

## Next Steps

After server setup is complete:

1. Clone the DevOps repository
2. Configure application-specific settings in `.env.production`
3. Run the deployment scripts from `DevOps/apps/{app-name}/`

See individual application README files for deployment instructions.

## Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Redis Documentation](https://redis.io/docs/)
- [Docker Networking Documentation](https://docs.docker.com/network/)
- [DATABASE_CONNECTIVITY.md](./DATABASE_CONNECTIVITY.md) - Detailed database connectivity guide
