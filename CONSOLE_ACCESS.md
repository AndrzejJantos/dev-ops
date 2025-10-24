# Rails Console & Task Access Guide

This guide explains how to access and use the Rails console and run Rails tasks directly on the production server.

## Overview

Each application is installed in **two places**:

1. **Native Installation** (`/home/andrzej/apps/<app-name>/repo/`)
   - Full Rails environment with gems installed
   - Used for console access and running tasks
   - Connected to production database
   - Shares `.env.production` with Docker

2. **Docker Containers** (running instances)
   - Serve HTTP traffic
   - Isolated and scalable
   - Zero-downtime deployments

## 🖥️ Rails Console Access

### Using Helper Script (Recommended)

```bash
cd /home/andrzej/DevOps
./scripts/console.sh <app-name>
```

**Example:**
```bash
./scripts/console.sh cheaperfordrug-landing
```

**Output:**
```
=== Rails Console for cheaperfordrug-landing ===
Repository: /home/andrzej/apps/cheaperfordrug-landing/repo
Environment: production

Loading production environment (Rails 8.0.2)
irb(main):001:0>
```

### Manual Access

```bash
cd /home/andrzej/apps/cheaperfordrug-landing/repo
RAILS_ENV=production bundle exec rails console
```

## 💡 Console Examples

### User Management

```ruby
# Count users
User.count

# Find user
user = User.find(1)
user = User.find_by(email: 'test@example.com')

# Create user
user = User.create!(
  email: 'new@example.com',
  name: 'New User'
)

# Update user
user.update!(status: 'active')

# Delete user
user.destroy!
```

### Database Queries

```ruby
# Subscribers
Subscriber.count
Subscriber.where(status: 'active')
Subscriber.where('created_at > ?', 1.week.ago)
Subscriber.order(created_at: :desc).limit(10)

# Payments
Payment.sum(:amount)
Payment.where(status: 'completed').count
Payment.where('created_at >= ?', Date.today).sum(:amount)

# Joins and includes
Subscriber.joins(:payments).where(payments: { status: 'completed' })
Subscriber.includes(:payments).find(1)
```

### Cache Operations

```ruby
# Clear all cache
Rails.cache.clear

# Read from cache
Rails.cache.read('key')

# Write to cache
Rails.cache.write('key', 'value', expires_in: 1.hour)

# Delete from cache
Rails.cache.delete('key')

# Fetch (read or write)
Rails.cache.fetch('expensive_operation', expires_in: 1.hour) do
  # Expensive calculation
end
```

### Environment & Configuration

```ruby
# Check environment
Rails.env
Rails.env.production?

# Database configuration
ActiveRecord::Base.connection_db_config

# Check database connection
ActiveRecord::Base.connection.execute("SELECT 1")

# List tables
ActiveRecord::Base.connection.tables

# Application configuration
Rails.application.config

# Secrets and credentials
Rails.application.credentials.stripe
ENV['STRIPE_SECRET_KEY']
```

### Debugging & Inspection

```ruby
# Check model attributes
User.column_names
User.attribute_names

# Explain query
User.where(status: 'active').explain

# Benchmark
Benchmark.measure { User.all.to_a }

# Object inspection
user.inspect
user.attributes
user.methods.grep(/email/)
```

## 🔧 Running Rails Tasks

### Using Helper Script (Recommended)

```bash
cd /home/andrzej/DevOps
./scripts/rails-task.sh <app-name> <task> [args]
```

**Examples:**
```bash
# Database migrations
./scripts/rails-task.sh cheaperfordrug-landing db:migrate
./scripts/rails-task.sh cheaperfordrug-landing db:rollback STEP=1
./scripts/rails-task.sh cheaperfordrug-landing db:migrate:status
./scripts/rails-task.sh cheaperfordrug-landing db:seed
./scripts/rails-task.sh cheaperfordrug-landing db:reset

# Routes
./scripts/rails-task.sh cheaperfordrug-landing routes
./scripts/rails-task.sh cheaperfordrug-landing routes | grep users

# Runner (execute Ruby code)
./scripts/rails-task.sh cheaperfordrug-landing runner 'puts User.count'
./scripts/rails-task.sh cheaperfordrug-landing runner 'User.where(status: :inactive).destroy_all'

# Cache operations
./scripts/rails-task.sh cheaperfordrug-landing cache:clear

# Assets
./scripts/rails-task.sh cheaperfordrug-landing assets:precompile
./scripts/rails-task.sh cheaperfordrug-landing assets:clean

# Custom tasks
./scripts/rails-task.sh cheaperfordrug-landing subscribers:cleanup
./scripts/rails-task.sh cheaperfordrug-landing reports:generate
```

### Manual Execution

```bash
cd /home/andrzej/apps/cheaperfordrug-landing/repo
RAILS_ENV=production bundle exec rails <task>
```

## 📝 Common Workflows

### Running a Data Migration Script

```bash
# Create a script
cd /home/andrzej/DevOps
./scripts/console.sh cheaperfordrug-landing

# In console
Subscriber.where('created_at < ?', 1.year.ago).find_each do |sub|
  sub.update(status: 'archived')
  puts "Archived subscriber #{sub.id}"
end
```

Or using runner:
```bash
./scripts/rails-task.sh cheaperfordrug-landing runner '
  Subscriber.where("created_at < ?", 1.year.ago).find_each do |sub|
    sub.update(status: "archived")
    puts "Archived subscriber #{sub.id}"
  end
'
```

### Checking Application Health

