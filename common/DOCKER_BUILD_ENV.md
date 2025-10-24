# Docker Build Environment Variables

## Problem

When building Docker images for Rails or Node.js applications, the build process often requires environment variables that:
- Are not available at build time
- Would be security risks to hardcode in Dockerfiles
- Vary between environments (dev, staging, production)

Common examples:
- `MAILGUN_API_KEY` - Used in Rails production.rb configuration
- `STRIPE_SECRET_KEY` - Payment gateway credentials
- `DATABASE_URL` - Database connection strings
- Other API keys and secrets

## Solution

Our DevOps scripts automatically create a temporary `.env` file with dummy values before each Docker build, then remove it after the build completes.

### How It Works

1. **Before Docker Build**: A `.env` file is created in the repo directory with safe dummy values
2. **During Build**: The Dockerfile can use these values (if the app is configured to load .env files)
3. **After Build**: The temporary `.env` file is automatically deleted
4. **At Runtime**: Real environment variables are provided via `docker run --env-file`

### Implementation

This happens automatically in:
- `common/rails/setup.sh` - Initial Docker image build during setup
- `common/docker-utils.sh` - All Docker builds (deployments, rebuilds)

### Dummy Values Used

```bash
# Database (not used during build)
DATABASE_URL=postgresql://dummy:dummy@localhost/dummy
REDIS_URL=redis://localhost:6379/0

# API Keys (dummy values for build)
MAILGUN_API_KEY=dummy_key_for_build
STRIPE_PUBLISHABLE_KEY=pk_test_dummy_for_build
STRIPE_SECRET_KEY=sk_test_dummy_for_build
GOOGLE_ANALYTICS_ID=G-XXXXXXXXXX
GOOGLE_TAG_MANAGER_ID=GTM-XXXXXXX
FACEBOOK_PIXEL_ID=000000000000000
ROLLBAR_ACCESS_TOKEN=dummy_token_for_build
SECRET_KEY_BASE=dummy_secret_key_base_for_build_only

# Rails environment
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

# Node.js environment
NODE_ENV=production
```

## Requirements for Your Application

### For Rails Apps

Your Dockerfile should use a gem that loads `.env` files, such as:
- `dotenv-rails` (recommended)
- `figaro`
- Or load the `.env` file manually in your config

**Example Dockerfile snippet:**
```dockerfile
# Make sure your Gemfile includes dotenv-rails
# Then the .env file will be automatically loaded during asset precompilation
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
```

**Alternative**: If you don't want to use dotenv, modify your `config/environments/production.rb` to provide defaults:
```ruby
# Instead of:
config.action_mailer.mailgun_settings = {
  api_key: ENV.fetch('MAILGUN_API_KEY')
}

# Use:
config.action_mailer.mailgun_settings = {
  api_key: ENV.fetch('MAILGUN_API_KEY', 'dummy_key_for_build')
}
```

### For Node.js Apps

If your app loads environment variables during build (e.g., for webpack configurations), ensure you use a library like:
- `dotenv` (standard)
- `dotenv-webpack`

**Example package.json build script:**
```json
{
  "scripts": {
    "build": "node -r dotenv/config ./node_modules/.bin/webpack"
  }
}
```

## Security Notes

✅ **Safe**: Dummy values are only used during Docker image build
✅ **Temporary**: The `.env` file is deleted immediately after build
✅ **Runtime**: Real secrets are provided via `--env-file` at container startup
✅ **Git**: The temporary `.env` is never committed (should be in `.gitignore`)

## Troubleshooting

### Error: "key not found: SOME_VAR_NAME"

If you encounter this error during Docker build:

1. **Add the variable to the dummy env**: Edit `common/docker-utils.sh` and add your variable to the heredoc:
   ```bash
   SOME_VAR_NAME=dummy_value_for_build
   ```

2. **Or modify your app**: Use `ENV.fetch('SOME_VAR_NAME', 'default')` instead of `ENV.fetch('SOME_VAR_NAME')`

### Docker Build Not Finding .env File

Ensure your Dockerfile doesn't have `.env` in `.dockerignore`. However, the temporary `.env` should be in your repository's `.gitignore`.

## Benefits

✅ **Works for all apps**: No need to modify Dockerfiles for each app
✅ **Secure**: No secrets in Dockerfiles or git history
✅ **Flexible**: Easy to add new dummy variables
✅ **Clean**: Temporary file is always cleaned up
✅ **Standard**: Uses standard `.env` file convention

---

**Last Updated**: October 2024