```bash
# Database connection
./scripts/rails-task.sh cheaperfordrug-landing runner 'puts ActiveRecord::Base.connection.execute("SELECT 1").values'

# Redis connection
./scripts/rails-task.sh cheaperfordrug-landing runner 'puts Redis.new.ping'

# Check migrations
./scripts/rails-task.sh cheaperfordrug-landing db:migrate:status

# Count records
./scripts/rails-task.sh cheaperfordrug-landing runner 'puts "Users: #{User.count}, Subscribers: #{Subscriber.count}"'
```

### Generating Reports

```bash
# User report
./scripts/rails-task.sh cheaperfordrug-landing runner '
  puts "Total Users: #{User.count}"
  puts "Active Users: #{User.where(status: :active).count}"
  puts "New Users (Last 7 days): #{User.where("created_at > ?", 7.days.ago).count}"
'

# Payment report
./scripts/rails-task.sh cheaperfordrug-landing runner '
  today_revenue = Payment.where("created_at >= ?", Date.today).sum(:amount)
  puts "Today Revenue: $#{today_revenue}"
'
```

### Bulk Operations

```bash
# Bulk update
./scripts/rails-task.sh cheaperfordrug-landing runner '
  User.where(email_verified: false).update_all(status: :pending)
'

# Bulk delete old records
./scripts/rails-task.sh cheaperfordrug-landing runner '
  Payment.where("created_at < ?", 2.years.ago).delete_all
'
```

## 🗂️ File Locations

### Application Code
```
/home/andrzej/apps/<app-name>/repo/
├── app/                    # Application code
├── config/                 # Configuration
├── db/                     # Database & migrations
├── log/                    # Rails logs
├── vendor/bundle/          # Installed gems
└── .env.production         # Environment (symlink)
```

### Environment Variables
```
/home/andrzej/apps/<app-name>/.env.production  # Actual file
/home/andrzej/apps/<app-name>/repo/.env.production  # Symlink
```

### Logs
```
/home/andrzej/apps/<app-name>/repo/log/production.log
```

## ⚠️ Safety Tips

### 1. Always Confirm Destructive Operations

```ruby
# Bad
User.delete_all

# Good - check first
users = User.where(status: :inactive)
puts "About to delete #{users.count} users"
# Manually confirm, then:
users.delete_all
```

### 2. Use Transactions for Critical Operations

```ruby
ActiveRecord::Base.transaction do
  user.update!(status: :active)
  user.subscriptions.update_all(active: true)
  # If anything fails, everything rolls back
end
```

### 3. Test Queries Before Executing

```ruby
# See what will be affected
User.where(status: :inactive).to_sql
User.where(status: :inactive).count

# Then execute
User.where(status: :inactive).destroy_all
```

### 4. Backup Before Bulk Changes

```bash
# Create database backup
cd /home/andrzej/DevOps
./scripts/rails-task.sh cheaperfordrug-landing runner '
  require "fileutils"
  timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
  `sudo -u postgres pg_dump cheaperfordrug_landing_production | gzip > /home/andrzej/apps/cheaperfordrug-landing/backups/manual_#{timestamp}.sql.gz`
'
```

## 🔍 Troubleshooting

### Console Won't Start

```bash
# Check bundle is installed
cd /home/andrzej/apps/cheaperfordrug-landing/repo
bundle check

# Reinstall if needed
RAILS_ENV=production bundle install --path vendor/bundle
```

### Database Connection Error

```bash
# Test database connection
psql -U postgres -d cheaperfordrug_landing_production -c "SELECT 1;"

# Check environment variables
cd /home/andrzej/apps/cheaperfordrug-landing/repo
grep DATABASE_URL ../.env.production
```

### Missing Gem Error

```bash
# Update gems
cd /home/andrzej/apps/cheaperfordrug-landing/repo
RAILS_ENV=production bundle install --path vendor/bundle
```

### Permission Denied

```bash
# Fix ownership
sudo chown -R andrzej:andrzej /home/andrzej/apps/cheaperfordrug-landing/repo
```

## 📚 Additional Resources

### Rails Console Shortcuts

```ruby
# Reload console
reload!

# Clear screen
system 'clear'

# Show SQL queries
ActiveRecord::Base.logger = Logger.new(STDOUT)

# Disable SQL logging
ActiveRecord::Base.logger = nil

# Pretty print
pp User.first

# Get helper methods
helper.link_to('text', '/')
```

### Environment Variables

All environment variables from `.env.production` are available:

```ruby
ENV['DATABASE_URL']
ENV['REDIS_URL']
ENV['STRIPE_SECRET_KEY']
ENV['MAILGUN_API_KEY']
```

### Useful Gems in Console

```ruby
# Benchmark
Benchmark.measure { expensive_operation }

# Hirb (if installed) - better table output
require 'hirb'
Hirb.enable

# Awesome Print (if installed)
require 'awesome_print'
ap User.first
```

## 🎓 Best Practices

1. **Use transactions** for multi-step operations
2. **Test queries** with `.to_sql` and `.count` first
3. **Limit results** with `.limit(10)` when exploring data
4. **Use `.find_each`** for batch processing large datasets
5. **Monitor memory** usage during bulk operations
6. **Create backups** before destructive operations
7. **Log important actions** for audit trail
8. **Exit cleanly** with `exit` or Ctrl+D

## 📞 Quick Reference

```bash
# Console access
./scripts/console.sh cheaperfordrug-landing

# Run migrations
./scripts/rails-task.sh cheaperfordrug-landing db:migrate

# Check routes
./scripts/rails-task.sh cheaperfordrug-landing routes

# Execute Ruby code
./scripts/rails-task.sh cheaperfordrug-landing runner 'puts User.count'

# View logs
tail -f /home/andrzej/apps/cheaperfordrug-landing/repo/log/production.log
```

---

**Need help?** Contact andrzej@webet.pl
